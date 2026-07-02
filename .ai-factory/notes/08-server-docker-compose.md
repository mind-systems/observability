# Server Docker Compose

**Date:** 2026-06-27 (reconciled 2026-07-02 after plan-review found the original mechanism broken)
**Source:** conversation context; plan `.ai-factory/plans/01-server-docker-compose.md`

## Key Findings

- Existing `backend/` configs (`loki.yaml`, `grafana.ini`, `provisioning/`) are for native Homebrew and must stay byte-for-byte untouched — Docker is a purely additive layer, not a replacement.
- Grafana provisioning YAML has **no `${VAR:-default}` env-var substitution** — the originally planned `url: ${LOKI_INTERNAL_URL:-http://localhost:3100}` in `provisioning/datasources/loki.yaml` does not work. Fix: a separate Docker-specific datasource file (`backend/grafana/loki.datasource.docker.yaml`, hardcoded `url: http://loki:3100`), bind-mounted as an overlay onto the container's `.../datasources/loki.yaml` path — more specific than the whole-`provisioning/` mount, so it wins without editing the native file.
- The native `loki.yaml` is **not container-portable**: it depends on `${HOME}` expansion (`-config.expand-env=true`, passed only by the Makefile) and stores data under the host `$HOME`, not a container path. Fix: a separate Docker-specific config (`backend/loki/loki.docker.yaml`) with storage paths pointed at `/loki` (the mounted volume) and no env expansion needed.
- **Loki's Docker image has no shell, wget, or curl** (`grafana/loki` is built `FROM gcr.io/distroless/static:nonroot`, confirmed via the image's Dockerfile) — an HTTP-based Docker healthcheck is impossible. Loki 3.6+ ships a native `-health` flag for exactly this (self-checks `/ready`, exits 0/1, no external tool needed); the compose healthcheck uses `["CMD", "/usr/bin/loki", "-health"]`. Grafana's default published tag is Alpine-based (includes busybox `wget`), so its healthcheck can stay `wget`-based.
- Host ports: **observe-write-proxy 4318** (Bearer-authenticated OTLP writes from SDKs), Grafana `3030:3000` (UI + agent reads via datasource proxy) — published on all interfaces, flagged for reverse-proxy/TLS or loopback-binding at deploy time. **Loki is internal-only** (no host port): SDK writes go through the proxy, reads go through the Grafana datasource proxy. `3030` is the host mapping only — inside `obs-net` the proxy reaches Grafana at `grafana:3000`.
- **`observe-write-proxy`'s image has a blocking precondition**: its final stage is `gcr.io/distroless/static:nonroot` (uid 65532) and never creates `/data`, so a fresh `proxy-data` named volume mounts root-owned and the proxy crash-loops on `EACCES` opening `/data/proxy.db`. This is fixed in the `observe-write-proxy` repo itself (separate git repo), not here — see Task 7 in the plan.
- Grafana admin credentials: `GF_SECURITY_ADMIN_PASSWORD` (and `_USER`) are supplied via a required `backend/.env` (`.env.example` template, gitignored), overriding the `admin/admin` baked into the read-only `grafana.ini`.
- Image tags are pinned to the Homebrew-tested versions — `grafana/loki:3.7.2`, `grafana/grafana:13.0.2` — confirmed to exist on Docker Hub. Never `:latest`. The Loki tag must stay on the 3.x line: the config is 3.x-shaped (`tsdb`/schema v13/`parallelise_shardable_queries`/`disk_full_threshold`); a 2.x tag would reject it.

## Details

### Files created

- `backend/loki/loki.docker.yaml` — copy of `loki.yaml` with the four storage paths repointed at `/loki` (mounted volume), no `${HOME}`, no `-config.expand-env`. Everything else identical.
- `backend/grafana/loki.datasource.docker.yaml` — copy of `provisioning/datasources/loki.yaml` with only `url: http://loki:3100` changed. Lives **outside** `provisioning/` so Grafana's scanner never auto-loads it as a second datasource; wired in only via the compose overlay mount.
- `backend/docker-compose.yml` — three services (`loki`, `grafana`, `observe-write-proxy`) on internal network `obs-net`, named volumes `loki-data`/`grafana-data`/`proxy-data`, every service `restart: unless-stopped`.
- `backend/.env.example` — documents `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD`; `backend/.gitignore` — ignores the real `backend/.env`.

### Files NOT touched (native Homebrew path stays valid)

- `backend/loki/loki.yaml`, `backend/grafana/grafana.ini`, `backend/grafana/provisioning/datasources/loki.yaml`, root `Makefile` — all byte-for-byte unchanged. The Docker path is 100% parallel `*.docker.yaml` files plus the compose file; `make backend-up` is unaffected.

### Scope: write only, do NOT run

Do not run `docker compose up`, do not start any container, do not test the stack. The dev machine is under the project's hard "No Docker" constraint. The compose file targets the **server** and is verified by whoever deploys it there.

Deploy-time smoke check for the server operator (NOT part of this task):

```bash
cd backend/
cp .env.example .env   # fill in GRAFANA_ADMIN_PASSWORD
docker compose up -d
curl http://localhost:4318/healthz       # observe-write-proxy → 200
curl http://localhost:3030/api/health    # Grafana → {"database": "ok", ...}
# Loki is internal-only (no host port): verify from inside the network —
# docker compose exec loki /usr/bin/loki -health
# then Grafana → Data Sources → Loki → Test → "Data source connected"
```

## Cross-repo precondition (blocking)

`observe-write-proxy/Dockerfile`'s final stage (`gcr.io/distroless/static:nonroot`) never creates `/data`; a fresh `proxy-data` volume mounts root-owned and the proxy crash-loops with `EACCES`. Fix (separate repo, own git history): create `/data` owned by uid/gid 65532 in the builder stage and copy it with ownership into the final stage, e.g.:

```dockerfile
# in the golang build stage
RUN mkdir -p /data && chown 65532:65532 /data
```
```dockerfile
# in the final distroless stage
COPY --from=build --chown=65532:65532 /data /data
```

Until this lands, `docker compose up` cannot bring up the only OTLP write path — treat it as a hard dependency of this milestone, not an optional follow-up.

## Open Questions

None outstanding. Resolved during plan-review:

- ~~Parameterize `provisioning/datasources/loki.yaml` via `${LOKI_INTERNAL_URL:-http://localhost:3100}`~~ — **does not work**; Grafana provisioning YAML has no env-var substitution syntax. Superseded by the separate `loki.datasource.docker.yaml` overlay file.
- ~~Native `loki.yaml`/`grafana.ini` already match the container ports, no other change needed~~ — true for the *ports*, but the native `loki.yaml`'s storage paths (`${HOME}`-based) are not container-portable regardless. Superseded by the separate `loki.docker.yaml` file.
- `auth_enabled: false` is already set in `backend/loki/loki.yaml:16` and carried into `loki.docker.yaml`; no change needed there.
- Loki Docker healthcheck: resolved via the binary's native `-health` flag (see Key Findings) instead of `wget`, which the distroless image doesn't have.
