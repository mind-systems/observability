# tradeoxy_core — Integrate the observability logging SDK (observe-js, Node, NestJS)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. Today the broker writes its own log files and core writes its own, and debugging anything cross-cutting means merging timestamps by hand. Instead, every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, with restart markers, browsable in Grafana and queryable via the `observe-logs` skill.

Integration is **transport-only**: keep your curated log lines, do **not** rewrite call sites, only change where output goes and add a one-time init.

## Your SDK

**`observe-js`** — built and released, frozen at tag **`v0.1.0`** (isomorphic Node + browser; conforms to `observe-contract@v0.1.2`; shared with mind_api and mind_mcp). Add it as an npm git dependency pinned to that tag (NestJS is CommonJS — the dual ESM+CJS build resolves the `require` entry):

```jsonc
// package.json
"dependencies": {
  "observe-js": "git+https://github.com/mind-systems/observe-js.git#v0.1.0"
}
```

Node surface (`import … from "observe-js"`): `init`, `log`, `flush`, `shutdown`, `startSpan`/`withSpan`, `inject`/`extract`, `objectCarrier`/`headersCarrier` (+ `Level`, `Carrier`). Winston adapter at the subpath: `import { ObserveTransport } from "observe-js/winston"`. Confirm exact signatures against `v0.1.0`.

## Current logging in this project

- Winston via nest-winston, configured in **`src/common/logger/winston.config.ts`**.
- Injected as `@Inject(WINSTON_MODULE_NEST_PROVIDER) logger`; ~112 call sites across ~43 files; calls like `this.logger.log(msg, ServiceName.name)`.
- Transports: console (human-readable dev / JSON prod) + daily-rotate file `core-%DATE%.log`. File records are JSON `{ ts, svc: "core", msg }`.

**Single swap point: the `transports` array in `src/common/logger/winston.config.ts`.**

## What you need to do

1. **Add the dependency** (above). `winston` is already present.
2. **Initialize once at bootstrap** (`src/main.ts`): `init({ project: "tradeoxy", service: "core", endpoint: <otlp url> })`. Emits the `service.start` restart marker (fixes "after restart I don't know where the logs begin") and sets resource attributes. Idempotent.
3. **Add `ObserveTransport`** (from `observe-js/winston`) to the Winston `transports` array, alongside console/file — additive. All ~112 call sites stay unchanged. The transport maps Winston levels to canonical tokens per the contract and strips `Symbol`-keyed meta — you don't implement level mapping.
4. **Bind incoming trace context per gRPC call** *(the key leg — core is the callee of the broker over gRPC).* Add a gRPC interceptor that builds a carrier over the **incoming gRPC metadata** (e.g. `objectCarrier` over its string map), `extract`s the context, and runs the handler inside `runWithContext(ctx, …)`. Then every core log emitted while handling a broker call carries the broker's `trace_id` — the "broker → core responded" leg. No call-site changes. Logs outside a request (startup, schedulers) simply carry no `trace_id`.
5. **Honor conventions:** the existing `svc: "core"` becomes the `service=core` label; the per-call `context` (`ServiceName.name`) and ids go into structured fields, not labels (only `project`, `service`, `level` are labels — the SDK enforces this).

## Endpoint (env-configurable; no mobile/browser nuance)

`init(endpoint:)` is **required**. core runs server-side alongside the backend, so the local OTLP endpoint is reachable directly (`http://localhost:3100/otlp/v1/logs`) — no emulator/CORS nuance. Supply it via core's existing config/env; the planner decides where. Don't hard-code.

## Log destination switch (`LOG_DESTINATION`)

Workspace convention (root `docs/log-destinations.md`): `LOG_DESTINATION` ∈ `file | grafana | both`, applied at the transports array:
- `file` → existing console + daily-rotate file transports only;
- `grafana` → `ObserveTransport` only;
- `both` → both.

Same variable name and values as every other project.

## Project-specific gotchas

- There is **no correlation id between broker and core today** — this integration introduces it. The whole value of doing core + broker together is seeing one webhook produce a single correlated chain (broker extracts the webhook's `traceparent` and injects it into the outbound gRPC metadata; core extracts it here).
- Bind trace context per gRPC call via the interceptor; do not thread anything through call sites.
- A failed/slow/unreachable export never throws into `this.logger.log(...)` and never blocks request handling — the SDK degrades silently (bounded buffer, drop-oldest).

## Definition of done

- `init({ project: "tradeoxy", service: "core", endpoint })` at bootstrap; `service.start` visible on restart (verify: `observe-logs since-restart core --project tradeoxy`).
- Existing log lines appear in Loki tagged `project=tradeoxy`, `service_name=core`, queryable via LogQL / `observe-logs window … --project tradeoxy --service core`.
- A webhook handled by the broker and forwarded to core produces broker + core logs sharing one `trace_id` (verify: `observe-logs trace <id>` shows both legs).
- `LOG_DESTINATION` honored.
- No call sites rewritten; console/file logging preserved as desired; no Docker introduced.
