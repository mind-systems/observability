# mind_api — Integrate the observability logging SDK (Node/TS, NestJS)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. Today every service writes its own log files and they must be merged by hand on timestamps. Instead, every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): all logs in one queryable place, correlated across services by a shared `trace_id`, with clear restart markers, browsable in Grafana and queryable via the `observe-logs` skill.

Integration is **transport-only**: keep your curated log lines, do **not** rewrite call sites, only change where output goes and add a one-time init.

## Your SDK

**`observe-js`** — built and released, frozen at tag **`v0.1.0`** (isomorphic Node + browser; conforms to `observe-contract@v0.1.2`). Add it as an npm git dependency pinned to that tag (NestJS is CommonJS — the package's dual ESM+CJS build resolves the `require` entry automatically):

```jsonc
// package.json
"dependencies": {
  "observe-js": "git+https://github.com/mind-systems/observe-js.git#v0.1.0"
}
```

Node surface (`import … from "observe-js"`): `init`, `log`, `flush`, `shutdown`, `startSpan`/`withSpan`, `inject`/`extract`, `objectCarrier`/`headersCarrier` (+ `Level`, `Carrier`, `InitOptions`). The Winston adapter is a subpath: `import { ObserveTransport } from "observe-js/winston"`. Confirm exact signatures against the `v0.1.0` tag.

## Current logging in this project

- Winston via `WinstonModule.createLogger()` configured in **`src/main.ts`**.
- Per-service usage: `new Logger(ServiceName.name)` from `@nestjs/common`; `logger.log/warn/error/debug(...)`.
- Transports: console (colored in dev, JSON in prod) + daily-rotate files (`logs/error-%DATE%.log`, `logs/combined-%DATE%.log`).

**Single swap point: the Winston transports array in `src/main.ts`** (`WinstonModule` setup).

## What you need to do

1. **Add the dependency** (above). `winston` is already present.
2. **Initialize once at bootstrap** (`src/main.ts`, before the app handles traffic): `init({ project: "mind", service: "mind_api", endpoint: <otlp url> })`. Emits the `service.start` restart marker and sets resource attributes. Idempotent (second call no-ops).
3. **Add `ObserveTransport` to the Winston transports array** (from `observe-js/winston`), alongside the existing console/file transports — additive. All existing `logger.log(...)` call sites stay unchanged. The transport already **maps Winston levels to the canonical tokens** per the contract (`http`/`verbose`/`debug`→`debug`, `silly`→`trace`, rest 1:1) and strips Winston's `Symbol`-keyed meta — you don't implement level mapping.
4. **Bind incoming trace context per request** *(the main propagation job here — mind_api is a receiver, called by mind_web / mind_mobile).* Add a NestJS middleware/interceptor that `extract`s the inbound `traceparent` and runs the handler inside the SDK's ambient context, so every log emitted during that request carries the caller's `trace_id` — no call-site changes:
   - HTTP: `extract(objectCarrier(req.headers))` → if non-null, run the handler inside `runWithContext(ctx, …)`;
   - gRPC (where applicable): the same over a carrier built from the call metadata.
   Propagate onward (`inject`) on any outgoing calls mind_api makes. Requests with no inbound `traceparent`, and background/startup logs, simply carry no `trace_id` — that is fine.
5. **Honor conventions:** only `project`, `service`, `level` are low-cardinality labels; the per-service `context` (`ServiceName.name`) and any ids go into structured fields, not labels (the SDK enforces this).

## Endpoint (env-configurable; no mobile-style nuance)

`init(endpoint:)` is **required**. mind_api runs server-side alongside the backend, so the local OTLP endpoint is reachable directly (e.g. `http://localhost:3100/otlp/v1/logs`) — there is **no** emulator/device reachability nuance like mind_mobile. Still supply it through mind_api's existing config/env rather than hard-coding; the planner decides where. This note does not prescribe values or touch that config.

## Log destination switch (`LOG_DESTINATION`)

Workspace convention (see root `docs/log-destinations.md`): one switch `LOG_DESTINATION` ∈ `file | grafana | both`, applied at the transports array:
- `file` → existing console + daily-rotate file transports only;
- `grafana` → `ObserveTransport` only;
- `both` → both.

Use the same variable name and values as every other project.

## Project-specific gotchas

- Trace context must be bound **per request** (the middleware running the handler within the ambient context) — otherwise logs won't carry `trace_id`. This is the inbound counterpart to mind_mobile, which *originates* the trace; mind_api *inherits* it.
- A failed/slow/unreachable export never throws into `logger.log(...)` and never blocks request handling — the SDK degrades silently (bounded buffer, drop-oldest). Not something you implement.

## Definition of done

- `init({ project: "mind", service: "mind_api", endpoint })` at bootstrap; `service.start` visible on restart (verify: `observe-logs since-restart mind_api --project mind`).
- Existing log lines appear in Loki tagged `project=mind`, `service_name=mind_api`, queryable via LogQL / `observe-logs window … --project mind --service mind_api`.
- A request originating in mind_web/mind_mobile produces mind_api logs sharing the caller's `trace_id` (verify: `observe-logs trace <id>` shows both legs).
- `LOG_DESTINATION` honored (file / grafana / both).
- No call sites rewritten; console/file logging preserved as desired; no Docker introduced.
