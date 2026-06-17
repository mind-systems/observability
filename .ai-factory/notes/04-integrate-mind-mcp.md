# mind_mcp — Integrate the observability logging SDK (observe-js, Node, MCP server)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. Every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated by a shared `trace_id`, with restart markers, browsable in Grafana and queryable via the `observe-logs` skill.

Integration here is **optional / low-volume** — the value is the restart marker plus error/diagnostic capture for the MCP server, not a large body of curated lines.

## Your SDK

**`observe-js`** — built and released, frozen at tag **`v0.1.0`** (isomorphic Node + browser; conforms to `observe-contract@v0.1.2`; shared with mind_api and tradeoxy_core). Add it as an npm git dependency pinned to that tag (the dual ESM+CJS build resolves whichever module system mind_mcp uses):

```jsonc
// package.json
"dependencies": {
  "observe-js": "git+https://github.com/mind-systems/observe-js.git#v0.1.0"
}
```

Node surface (`import … from "observe-js"`): `init`, `log`, `flush`, `shutdown` (+ `startSpan`/`withSpan`, `inject`/`extract`, `Level` — not central here). Confirm exact signatures against `v0.1.0`.

## Current logging in this project

- Minimal: a single `console.error("mind-mcp server started")` in `src/index.ts`. Node/TS, Model Context Protocol SDK.

**Single swap point: `src/index.ts`** (and any future logging — wrap it in the SDK from the start).

## What you need to do

1. **Add the dependency** (above).
2. **Initialize once at startup** (`src/index.ts`, after the server connects): `init({ project: "mind", service: "mind_mcp", endpoint: <otlp url> })`. Emits the `service.start` marker and sets resource attributes; idempotent.
3. **Route logging through the SDK.** Replace the bare `console.error` startup line (and any future logs) with `log(level, msg, attrs?)`, keeping a local echo on **stderr** only (see the critical gotcha). Pick the level by *intent*, not by the fact the old line used `console.error` — the startup line is `info`, real failures are `error` (`console.error` was only used to stay off stdout).
4. **Honor conventions:** only `project`, `service`, `level` are low-cardinality labels.

Trace propagation is **not central** here: an MCP server speaks JSON-RPC over stdio, not the HTTP/gRPC cross-service chain, so there's no inbound `traceparent` to bind. Logs simply carry `service=mind_mcp` with no `trace_id`, which is fine.

## Project-specific gotchas — CRITICAL

- **stdout is reserved for the MCP protocol.** Logs must **never** be written to stdout — it corrupts the MCP stdio transport and breaks the server. Two concrete points now that the SDK is real:
  - The SDK ships logs over **OTLP/HTTP (off-channel)** — it does **not** write to stdout. Good; that's exactly why this is safe.
  - But wire the SDK's diagnostics hook **`onError` to stderr (or a no-op), never `console.log`** — an accidental `console.log` in your own `onError` would land on stdout and break the transport. Likewise keep the local echo on `process.stderr` / `console.error`, never `console.log`.
  - Verify nothing in the logging path writes to stdout.

## Log destination switch (`LOG_DESTINATION`)

Workspace convention (root `docs/log-destinations.md`): `LOG_DESTINATION` ∈ `file | grafana | both`. There is no file here, and the local sink is **stderr**:
- `file` → stderr echo only;
- `grafana` → OTLP only;
- `both` → stderr echo + OTLP.

Same variable name and values as every other project.

## Endpoint

`init(endpoint:)` is **required**; the server runs alongside the backend, so the local OTLP endpoint is reachable directly (`http://localhost:3100/otlp/v1/logs`) — no emulator/CORS nuance. Supply it via mind_mcp's env/config; the planner decides where. Don't hard-code.

## Definition of done

- `init({ project: "mind", service: "mind_mcp", endpoint })` at startup; `service.start` visible on restart (verify: `observe-logs since-restart mind_mcp --project mind`).
- Logs appear in Loki tagged `project=mind`, `service_name=mind_mcp`.
- **stdout remains clean** (MCP protocol intact); all local echo and SDK `onError` output is stderr-only.
- `LOG_DESTINATION` honored.
- No Docker introduced.
