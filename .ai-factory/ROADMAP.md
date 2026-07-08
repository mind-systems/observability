# Project Roadmap

> A native-by-default observability stack (server/cloud deployment also runs via Docker) plus a thin multi-platform SDK that ships each project's custom logs over OTLP to a Grafana backend — correlated by `trace_id`.

## Milestones

> Everything above `---STOP---` is the observability project's own work. Everything below the line is integration work **owned by each consuming project** — those teams check off their own items. Each integration task links a detailed, self-contained note.

### Phase 1 — Foundation

- [x] **Backend bootstrap** — stand up Grafana + Loki natively via Homebrew (no Docker); one command from the repo root; verify Loki's OTLP log ingestion, local-FS storage, and low-cardinality label policy end to end against the frozen contract fixtures — see `.ai-factory/notes/backend-bootstrap.md`
- [x] **OTLP log contract & propagation conventions** — define the shared record shape and conventions: resource attributes (`project`, `service.name`, `service.instance.id`), level mapping, the `service.start` restart marker, Loki label policy, and trace-context propagation (`traceparent` over HTTP, trace id in gRPC metadata)

### Phase 2 — SDKs

- [x] **`observe-js` SDK** — one isomorphic package (Node + browser); platform-neutral core (OTLP/HTTP exporter, record model, batching, resource attributes) with two thin layers selected via conditional `exports`, uniform `init`/`log` API and carrier-agnostic inject/extract shared across both. The reference SDK; pins `observe-contract@v0.1.2` — **decomposed into atomic tasks in `observe-js/.ai-factory/ROADMAP.md`**:
  - [x] Node layer — covers mind_api, mind_mcp, tradeoxy_core: `AsyncLocalStorage` trace context, Winston transport adapter
  - [x] Browser layer — framework-agnostic for mind_web (React) and tradeoxy_gui (Angular): explicit (non-`zone.js`) trace context, trace origination on user action, `traceparent` injection on outgoing HTTP
- [x] **`observe-dart` SDK** — mind_mobile: pure-Dart core (OTLP/HTTP exporter via `package:http`, record model, bounded offline-tolerant batching, resource attributes) with Flutter only at the `logPrint` sink adapter edge; native `Zone` trace context, uniform `init`/`log` API and carrier-agnostic inject/extract. Pins `observe-contract@v0.1.2` — **decomposed into atomic tasks in `observe-dart/.ai-factory/ROADMAP.md`**
- [x] **`observe-swift` SDK** — tradeoxy broker: pure-Swift zero-dep `Observe` module (Foundation only); `URLSession` OTLP/HTTP exporter behind an `Exporter` protocol seam (host-injectable `AsyncHTTPClient` on Linux/Vapor), record model, actor-isolated bounded offline-tolerant batching, resource attributes; `@TaskLocal` trace context, uniform `init`/`log` API, carrier-agnostic inject/extract (HTTP `traceparent` in, gRPC metadata out); sink behind the custom `actor Logger`'s `append(svc:msg:)` — ~168 call sites untouched. Pins `observe-contract@v0.1.2` — **decomposed into atomic tasks in `observe-swift/.ai-factory/ROADMAP.md`**

### Phase 3 — Tooling

- [x] **Query helper (skill, not MCP)** — a Claude Code skill `observe-logs` driving a thin read-only LogQL/`curl` script over the Loki HTTP API for the common debug slices: since-last-restart (via the `event.name="service.start"` marker), by `trace_id` (structured metadata), by level/project/time window. Endpoint via env (`OBS_LOKI_URL`, default `http://localhost:3100`). Decided as a skill (sole consumer is Claude Code; zero running infra; reversible — the script can be MCP-wrapped later). **Lives in the global skills repo, not here — decomposed in `~/projects/skills/.ai-factory/ROADMAP.md` (spec `.ai-factory/notes/20-observe-logs-skill.md`)**, so it's usable from any consuming project against the shared local backend.

### Phase 4 — Server Deployment

