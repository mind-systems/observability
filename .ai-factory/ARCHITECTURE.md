# Architecture: Contract-Driven Integration (OTLP Boundary)

## Overview

This project is not a single application — it is a set of thin SDKs plus run configuration for an off-the-shelf backend. The architecture is therefore organized around **one contract**: OpenTelemetry OTLP. Host applications depend only on that contract; the storage/query/UI engine behind it (the Grafana family, run natively) stays swappable.

There is no custom storage engine, no business domain, and no layered application stack to design. The work that matters is keeping the OTLP boundary clean so that (a) host apps change only at a single logging sink, and (b) the backend can grow — logs → traces → profiles → cloud — without re-platforming.

## Decision Rationale

- **Project type:** observability tooling — multi-platform SDK + off-the-shelf backend run config
- **Tech stack:** Swift / Node-TypeScript / web JS / Dart-Flutter SDKs; OTLP over HTTP; Grafana family backend (Loki now)
- **Hard constraints:** no Docker; native macOS only
- **Key factor:** OTLP at the SDK boundary is the real future-proofing — it decouples host apps from the backend, so the backend choice is reversible and the roadmap (traces, profiling, cloud) is additive

## Folder Structure

```
observability/
├── sdks/
│   ├── swift/      # Swift SDK — Telemetry sink, OTLP/HTTP exporter, @TaskLocal trace context
│   ├── node/       # Node/TS SDK — exporter, AsyncLocalStorage context, Winston transport adapter
│   ├── web/        # web JS SDK — framework-agnostic (React, Angular), Zone-based context
│   └── dart/       # Dart/Flutter SDK — exporter, Zone context, logPrint sink adapter
├── backend/        # off-the-shelf engine — native run config only, NO Docker
│   ├── loki/       # Loki config: OTLP log ingestion, low-cardinality labels, local-FS storage
│   └── grafana/    # Grafana provisioning: Loki datasource, dashboards
├── tools/          # thin query/MCP wrapper for common debug slices (LogQL over Loki HTTP API)
├── docs/
└── .ai-factory/
```

Only `sdks/` and `tools/` contain code we own. `backend/` holds configuration for binaries installed via Homebrew — no engine code lives here. Directories for `tempo/`, `pyroscope/`, `mimir/` are added under `backend/` when those signals are introduced.

## Dependency Rules

- ✅ Host app → SDK, **only at the single logging sink** (the custom `append`, the Winston transport, `logPrint`, the web wrapper).
- ✅ SDK → the OTLP contract (resource attributes + OTLP log records). The OTLP endpoint URL is the SDK's only knowledge of the outside world, supplied by config.
- ✅ Grafana → Loki (datasource). Claude → Loki HTTP API (LogQL).
- ❌ SDK → Loki/Grafana specifics. The SDK must never encode anything backend-specific beyond "POST OTLP to this URL".
- ❌ Application call sites → the SDK API or `trace_id`. Call sites stay untouched; correlation is ambient.
- ❌ High-cardinality fields (`trace_id`, ids, free text) → Loki **labels**. They belong in the log body / structured metadata.
- ❌ Any component → Docker.

## Component Communication

- **SDK → backend:** OTLP/HTTP. For logs-only, SDKs post to Loki's native OTLP log endpoint directly — no collector required.
- **Front door (deferred):** once more than one signal exists, introduce a single OTLP front door (Grafana Alloy / OTel Collector) that fans out logs → Loki, traces → Tempo, profiles → Pyroscope. SDKs keep pointing at one endpoint; only its target changes.
- **Cross-service context:** trace context propagates web → broker (`traceparent` HTTP header) → core (gRPC metadata). The SDK injects/extracts it; call sites are unaware.
- **Read paths:** the developer browses and selects log lines in Grafana; Claude pulls slices programmatically via the Loki HTTP API.

## Key Principles

1. **OTLP is the only contract.** Everything else behind it is replaceable.
2. **The SDK never breaks the host.** A failed export or unreachable backend degrades silently (drop/buffer) — it never throws into the caller's `log()` path.
3. **Correlation is ambient.** `trace_id` flows via `@TaskLocal` / `AsyncLocalStorage` / `Zone`, never through call-site arguments.
4. **Uniform public API across platforms.** Same vocabulary (`init`, `log`, `startSpan`, `withSpan`) everywhere, even where language idioms differ.
5. **Resource attributes identify origin.** `project`, `service.name`, `service.instance.id` on every record; `service.start` marks restarts.
6. **Low-cardinality Loki labels.** Labels = `project`, `service`, `level`. Nothing else.
7. **Native, no Docker.** Backend runs as Homebrew processes.
8. **Build logs now; the rest is additive.** Traces, profiles, metrics, and cloud are configuration/deployment additions, not rewrites.

## Code Examples

### Swap point — Swift broker (illustrative)

The custom `actor Logger` keeps its ~168 call sites; only its sink changes:

```swift
// Sources/App/Managers/Logger.swift — append(svc:msg:)
private func append(svc: String, msg: String) {
    // before: write JSON line to file + stdout
    // after: hand the record to the SDK; trace_id is read from ambient context inside the SDK
    Telemetry.log(level: .info, message: msg, attrs: ["svc": svc])
}
```

### Swap point — NestJS core (illustrative)

A custom Winston transport replaces the file transport; call sites (`this.logger.log(...)`) are unchanged:

```typescript
// src/common/logger/winston.config.ts
transports: [
  new ConsoleTransport(),
  new OtlpTransport({ endpoint: process.env.OTLP_ENDPOINT }), // ships over OTLP; trace_id from AsyncLocalStorage
]
```

### Dependency rule — SDK stays backend-agnostic

```text
log("order filled")  ──►  SDK  ──►  OTLP/HTTP  ──►  Loki (today) | Grafana Cloud (later)
                            ▲
                  knows ONLY the OTLP endpoint URL — never "Loki", never "Grafana"
```

## Anti-Patterns

- ❌ Importing the SDK at application call sites or threading `trace_id` through function arguments.
- ❌ Encoding backend-specific logic (Loki/Grafana APIs, schemas) inside an SDK.
- ❌ Putting `trace_id` or other high-cardinality values into Loki labels (this destroys Loki's index efficiency).
- ❌ Letting an export failure raise into the host application's logging call.
- ❌ Introducing Docker for any component "just to get started".
- ❌ Hard-coding the backend so that adding Tempo/Pyroscope or moving to cloud requires touching SDK or call-site code.
