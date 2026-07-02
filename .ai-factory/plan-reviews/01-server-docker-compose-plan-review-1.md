# Plan Review: Server Docker Compose

**Plan:** `.ai-factory/plans/01-server-docker-compose.md`
**Spec note:** `.ai-factory/notes/08-server-docker-compose.md`
**Files Reviewed:** plan + spec note + `backend/loki/loki.yaml`, `backend/grafana/grafana.ini`, `backend/grafana/provisioning/datasources/loki.yaml`, root `Makefile`, `observe-write-proxy/` (config, Dockerfile)
**Risk Level:** 🔴 High

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** ⚠️ WARN. ARCHITECTURE.md lists `❌ Any component → Docker` as a hard dependency rule and anti-pattern, and `Native, no Docker` as a key principle. This plan introduces Docker. The intended reconciliation is "server-only, additive, native path untouched," which is legitimate — but ARCHITECTURE.md has **no server-deployment carve-out** documented, and the plan's own promise (native path stays valid) does not actually hold (see Critical #1 and #2). Recommend adding a short "Server deployment (Docker) — separate from the native macOS path" note to ARCHITECTURE.md so the Docker layer is a sanctioned exception rather than a silent contradiction. Docs are out of scope for this plan per its Settings, so this is a WARN, not a blocker.
- **Rules (`.ai-factory/RULES.md`):** not present — skipped.
- **Roadmap (`.ai-factory/ROADMAP.md`):** ✅ Linked. Maps 1:1 to Phase 4 → "Server Docker Compose". Note that the flawed datasource mechanism (`${LOKI_INTERNAL_URL:-http://localhost:3100}`) is inherited verbatim from the ROADMAP line and the spec note — so Critical #1 must be fixed in the ROADMAP entry and the spec note too, not only in the plan.
- **skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`):** not present — no project overrides applied.

## Critical Issues

### 1. Grafana does not support the `${VAR:-default}` default-value syntax — Task 1 breaks BOTH the native and the Docker datasource

Task 1 changes the datasource URL to `${LOKI_INTERNAL_URL:-http://localhost:3100}` and claims "Grafana v8+ supports env-var substitution in provisioning files" with the `:-default` preserving the native path. **The `:-default` (bash parameter-expansion) form is not supported by Grafana.** Grafana provisioning interpolation supports only `$VAR` and `${VAR}`; there is no default-value operator (confirmed against the current official "Provision Grafana" docs and multiple tracked issues).

Consequences of writing `url: ${LOKI_INTERNAL_URL:-http://localhost:3100}`:
- Grafana treats the braced content as a single variable **name** — `LOKI_INTERNAL_URL:-http://localhost:3100` — which never matches the actual `LOKI_INTERNAL_URL` var. So even the **Docker path breaks**: with `LOKI_INTERNAL_URL=http://loki:3100` set, the lookup is for the malformed name, not `LOKI_INTERNAL_URL`, and resolves to empty/literal.
- The **native Homebrew path breaks** too: with no env var set, the URL resolves to empty (or the literal unexpanded string). Either way the Loki datasource points nowhere — a regression to the currently-working native setup, which is the project's primary supported path.

This is the central mechanism of the plan and it does not work as specified. Fix direction (pick one, then update plan + note + ROADMAP):
- Use plain `url: ${LOKI_INTERNAL_URL}` **and** always provide the variable — including in the native launch (e.g. export `LOKI_INTERNAL_URL=http://localhost:3100` in the Makefile's `backend-up` Grafana invocation). This does touch the native run config, contradicting the plan's "no other backend files change," so state that explicitly.
- Or keep `url: http://localhost:3100` hardcoded for native and mount a **Docker-only** datasource provisioning file (or an override dir) that uses `http://loki:3100`, so the native file is genuinely untouched.

### 2. The mounted `loki.yaml` storage paths and env expansion do not work inside the container — Loki won't persist to the `/loki` volume (and may fail to start)

The plan asserts "backend/loki/loki.yaml … already match[es] the compose file — leave untouched." It does not match:

- `loki.yaml` sets `path_prefix`, `chunks_directory`, `rules_directory`, and `wal.dir` to `${HOME}/.local/share/observe/loki/...`. These are expanded **only** because the native run passes `-config.expand-env=true` (Makefile line 30). The compose `command` is just `-config.file=/etc/loki/local-config.yaml` — **`-config.expand-env=true` is missing**, so `${HOME}` is not expanded. Loki will use the literal `${HOME}/...` path or fail config validation at startup.
- Even if `-config.expand-env=true` were added, `$HOME` inside the `grafana/loki` image is not `/loki`. Data would land under `$HOME/.local/share/observe/loki` (or `/.local/...`), **not** the mounted `loki-data:/loki` named volume. The volume mount would receive nothing, so the intended persistence silently does not happen — logs are lost on container replacement.

The Docker path needs its own Loki storage config pointing at `/loki` (the mounted volume), e.g. a Docker-specific config file with `path_prefix: /loki` and matching chunks/rules/wal dirs, or a config that does not depend on `${HOME}`. This is a real "wrong assumption about the codebase" — the native config is not container-portable.

### 3. Native Loki runtime flag `-querier.query-ingesters-within=0` is dropped in the compose command

The native launch also passes `-querier.query-ingesters-within=0` (Makefile line 31), which matters for reading recently-written logs on a single-binary instance. The compose command omits it. Depending on defaults this can make freshly-ingested logs temporarily unqueryable through the Grafana datasource. Add the same flag to the Loki service `command` (or justify its omission).

## Security Issues

### 4. Grafana ships with `admin/admin` on a server-exposed instance

`grafana/grafana.ini` hardcodes `admin_user = admin` / `admin_password = admin`, and it is mounted read-only into the container. The compose file (as specced) does **not** set `GF_SECURITY_ADMIN_PASSWORD`, and Grafana is published on `3030:3000` (bound to all interfaces by default) on a *server*. That is default-credentials exposure on a network-reachable admin UI. The spec note mentions this only as a passing comment; the file to be created omits any mitigation. Add `GF_SECURITY_ADMIN_PASSWORD` (sourced from an env/secret) to the grafana service, and consider not publishing Grafana on `0.0.0.0` without a reverse proxy/TLS. For a server target this should be treated as blocking, not advisory.

## Other Findings

- **`:latest` image tags (maintainability/correctness).** `grafana/loki:latest` and `grafana/grafana:latest` are unpinned. Loki config is version-sensitive (this config is Loki 3.x-shaped: `tsdb`/`schema v13`, `parallelise_shardable_queries`, `disk_full_threshold`). A `latest` that rolls to an incompatible major will break the deployment non-reproducibly. Pin explicit versions (ideally matching the Homebrew-tested versions).
- **`depends_on` is start-order only (minor).** `observe-write-proxy` depends_on `[loki, grafana]` and grafana depends_on `[loki]`, but plain `depends_on` waits for container start, not readiness. The proxy validates admin tokens against Grafana and forwards to Loki; on cold start it may briefly see them unreachable (proxy returns 503 until they're up). Acceptable for now, but consider `condition: service_healthy` with healthchecks. Not blocking.

## Positive Notes

- **observe-write-proxy wiring is correct.** Env var names (`LOKI_URL`, `GRAFANA_URL`, `DB_PATH`) and the `:4318` listen/port match `observe-write-proxy/internal/config/config.go` exactly; the `Dockerfile` exists; `build: ../observe-write-proxy` resolves correctly relative to `backend/`; `LOKI_URL` is correctly the base URL (proxy appends `/otlp/v1/logs`); `GRAFANA_URL=http://grafana:3000` correctly uses the internal port, not the `3030` host mapping; `DB_PATH=/data/proxy.db` on the `proxy-data` volume matches the container-image design (uid 65532 non-root, DB must live on a mounted volume).
- **Topology is sound.** Loki internal-only, reads via the Grafana datasource proxy, writes via the Bearer-authenticated proxy — matches the architecture's read/write split.
- **Line reference corrected.** Task 1 correctly targets line 7 of `datasources/loki.yaml` (the note's "line 6" was stale).
- **"Write only, do NOT run" constraint** correctly respects the no-Docker dev-machine rule.

## Verdict

The plan has two path-breaking defects (Grafana default-syntax that works in neither mode; a Loki config/volume mismatch that defeats persistence and may block startup), one dropped runtime flag, and a server-exposed default-credentials issue. The "no other backend files change / already matches" premise is incorrect. These must be resolved — and mirrored back into the spec note and the ROADMAP line — before implementation.
