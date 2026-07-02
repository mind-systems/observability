# Code Review: Server Docker Compose

**Plan:** `.ai-factory/plans/01-server-docker-compose.md`
**Reviewed:** `git diff HEAD` + `git status` (root repo) and the uncommitted change in the sibling `observe-write-proxy` repo.
**Files reviewed in full:** `backend/docker-compose.yml`, `backend/loki/loki.docker.yaml`, `backend/grafana/loki.datasource.docker.yaml`, `backend/.env.example`, `backend/.gitignore`, root `.gitignore` diff, `.ai-factory/ROADMAP.md` / `.ai-factory/notes/08-server-docker-compose.md` reconciliation, and `observe-write-proxy/Dockerfile` + `internal/store/store.go`.
**Risk level:** 🟢 Low — no correctness, security, or runtime-breaking defects found.

## Summary

The change adds `backend/docker-compose.yml` (Loki internal-only + Grafana `3030:3000` + observe-write-proxy `4318:4318` on `obs-net` with three named volumes), two Docker-specific config files (`loki.docker.yaml`, `loki.datasource.docker.yaml`), an `.env.example` + `.gitignore`, and reconciles the ROADMAP/spec note. It also carries the cross-repo `observe-write-proxy/Dockerfile` fix (Task 7). All native Homebrew files are byte-for-byte untouched, as required.

Every issue from the three prior plan-reviews is resolved in the shipped code, and the one place the implementation deviated from the plan (the Loki healthcheck) is a correct improvement, not a regression.

## Verification performed (make-or-break items confirmed against the pinned versions)

The stack gates startup on healthchecks (`grafana` and `observe-write-proxy` both `depends_on: { condition: service_healthy }`), so a wrong healthcheck would silently prevent the whole stack from starting. I verified each against the pinned image tags:

- **Loki healthcheck `["CMD", "/usr/bin/loki", "-health"]` — CORRECT.** The plan specified a `wget … /ready` check. The implementer changed it, with a comment explaining that `grafana/loki` is distroless. Confirmed against `grafana/loki` `v3.7.2`:
  - The image is `FROM gcr.io/distroless/static:nonroot` (no shell, no wget/curl), so the plan's `wget` check — and plan-review-2's "wget is present, this works" claim — **would have failed**. Docker healthchecks on Loki were broken by the 3.6.0 distroless migration (grafana/loki issue #20149).
  - The native `-health` command exists in `v3.7.2` (`cmd/loki/main.go` contains `CheckHealth(os.Args[1:])`; backported to 3.6.x via PR #20590). It runs before config parsing and defaults to `-health.url=http://localhost:3100/ready`, matching the `http_listen_port: 3100` in `loki.docker.yaml`. No `-config.file` is needed for it.
  - The binary path `/usr/bin/loki` matches the image's `COPY … /usr/bin/loki` / `ENTRYPOINT ["/usr/bin/loki"]`.
- **Grafana healthcheck `wget -qO- http://localhost:3000/api/health` — CORRECT.** `grafana/grafana` `v13.0.2` is alpine-based (`alpine:3.23.4`) and installs `curl` plus ships busybox `wget`; `/api/health` returns 200 when the DB is OK. Tag `13.0.2` exists on Docker Hub.
- **Proxy `/data` ownership (Task 7) — RESOLVED.** `observe-write-proxy/Dockerfile` now does `RUN mkdir -p /data && chown 65532:65532 /data` in the builder stage and `COPY --from=build --chown=65532:65532 /data /data` into the distroless final stage. `store.Open`'s `os.MkdirAll("/data", …)` is then a no-op on the pre-existing dir owned by uid 65532, and SQLite creates `/data/proxy.db` successfully — the crash-loop identified in plan-review-2 is fixed. (`loki-data`/`grafana-data` were never affected; those images chown their own data dirs.)

## Correctness spot-checks (all pass)

- **Datasource overlay mount.** `provisioning/` contains exactly one file (`datasources/loki.yaml`); the more-specific bind-mount of `loki.datasource.docker.yaml` onto that path wins (Docker orders overlapping mounts by destination depth), so Grafana sees a single Loki datasource pointing at `http://loki:3100`. The Docker-specific file lives outside `provisioning/`, so it is not double-loaded. Native file untouched.
- **`loki.docker.yaml`** differs from native `loki.yaml` only in the four storage paths (`path_prefix`, `chunks_directory`, `rules_directory`, `wal.dir` → `/loki…`). No `${HOME}`, so `-config.expand-env=true` is correctly omitted; the `-querier.query-ingesters-within=0` runtime flag is retained. Data lands on the `loki-data` volume.
- **Proxy wiring** — `LOKI_URL=http://loki:3100`, `GRAFANA_URL=http://grafana:3000` (internal port, not the `3030` host mapping), `DB_PATH=/data/proxy.db` on `proxy-data`, `build: ../observe-write-proxy` (correct relative path from `backend/`). Matches the proxy's `internal/config` env names.
- **Security posture** — `GF_SECURITY_ADMIN_PASSWORD` is required via compose `${VAR:?err}` (correct layer — this *is* supported by Compose, unlike Grafana provisioning), `.env` is gitignored with `!.env.example` retained, and both the compose file and `.env.example` warn that `3030:3000` publishes on all interfaces and should sit behind a reverse proxy / loopback bind.
- **`restart: unless-stopped`** on all three services (server-appropriate).
- **Root `.gitignore`** adds `observe-write-proxy/`, correctly excluding the newly-sibling proxy repo from root tracking.

## Non-blocking notes (advisory — not defects in the code)

- **Commit the sibling repo.** The Task 7 fix is present but **uncommitted** in `observe-write-proxy` (`git status` there shows `M Dockerfile`). `docker compose build` uses the local working tree, so it builds correctly here — but a fresh server `git clone` of the proxy repo will only get the fix once it is committed and pushed. Ensure the proxy repo commit lands alongside this root change.
- **Stale "Blocked on a cross-repo precondition" phrasing.** The reconciled ROADMAP line still describes the proxy `/data` issue as a blocker; since Task 7 is now implemented, that framing is slightly out of date. Purely a wording nit in a planning artifact — no action required for correctness.

REVIEW_PASS
