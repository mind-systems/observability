# tradeoxy_broker — Integrate the observability logging SDK (Swift / Vapor)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. Today the broker writes its own log files and core writes its own, and debugging anything cross-cutting means merging timestamps by hand; restarts leave no marker, so it's unclear where to start reading after a fix. Instead, every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, with restart markers, browsable in Grafana and queryable programmatically.

Integration is **transport-only**: keep your curated log lines, do **not** rewrite call sites, only change where output goes and add a one-time init.

This note is the scope/checklist for **tradeoxy_broker**. It is intentionally light on SDK API specifics — the Swift SDK is not built yet and will be refined once it exists.

## Your SDK

**Swift SDK** (built by the observability project — Phase 2; broker is its only consumer). Prerequisite: that SDK milestone must be done first.

## Current logging in this project

- Custom `actor Logger` in **`Sources/App/Managers/Logger.swift`**, fully independent of swift-log.
- Public API: `log(svc: String = "broker", _ message: String)` — ~168 call sites.
- The sink is `Logger.append(svc:msg:)` (around lines 127–140): it JSON-encodes `{ ts, svc, msg }`, writes to a daily file `broker-YYYY-MM-DD.log` via `FileHandle`, and also prints to stdout. Daily rotation + shutdown handling via `LoggerShutdownHandler`.

**Single swap point: `Logger.append(svc:msg:)`** — the one method that produces output.

## What you need to do

1. **Add the SDK dependency** to `Package.swift`.
2. **Initialize once at startup** (in `Sources/App/configure.swift`): `init(project: "tradeoxy", service: "broker")`. Emits the `service.start` restart marker (directly fixes "where do logs begin after a restart") and sets resource attributes. Flush on shutdown using the existing `LoggerShutdownHandler`.
3. **Forward the sink to the SDK** inside `append(svc:msg:)` — hand the record to the SDK in addition to (or instead of) the file/stdout writes. The `log(svc:_:)` wrapper and all ~168 call sites stay **unchanged**. The existing `svc` argument maps to a structured field.
4. **Trace origination + propagation.** The broker receives the TradingView **webhook** — this is the "webhook → broker handled it" leg and the origin of the broker→core trace. Start/continue a trace in the webhook entry point and propagate the trace id into **gRPC metadata** on calls to core, so core's logs join the same `trace_id`. Use `@TaskLocal` ambient context so the ~168 call sites pick up `trace_id` without changes.
5. **Honor conventions:** map to SDK levels (the current logger has no levels — default sensibly); only `project`, `service`, `level` are low-cardinality labels.

## Project-specific gotchas

- `Logger` is a Swift **actor** — the SDK handoff happens inside its isolation; ensure the export path is non-blocking and never throws back into `append`.
- Restart marker should fire on app start in `configure.swift`; flush buffered records on shutdown via the existing `LoggerShutdownHandler` so nothing is lost.
- `StrategyDispatcher` is an actor and PLR/entry/stop workers use async/await — `@TaskLocal` is the right vehicle to carry `trace_id` across those async hops without touching call sites.

## Out of scope for now

Exact SDK API, the actor handoff details, batching and endpoint config — deferred until the Swift SDK is built.

## Definition of done

- `init(project: "tradeoxy", service: "broker")` at startup; `service.start` visible in Grafana on restart; buffered logs flushed on shutdown.
- Existing log lines appear in Loki tagged `project=tradeoxy`, `service=broker`, queryable via LogQL.
- A webhook handled by the broker and forwarded to core produces broker + core logs sharing one `trace_id`.
- No call sites rewritten (the `log(svc:_:)` API and ~168 sites untouched); file/stdout output preserved as desired; no Docker introduced.
