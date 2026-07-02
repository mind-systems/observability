# Plan: Server Docker Compose

## Context
Add a Docker Compose stack for **server** deployment (Loki + Grafana + observe-write-proxy) as a genuinely **additive** layer over the existing native Homebrew `backend/` config. The native macOS path must keep working unchanged.

Plan-review-1 found that the spec note's original mechanism does not work: Grafana has no `${VAR:-default}` syntax, and the native `loki.yaml` is not container-portable (it depends on `${HOME}` + `-config.expand-env=true` and stores data under `$HOME`, not `/loki`). Both must not be worked around by editing the shared native files — instead Docker gets its own config files so the native files stay byte-for-byte untouched. This plan supersedes the "edit `datasources/loki.yaml`" and "native files already match" premises in the spec note; Task 5 reconciles the note and ROADMAP.

## Settings
- Testing: no
- Logging: minimal
- Docs: no (planning artifacts — spec note / ROADMAP — are reconciled in Task 5; ARCHITECTURE carve-out is a recommendation, not in scope)

## Design decisions

- **Native files are not touched.** No edit to `backend/loki/loki.yaml`, `backend/grafana/grafana.ini`, or `backend/grafana/provisioning/datasources/loki.yaml`. Docker gets parallel, Docker-specific config files. This makes the compose layer purely additive and keeps the Homebrew path valid by construction (review Critical #1 & #2, "native premise incorrect").
- **Loki:** a Docker-specific config with `/loki` storage paths (no `${HOME}`, so no `-config.expand-env=true` needed), so data lands on the mounted `loki-data` volume. The compose `command` also carries the two runtime flags the native launch passes (`-querier.query-ingesters-within=0`; expand-env is dropped only because the Docker config has no env vars) — review Critical #2 & #3.
- **Grafana datasource:** a Docker-specific datasource file with `url: http://loki:3100`, bind-mounted **onto** the container's `.../datasources/loki.yaml` path (a more-specific overlay over the whole-provisioning mount). Grafana therefore sees exactly one Loki datasource pointing at the internal Loki; the on-disk native file is unchanged. No env-var interpolation, so the broken `${VAR:-default}` form is eliminated entirely — review Critical #1.
- **Admin credentials:** `GF_SECURITY_ADMIN_PASSWORD` (and `GF_SECURITY_ADMIN_USER`) supplied via a required `.env` variable, overriding the `admin/admin` baked into the read-only `grafana.ini` — review Security #4.
- **Pinned images:** pin explicit `grafana/loki` (3.x line — the config is 3.x-shaped; a 2.x tag would reject it) and `grafana/grafana` tags matching the Homebrew-tested versions; no `:latest` (review Other findings).
- **Proxy env/port wiring is verbatim and confirmed** — `LOKI_URL`/`GRAFANA_URL`/`DB_PATH`, `4318`, `build: ../observe-write-proxy` are all correct. **But the `proxy-data` volume has a blocking precondition** (review-2 Critical #1): the distroless `nonroot` image (uid 65532) never creates `/data`, so a fresh named volume mounts **root-owned** and the proxy crash-loops trying to create `/data/proxy.db` (`EACCES`). This requires a cross-repo fix in `observe-write-proxy` (Task 7) before the stack can start; the compose file alone cannot fix volume ownership. `loki-data`/`grafana-data` are unaffected — those images chown their data dirs to their runtime users.
- **Server-deployment hardening:** every service declares a `restart:` policy so a crash or host reboot brings the stack back up (review-2 Other findings).

## Tasks

### Phase 1: Docker config files

- [x] **Task 1: Docker-specific Loki config**
  Files (new): `backend/loki/loki.docker.yaml`
  Copy `backend/loki/loki.yaml` verbatim, changing only the four storage paths to the mounted volume, with no `${HOME}` and no env expansion:
  - `common.path_prefix: /loki`
  - `common.storage.filesystem.chunks_directory: /loki/chunks`
  - `common.storage.filesystem.rules_directory: /loki/rules`
  - `ingester.wal.dir: /loki/wal`
  Keep everything else identical (`auth_enabled: false`, `http_listen_port: 3100`, schema v13/tsdb, `otlp_config` label policy, `disk_full_threshold: 0`, etc.). Update the top comment to note this is the container variant (data on the `/loki` volume, no `-config.expand-env` required).

- [x] **Task 2: Docker-specific Grafana Loki datasource**
  Files (new): `backend/grafana/loki.datasource.docker.yaml`
  Copy `backend/grafana/provisioning/datasources/loki.yaml` verbatim, changing only `url:` to `http://loki:3100`. Keep name `Loki`, `isDefault: true`, `access: proxy`, `maxLines: 1000`, etc. **Place it outside the `provisioning/` tree** so it is not auto-loaded as a second datasource — it is exposed only via the explicit overlay bind-mount in Task 3.

### Phase 2: Compose file (depends on Tasks 1 & 2)

- [x] **Task 3: Create the Docker Compose file**
  Files (new): `backend/docker-compose.yml`
  Three services on internal network `obs-net` with named volumes. Every service declares `restart: unless-stopped`.
  - **`loki`** — pinned `grafana/loki:<version>` (Task 6), **internal-only (no host port)**. Mounts `./loki/loki.docker.yaml:/etc/loki/local-config.yaml:ro` and `loki-data:/loki`. Command: `-config.file=/etc/loki/local-config.yaml -querier.query-ingesters-within=0`. Healthcheck: `wget -qO- localhost:3100/ready` (with a startup grace period). On `obs-net`.
  - **`grafana`** — pinned `grafana/grafana:<version>` (Task 6), port `3030:3000`. Mounts: `./grafana/grafana.ini:/etc/grafana/grafana.ini:ro`, `./grafana/provisioning:/etc/grafana/provisioning:ro`, the overlay `./grafana/loki.datasource.docker.yaml:/etc/grafana/provisioning/datasources/loki.yaml:ro`, and `grafana-data:/var/lib/grafana`. Env: `GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}`, `GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:?set GRAFANA_ADMIN_PASSWORD in backend/.env}`. Healthcheck: `wget -qO- localhost:3000/api/health`. `depends_on: { loki: { condition: service_healthy } }`. On `obs-net`.
  - **`observe-write-proxy`** — `build: ../observe-write-proxy` (sibling repo has a `Dockerfile`), port `4318:4318` (Bearer-authenticated OTLP writes). Env: `LOKI_URL=http://loki:3100`, `GRAFANA_URL=http://grafana:3000` (internal port — **not** the `3030` host mapping), `DB_PATH=/data/proxy.db`. Mounts `proxy-data:/data` (requires the Task 7 image fix to be writable). `depends_on: { loki: { condition: service_healthy }, grafana: { condition: service_healthy } }`. On `obs-net`.
  - Top-level `volumes:` — `loki-data`, `grafana-data`, `proxy-data`.
  - Top-level `networks:` — `obs-net`.
  - Both healthchecks use `wget`, which ships in the Alpine/BusyBox-based `grafana/loki` and `grafana/grafana` images; confirm it is present at the tags chosen in Task 6 (if absent, `grafana` and `proxy` would never start since they gate on `service_healthy`).

- [x] **Task 4: `.env` template and gitignore**
  Files (new): `backend/.env.example`; edit: `backend/.gitignore` (create if absent)
  `.env.example` documents `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD` (compose reads `backend/.env` automatically). Gitignore the real `backend/.env`. Add a comment in the compose file / `.env.example` warning that `3030` publishes Grafana on all interfaces — a server deployment should front it with a reverse proxy / TLS or bind to loopback (review Security #4, deploy-time guidance).

### Phase 3: Version pinning & artifact reconciliation

- [x] **Task 5: Reconcile the spec note and ROADMAP with the corrected mechanism**
  Files: `.ai-factory/notes/08-server-docker-compose.md`, `.ai-factory/ROADMAP.md`
  The note and the roadmap line (line ~28) both carry the broken `${LOKI_INTERNAL_URL:-http://localhost:3100}` mechanism and the "native files already match / edit `datasources/loki.yaml`" premise. Update both to the design here: Docker-specific `loki.docker.yaml` + `loki.datasource.docker.yaml`, native files untouched, admin password via env, pinned images, `-querier.query-ingesters-within=0` retained. Remove the resolved "Open Questions" section's stale claims where they now conflict.
  Recommendation (out of scope, note only): add a short "Server deployment (Docker) — additive, separate from the native macOS path" carve-out to `.ai-factory/ARCHITECTURE.md` so the Docker layer is a sanctioned exception to the "❌ Any component → Docker" rule rather than a silent contradiction (review Architecture WARN).

- [x] **Task 6: Pin image versions**
  Files: `backend/docker-compose.yml`
  Replace the `<version>` placeholders with explicit tags matching the Homebrew-tested versions. Determine them from the installed binaries (`loki --version`, `grafana server --version`) or the current stable release lines. **The Loki tag must be a 3.x line** — the config is 3.x-shaped (`tsdb`/schema v13/`parallelise_shardable_queries`/`disk_full_threshold`) and a 2.x pin would reject it. Never use `:latest`.

### Phase 4: Cross-repo precondition (blocking)

- [x] **Task 7: Make the proxy image ship a writable `/data` (in the `observe-write-proxy` repo)**
  Files: `observe-write-proxy/Dockerfile` (**separate git repo** — commit there, not in root)
  The final stage is `gcr.io/distroless/static:nonroot` (uid 65532) and copies only `/proxy`; it never creates `/data`. A fresh `proxy-data` named volume therefore mounts root-owned, and `store.Open` (`os.MkdirAll("/data",…)` is a no-op on the existing mountpoint, then SQLite open at `/data/proxy.db`) fails with `EACCES` under uid 65532 — the proxy `os.Exit(1)`s and crash-loops. Distroless has no shell, so `RUN mkdir` in the final stage is impossible. Fix: create the dir in the builder stage and copy it with ownership, e.g. `RUN mkdir -p /data && chown 65532:65532 /data` in the `golang` build stage, then `COPY --from=build --chown=65532:65532 /data /data` in the final stage. This is a **hard precondition**: until the image ships a `/data` owned by uid 65532, `docker compose up` cannot bring up the only OTLP write path. Since it lives in a separate repo, treat it as a dependency of this milestone — the root compose files are not "ready to run" without it.

## Constraints

- **Write only — do NOT run.** Do not run `docker compose up`, start any container, or test the stack. The dev machine is under the hard "No Docker" constraint; the compose file targets the server and is verified by whoever deploys it. Deliverable is the correct, ready-to-run files.
- **Cross-repo dependency.** Task 7 lands in the separate `observe-write-proxy` repo; run `git` there, not from root. The root compose file is only "ready to run" once that image fix is in — flag this in the milestone completion note if Task 7 cannot be completed in the same pass.
- **Native Homebrew files stay byte-for-byte untouched** — `backend/loki/loki.yaml`, `backend/grafana/grafana.ini`, `backend/grafana/provisioning/datasources/loki.yaml`, and the root `Makefile` are not edited. The Docker path uses parallel `*.docker.yaml` files, so the native `make backend-up` flow is unaffected.
