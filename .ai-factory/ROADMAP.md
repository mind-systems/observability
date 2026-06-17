# Project Roadmap

> A local, no-Docker observability stack plus a thin multi-platform SDK that ships each project's custom logs over OTLP to a native Grafana backend — correlated by `trace_id`.

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

---STOP---

## Per-project integration (owned by each project)

> Ordered mind-first, then tradeoxy. Each task is gated on its SDK (Phase 2) being ready. Each links a detailed integration note written for a reader without this project's context. Notes will be refined once the SDKs exist.

### mind

- [ ] **mind_mobile — integrate Dart/Flutter SDK** — see `.ai-factory/notes/01-integrate-mind-mobile.md`
- [ ] **mind_api — integrate Node/TS SDK** — see `.ai-factory/notes/02-integrate-mind-api.md`
- [ ] **mind_web — integrate Web JS SDK** — see `.ai-factory/notes/03-integrate-mind-web.md`
- [ ] **mind_mcp — integrate Node/TS SDK** — see `.ai-factory/notes/04-integrate-mind-mcp.md`

### tradeoxy

- [ ] **tradeoxy_core — integrate Node/TS SDK** — see `.ai-factory/notes/05-integrate-tradeoxy-core.md`
- [ ] **tradeoxy_broker — integrate Swift SDK** — see `.ai-factory/notes/06-integrate-tradeoxy-broker.md`
- [ ] **tradeoxy_gui — integrate Web JS SDK** — see `.ai-factory/notes/07-integrate-tradeoxy-gui.md`
