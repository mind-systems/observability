# Plan Review 2: Server Docker Compose

**Plan:** `.ai-factory/plans/01-server-docker-compose.md`
**Spec note:** `.ai-factory/notes/08-server-docker-compose.md`
**Prior review:** `.ai-factory/plan-reviews/01-server-docker-compose-plan-review-1.md`
**Files Reviewed:** plan v2 + spec note + `backend/loki/loki.yaml`, `backend/grafana/grafana.ini`, `backend/grafana/provisioning/datasources/loki.yaml`, root `Makefile`, `.ai-factory/ROADMAP.md`, `.ai-factory/ARCHITECTURE.md`, `observe-write-proxy/` (`Dockerfile`, `.dockerignore`, `internal/config/config.go`, `internal/store/store.go`, `cmd/proxy/main.go`)
**Risk Level:** 🟡 Medium

## Regression check against plan-review-1

All five findings from review-1 are resolved correctly by this revision:

- **Critical #1 (Grafana `${VAR:-default}` unsupported):** resolved. Task 2 drops env interpolation entirely and uses a Docker-specific datasource file (`loki.datasource.docker.yaml`) with a literal `url: http://loki:3100`, overlaid via a more-specific bind-mount. The native file is genuinely untouched. Design decision #2/#3 states this explicitly.
- **Critical #2 (native `loki.yaml` not container-portable):** resolved. Task 1 creates `loki.docker.yaml` with literal `/loki` paths and no `${HOME}`, so no `-config.expand-env=true` is needed and data lands on the `loki-data` volume.
- **Critical #3 (dropped `-querier.query-ingesters-within=0`):** resolved. Task 3's Loki `command` retains the flag.
- **Security #4 (`admin/admin` on a server):** resolved. Task 3 sets `GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:?...}` (correct compose-side interpolation, which *does* support `:?`), Task 4 adds `.env.example` + gitignore + reverse-proxy/TLS warning.
- **Other (`:latest`):** resolved. Task 6 pins explicit tags; `:latest` explicitly forbidden.

The overlay bind-mount approach (whole `provisioning/` tree + a more-specific file mount onto `datasources/loki.yaml`) is sound: Docker resolves nested mounts by destination depth regardless of declaration order, so Grafana sees exactly one Loki datasource pointing at `loki:3100`, and no duplicate is auto-loaded since the Docker-specific file lives outside `provisioning/`. Verified there is only one file under `provisioning/` (`datasources/loki.yaml`) and no dashboards provisioning to worry about.

