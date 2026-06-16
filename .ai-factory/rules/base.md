# Project Base Rules

> Greenfield project — no application code yet. These are the agreed conventions for the multi-platform SDK monorepo, to be refined as code lands.

## Naming Conventions

- **Per-platform idioms win.** Each SDK follows its language's native style: Swift → `camelCase` members / `UpperCamelCase` types; TypeScript → `camelCase` / `PascalCase`; Dart → `lowerCamelCase` / `UpperCamelCase`, `snake_case` filenames.
- **Uniform public API surface across platforms.** The same concepts use the same names everywhere: `init`, `log`, `startSpan`, `withSpan`. Do not let platform idioms drift the public vocabulary.
- **Telemetry attribute keys follow OpenTelemetry semantic conventions** (`service.name`, `service.instance.id`); custom keys use the project prefix `project`.

## Module Structure

- Monorepo with one top-level directory per SDK platform plus the native Grafana + Loki run configuration and any query/MCP wrapper.
- Keep the OTLP exporter, the public API, and the ambient-context plumbing as separate units within each SDK.
- Backend (Grafana family) is off-the-shelf and runs natively (no Docker) — no engine code lives here, only run config (Loki config, Grafana provisioning).

## Error Handling

- The SDK must **never break the host app**: a failed export or unreachable collector degrades silently (drop/buffer), never throws into the caller's `log()` path.
- Surface SDK-internal failures only through the SDK's own diagnostic channel, not the host logger.

## Logging

- Structured records over OTLP carry: `project`, `service.name`, `service.instance.id`, level, message, `trace_id`.
- `trace_id` is injected via ambient context (`@TaskLocal` / `AsyncLocalStorage` / `Zone`) — never threaded through call sites.
- Host projects keep their custom loggers; only the sink is swapped.

## Language

All files — code, docs, config — are written in English.
