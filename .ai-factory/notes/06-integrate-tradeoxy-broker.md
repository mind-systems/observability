# tradeoxy_broker — Integrate the observability logging SDK (observe-swift, Vapor)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. Today the broker writes its own log files and core writes its own; debugging anything cross-cutting means merging timestamps by hand, and restarts leave no marker. Instead, every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, with restart markers, browsable in Grafana and queryable via the `observe-logs` skill.

Integration is **transport-only**: keep your curated log lines, do **not** rewrite call sites, only change where output goes and add a one-time init.

## Your SDK

**`observe-swift`** — built and released, frozen at tag **`v0.1.0`** (single module `Observe`, zero deps; conforms to `observe-contract@v0.1.2`; broker is its only consumer). The SDK ships a broker-specific guide — **read `observe-swift`'s `docs/broker-integration.md`**; it documents the exact two edits and the shutdown drain.

Add it to `Package.swift`:

```swift
.package(url: "https://github.com/mind-systems/observe-swift.git", exact: "0.1.0")
// product: "Observe"
```

Public surface (`import Observe`): `Observe.start(InitOptions(...))`, `Observe.log(_ level:_ message:attrs:)`, `withSpan`/`startSpan`, `Observe.inject(into:)` / `Observe.extract(from:)` (carrier-agnostic), `Level`, `TraceContext`, `Carrier`/`DictionaryCarrier`.

## Current logging in this project

- Custom `actor Logger` in **`Sources/App/Managers/Logger.swift`**, fully independent of swift-log.
- Public API: `log(svc: String = "broker", _ message: String)` — ~168 call sites.
- The sink is `Logger.append(svc:msg:)` (≈ lines 127–140): JSON-encodes `{ ts, svc, msg }`, writes a daily file `broker-YYYY-MM-DD.log` via `FileHandle`, and also prints to stdout. Daily rotation + shutdown via `LoggerShutdownHandler`.

**Single swap point: `Logger.append(svc:msg:)`** — the one method that produces output.

## What you need to do

1. **Add the dependency** (above).
2. **Initialize once at startup** (`Sources/App/configure.swift`):
   `Observe.start(InitOptions(project: "tradeoxy", service: "broker", endpoint: <otlp url>))`. Emits the `service.start` restart marker and sets resource attributes. Idempotent (second call no-ops via `onError(.alreadyInitialized)`).
3. **One line in the sink** — inside `Logger.append(svc:msg:)`, additive alongside the existing file/stdout writes:
   `Observe.log(.info, msg, attrs: ["svc": svc])`. The `log(svc:_:)` wrapper and all ~168 call sites stay **unchanged**. Level-less source → `.info` (the correct cross-platform mapping); `svc` becomes a structured attribute, **not** a label.
4. **Drain on shutdown** — flush buffered records before the process exits, wired into the existing `LoggerShutdownHandler` (exact call in `docs/broker-integration.md`).
5. **Mid-chain trace propagation** *(the broker is the middle of the chain: web → broker → core).* On the inbound **TradingView webhook** (Vapor route): build a `Carrier` over the request headers, `Observe.extract(from:)` the `traceparent`, and run the handler inside the SDK's ambient context (`withSpan` / `runWithContext`). On the outbound **gRPC call to core**: `Observe.inject(into: &metadataCarrier)`. Carrier-agnostic — no `grpc-swift` dependency in the SDK. This is what makes the webhook → broker → core chain share one `trace_id`.

## Ambient context — `@TaskLocal` (watch `Task.detached`)

`trace_id` flows via `@TaskLocal` — real propagation across `await` in the structured task tree, so the ~168 call sites and the async PLR/entry/stop workers pick it up without changes. **Trap:** `@TaskLocal` is inherited by child tasks but **NOT by `Task.detached`** (clean slate → no `trace_id`). If `StrategyDispatcher` or any worker spawns via `Task.detached`, either use a structured child task or re-bind the context inside it.

## Project-specific gotchas

- `Logger` is a Swift **actor** — the SDK hand-off happens inside its isolation; the export path is non-blocking and never throws back into `append` (a guarantee of the SDK, not something you implement). `Observe.log` returns promptly.
- Restart marker fires on app start in `configure.swift`; buffered records are flushed on shutdown via `LoggerShutdownHandler` so nothing is lost.
- stdout is **not** reserved here (unlike mind_mcp) — the broker's existing stdout/file output can stay.

## Endpoint (env-configurable; Linux/Vapor watch-point)

`endpoint` (in `InitOptions`) is **required**. On macOS dev the backend is reachable at `http://localhost:3100/otlp/v1/logs`; in other environments substitute the network address. **Linux/Vapor:** if the default `URLSession` async path is unavailable on the broker's toolchain, inject an `AsyncHTTPClient`-backed exporter via `InitOptions.exporter` — never a core dependency (see `docs/broker-integration.md`). Supply the endpoint via the broker's existing config; the planner decides where. Don't hard-code.

## Log destination switch (`LOG_DESTINATION`)

Workspace convention (root `docs/log-destinations.md`): `LOG_DESTINATION` ∈ `file | grafana | both`, applied at the sink:
- `file` → existing daily-file + stdout output only (the `Observe.log` line skipped);
- `grafana` → `Observe.log` (OTLP) only;
- `both` → both.

Same variable name and values as every other project.

## Definition of done

- `Observe.start(InitOptions(project: "tradeoxy", service: "broker", endpoint))` at startup; `service.start` visible on restart (verify: `observe-logs since-restart broker --project tradeoxy`); buffered logs flushed on shutdown.
- Existing log lines appear in Loki tagged `project=tradeoxy`, `service_name=broker`, queryable via LogQL / `observe-logs window … --project tradeoxy --service broker`.
- A webhook handled by the broker and forwarded to core produces broker + core logs sharing one `trace_id` (verify: `observe-logs trace <id>` shows both legs).
- `LOG_DESTINATION` honored.
- No call sites rewritten (the `log(svc:_:)` API and ~168 sites untouched); file/stdout output preserved as desired; no Docker introduced.