Env/port wiring re-verified against `observe-write-proxy/internal/config/config.go`: `LOKI_URL`/`GRAFANA_URL`/`DB_PATH` names and `:4318` default are exact; `LOKI_URL` is correctly the base URL (proxy joins `/otlp/v1/logs` later); `GRAFANA_URL=http://grafana:3000` correctly uses the internal port. `grafana.ini` bakes no `paths.*` (they come from `GF_PATHS_*`), and the Grafana image's default `GF_PATHS_PROVISIONING=/etc/grafana/provisioning` / `GF_PATHS_DATA=/var/lib/grafana` line up with the plan's mounts — so removing the Makefile's `GF_PATHS_*` injection is harmless here.

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** ⚠️ WARN. ARCHITECTURE.md still states hard "no Docker" rules in four places (line 13 "Hard constraints: no Docker", line 24 "NO Docker", line 46 "❌ Any component → Docker", line 63 "Native, no Docker", line 107 "❌ Introducing Docker … just to get started"). This plan introduces Docker for the server path. Task 5 correctly *recommends* (out of scope, note-only) adding a "Server deployment (Docker) — additive, separate from the native macOS path" carve-out. The contradiction remains documented-but-unresolved; acceptable given the plan's `Docs: no` setting and the additive design, but the carve-out should not be forgotten when docs are next in scope.
- **Rules (`.ai-factory/RULES.md`):** not present — skipped.
- **Roadmap (`.ai-factory/ROADMAP.md`):** ✅ Linked (Phase 4 → "Server Docker Compose"). The ROADMAP line still carries the broken `${LOKI_INTERNAL_URL:-http://localhost:3100}` mechanism and the "one conflict … parameterize" premise; Task 5 explicitly reconciles both the ROADMAP line and the spec note with the corrected design. Good — this closes review-1's note that the flaw must be fixed in all three artifacts.
- **skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`):** not present — no project overrides applied.

## Critical Issues

### 1. `proxy-data:/data` volume will be root-owned; the distroless non-root proxy (uid 65532) cannot create `/data/proxy.db` → startup crash

The plan (Design decision "Proxy wiring is kept verbatim" and Task 3) treats `proxy-data:/data` + `DB_PATH=/data/proxy.db` as confirmed-correct. But the runtime permissions do not line up:

- `observe-write-proxy/Dockerfile` final stage is `gcr.io/distroless/static:nonroot`, runs `USER nonroot:nonroot` (uid 65532), and **never creates `/data`** (only `COPY --from=build /proxy /proxy`).
- A fresh **named volume** mounted at a path that does **not** exist in the image is initialized empty and owned by **root:root**. Docker only copies ownership onto a fresh named volume when the mount path already exists in the image — here it doesn't.
- At startup `internal/store/store.go` runs `os.MkdirAll("/data", 0o755)` (a no-op since the mountpoint already exists, root-owned) then opens SQLite at `/data/proxy.db`. Creating the DB file as uid 65532 in a root:root `0755` directory fails with `EACCES`, so `store.Open` errors and `cmd/proxy/main.go` calls `os.Exit(1)`.

Net effect: the proxy container crash-loops on a clean deploy, and since `observe-write-proxy` is the only host-exposed OTLP write path, SDK writes never land. This directly defeats the plan's deliverable ("correct, ready-to-run files"). The Dockerfile comment itself flags the requirement ("DB_PATH must point inside a mounted volume writable by uid 65532") but nothing in the plan or the image satisfies it.

The proper fix is a one-line change in the **`observe-write-proxy` repo** (out of this plan's stated file scope), e.g. create `/data` owned by `nonroot` in the builder stage and `COPY --from=build --chown=nonroot:nonroot /data /data` into the final stage (distroless has no shell, so a `RUN mkdir` in the final stage is not possible). Because it is cross-repo, the plan should at minimum:
- add an explicit note/dependency that the proxy image must ship a `/data` directory owned by uid 65532 before this stack can start, and
- stop asserting the `proxy-data` volume is "correct" without that precondition.

Contrast: the `grafana/loki` and `grafana/grafana` images create and chown their data dirs (`/loki`, `/var/lib/grafana`) to their non-root runtime users, so `loki-data`/`grafana-data` inherit correct ownership — those two are genuinely fine. Only the proxy volume is affected.

## Other Findings

- **Loki/Grafana healthcheck binary (verify, likely OK).** Task 3 uses `wget -qO- localhost:3100/ready` (Loki) and `wget -qO- localhost:3000/api/health` (Grafana). Both `grafana/loki` and `grafana/grafana` are Alpine/BusyBox-based and ship `wget`, and Grafana's own reference docker-compose examples use exactly this Loki healthcheck — so this should work. Worth a one-line confirmation at the pinned versions chosen in Task 6, since if `wget` were absent the healthcheck would fail and `grafana`/`proxy` would never start (both gate on `service_healthy`). Non-blocking.
- **No `restart:` policy (server-deployment gap).** For a *server* target, none of the three services declares `restart: unless-stopped` (or `on-failure`). Without it, a crash or host reboot leaves the stack down. Recommend adding a restart policy to all three services — this is exactly the kind of production concern a server compose file exists to encode. Minor.
- **Grafana admin password reset semantics (informational).** `GF_SECURITY_ADMIN_PASSWORD` is re-applied by Grafana on every startup, so rotating the value in `.env` takes effect on restart even on an existing `grafana-data` volume — the intended behavior, no action needed. Noted only to preempt a "does this work after first boot?" question.
- **Task 6 version pinning must land on Loki 3.x.** The plan already flags the config as "Loki 3.x-shaped" (`tsdb`/schema v13/`parallelise_shardable_queries`/`disk_full_threshold`). Emphasize: the pinned Loki tag must be a 3.x line — a 2.x pin would reject this config. Determining from the Homebrew binary (`loki --version`) is the right source. Guidance is present; just ensuring it isn't lost.

## Positive Notes

- Clean, disciplined resolution of every review-1 defect without touching a single native file — the `*.docker.yaml` parallel-file strategy plus the overlay bind-mount is the right way to keep the compose layer purely additive.
- Correct use of compose-native `${VAR:?err}` / `${VAR:-default}` interpolation (which *is* supported by Docker Compose) exactly where Grafana provisioning interpolation is *not* — the distinction that broke review-1 is now handled at the right layer.
- `depends_on: { condition: service_healthy }` with real healthchecks upgrades review-1's "start-order only" caveat to genuine readiness gating.
- Task 5 explicitly reconciles the spec note **and** the ROADMAP line, closing the "fix must be mirrored to all three artifacts" requirement from review-1.
- Security posture materially improved: required admin password via `.env`, secret gitignored, `.env.example` committed, and an explicit reverse-proxy/TLS / loopback-binding warning for the `3030` publish.

## Verdict

The plan is structurally sound and resolves all of plan-review-1's issues. The remaining substantive risk is cross-repo: the `observe-write-proxy` distroless image does not create a `/data` directory owned by its non-root uid, so the `proxy-data` named volume will be root-owned and the proxy will crash on first start (Critical #1). Because the stack's only write path depends on it, this should be addressed — via a proxy-image fix plus an explicit dependency note in this plan — before the compose file is considered "ready to run." The restart-policy and healthcheck-binary items are minor hardening. Recommend one revision to acknowledge/handle the proxy volume ownership precondition.
