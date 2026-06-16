# mind_api — Integrate the observability logging SDK (Node/TS, NestJS)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. Today every service writes its own log files and they must be merged by hand on timestamps. Instead, every service will ship logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): all logs in one queryable place, correlated across services by a shared `trace_id`, with clear restart markers, browsable in Grafana and queryable programmatically.

Integration is **transport-only**: keep your curated log lines, do **not** rewrite call sites, only change where output goes and add a one-time init.

This note is the scope/checklist for **mind_api**. It is intentionally light on SDK API specifics — the Node/TS SDK is not built yet and this note will be refined once it exists. Treat it as what-and-why, not an implementation spec.

## Your SDK

**Node/TS SDK** (built by the observability project — Phase 2; shared with mind_mcp and tradeoxy_core). Prerequisite: that SDK milestone must be done first.

## Current logging in this project

- Winston via `WinstonModule.createLogger()` configured in **`src/main.ts`**.
- Per-service usage: `new Logger(ServiceName.name)` from `@nestjs/common`; `logger.log/warn/error/debug(...)`.
- Transports: console (colored in dev, JSON in prod) + daily-rotate files (`logs/error-%DATE%.log`, `logs/combined-%DATE%.log`).

**Single swap point: the Winston transports array in `src/main.ts`** (`WinstonModule` setup).

## What you need to do

1. **Add the SDK dependency.**
2. **Initialize once at bootstrap** (in `src/main.ts`, before the app handles traffic): `init(project: "mind", service: "mind_api")`. Emits the `service.start` restart marker and sets resource attributes.
3. **Add an OTLP transport** to the Winston transports array, alongside the existing console/file transports (additive — keep console for local dev). All ~existing `logger.log(...)` call sites stay unchanged.
4. **Bind incoming trace context per request.** mind_api is a *receiver* in the chain (called by mind_web / mind_mobile). Add a NestJS middleware/interceptor that extracts the incoming `traceparent` header (and trace id from gRPC metadata where applicable) and runs the request inside the SDK's `AsyncLocalStorage` context. This makes every log line emitted during that request automatically carry the caller's `trace_id` — no call-site changes. Propagate the context onward on any outgoing calls.
5. **Honor conventions:** map Winston levels to SDK levels; only `project`, `service`, `level` are low-cardinality labels; the per-service `context` (`ServiceName.name`) and any ids go into structured fields, not labels.

## Project-specific gotchas

- Trace context must be bound **per request** (NestJS middleware running the handler within the ALS context) — otherwise logs won't carry `trace_id`. Background jobs / startup logs will simply have no `trace_id`, which is fine.

## Out of scope for now

Exact SDK method names, the OTLP transport's options, and endpoint config — deferred until the Node/TS SDK is built.

## Definition of done

- `init(project: "mind", service: "mind_api")` at bootstrap; `service.start` visible in Grafana on restart.
- Existing log lines appear in Loki tagged `project=mind`, `service=mind_api`, queryable via LogQL.
- A request originating in mind_web/mind_mobile produces mind_api logs sharing the caller's `trace_id`.
- No call sites rewritten; console/file logging preserved as desired; no Docker introduced.