- [x] **Server Docker Compose** — today `backend/` runs natively via Homebrew; Docker is an additive layer, not a replacement. `backend/docker-compose.yml` runs three services on internal `obs-net` + named volumes: **Loki internal-only** (no host port), **Grafana** `3030:3000` (UI + agent reads via datasource proxy), and **observe-write-proxy** `4318:4318` (Bearer-authenticated OTLP writes from SDKs) — SDKs write through the proxy, not Loki directly. Proxy env: `LOKI_URL=http://loki:3100`, `GRAFANA_URL=http://grafana:3000` (internal — not the `3030` host mapping), `DB_PATH` on a `proxy-data` volume; built from the sibling `observe-write-proxy` repo. Grafana provisioning YAML has no `${VAR:-default}` substitution and the native `loki.yaml` is not container-portable (`${HOME}`-based paths), so both get parallel Docker-specific config files (`backend/loki/loki.docker.yaml`, `backend/grafana/loki.datasource.docker.yaml`, bind-mounted as an overlay) instead of edits — native `backend/loki/loki.yaml`, `grafana.ini`, and `provisioning/datasources/loki.yaml` stay byte-for-byte untouched; Homebrew setup remains valid. Loki's image is distroless (no shell/wget) so its healthcheck uses the binary's native `-health` flag. Images pinned (`grafana/loki:3.7.2`, `grafana/grafana:13.0.2`), admin password required via `backend/.env`. **Blocked on a cross-repo precondition**: `observe-write-proxy`'s distroless image never creates `/data`, so a fresh volume mounts root-owned and the proxy crash-loops — needs a `Dockerfile` fix in that sibling repo before the stack is runnable. Spec: `.ai-factory/notes/08-server-docker-compose.md`. [28m 16s]

### Phase 5 — Local native run

- [x] **Proxy in `make backend-up`** — today `make backend-up` launches only Loki + Grafana as background processes (PID files in `/tmp`); the proxy has no native run wiring, so locally SDKs still hit Loki directly and the write-auth path is never exercised. Extend the root `Makefile`'s `backend-up`/`backend-down`/`backend-status` to also build and run the proxy as a **third** background process, so one command brings up the whole local stack and the write path goes through the proxy — matching the current no-Docker, no-launchd UX. Build via `make -C $(ROOT)/observe-write-proxy build` (→ `observe-write-proxy/bin/proxy`); start **after Loki** (it forwards there) with `PROXY_PID=/tmp/obs-proxy.pid`, `PROXY_LOG=/tmp/obs-proxy.log`, idempotent via the PID-file guard (same pattern as loki/grafana). Env: canon defaults already fit local (`:4318`, `LOKI_URL=http://localhost:3100`, `GRAFANA_URL=http://localhost:3000`) — override only `DB_PATH=$(HOME)/.local/share/observe/proxy.db` so the token store persists beside loki/grafana data. Update the `backend-up` summary echo (add the `:4318` write endpoint), `backend-status` (proxy `/healthz`), and `backend-clean` (also remove `proxy.db` — flag that this drops minted tokens). Update `docs/backend.md`. Native-only; does not touch `docker-compose.yml`. Spec: `.ai-factory/notes/09-proxy-native-run.md`. [16m 2s]


---STOP---

## Per-project integration (owned by each project)

> Ordered mind-first, then tradeoxy. Each task is gated on its SDK (Phase 2) being ready. Each links a detailed integration note written for a reader without this project's context. Notes will be refined once the SDKs exist.

### mind

- [x] **mind_mobile — integrate Dart/Flutter SDK** — see `.ai-factory/notes/01-integrate-mind-mobile.md`
- [x] **mind_api — integrate `observe-js` (Node)** — see `.ai-factory/notes/02-integrate-mind-api.md`
- [x] **mind_web — integrate `observe-js` (browser)** — see `.ai-factory/notes/03-integrate-mind-web.md`

### tradeoxy

- [ ] **tradeoxy_core — integrate `observe-js` (Node)** — see `.ai-factory/notes/05-integrate-tradeoxy-core.md`
- [ ] **tradeoxy_broker — integrate `observe-swift`** — see `.ai-factory/notes/06-integrate-tradeoxy-broker.md`
- [ ] **tradeoxy_gui — integrate `observe-js` (browser)** — see `.ai-factory/notes/07-integrate-tradeoxy-gui.md`
