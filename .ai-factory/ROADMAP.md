# Project Roadmap

> A local, no-Docker observability stack plus a thin multi-platform SDK that ships each project's custom logs over OTLP to a native Grafana backend — correlated by `trace_id`.

## Milestones

> Everything above `---STOP---` is the observability project's own work. Everything below the line is integration work **owned by each consuming project** — those teams check off their own items. Each integration task links a detailed, self-contained note.

### Phase 1 — Foundation

- [x] **Backend bootstrap** — stand up Grafana + Loki natively via Homebrew (no Docker); one command from the repo root; verify Loki's OTLP log ingestion, local-FS storage, and low-cardinality label policy end to end against the frozen contract fixtures — see `.ai-factory/notes/backend-bootstrap.md`
- [x] **OTLP log contract & propagation conventions** — define the shared record shape and conventions: resource attributes (`project`, `service.name`, `service.instance.id`), level mapping, the `service.start` restart marker, Loki label policy, and trace-context propagation (`traceparent` over HTTP, trace id in gRPC metadata)

### Phase 2 — SDKs

- [ ] **`observe-js` SDK** — one isomorphic package (Node + browser); platform-neutral core (OTLP/HTTP exporter, record model, batching, resource attributes) with two thin layers selected via conditional `exports`, uniform `init`/`log` API and inject/extract helpers shared across both:
  - [ ] Node layer — covers mind_api, mind_mcp, tradeoxy_core: `AsyncLocalStorage` trace context, Winston transport adapter
  - [ ] Browser layer — framework-agnostic for mind_web (React) and tradeoxy_gui (Angular): `Zone` trace context, trace origination on user action, `traceparent` injection on outgoing HTTP
- [ ] **`observe-swift` SDK** — broker: `Telemetry` sink behind the custom `actor Logger`, OTLP/HTTP exporter, `@TaskLocal` trace context, gRPC metadata inject/extract — no call sites changed
- [ ] **`observe-dart` SDK** — mind_mobile: OTLP/HTTP exporter (batched, offline-tolerant), `Zone` context, `logPrint` sink adapter, propagation on outgoing HTTP/gRPC

### Phase 3 — Tooling

- [ ] **Query/MCP wrapper** — thin tool over the Loki HTTP API for common debug slices: since-last-restart, by `trace_id`, by level/project/time window

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
