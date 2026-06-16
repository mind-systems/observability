# tradeoxy_core — Integrate the observability logging SDK (Node/TS, NestJS)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. Today the broker writes its own log files and core writes its own, and debugging anything cross-cutting means merging timestamps by hand. Instead, every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, with restart markers, browsable in Grafana and queryable programmatically.

Integration is **transport-only**: keep your curated log lines, do **not** rewrite call sites, only change where output goes and add a one-time init.

This note is the scope/checklist for **tradeoxy_core**. It is intentionally light on SDK API specifics — the Node/TS SDK is not built yet and will be refined once it exists.

## Your SDK

**Node/TS SDK** (built by the observability project — Phase 2; shared with mind_api and mind_mcp). Prerequisite: that SDK milestone must be done first.

## Current logging in this project

- Winston via nest-winston, configured in **`src/common/logger/winston.config.ts`**.
- Injected as `@Inject(WINSTON_MODULE_NEST_PROVIDER) logger`; ~112 call sites across ~43 files; calls like `this.logger.log(msg, ServiceName.name)`.
- Transports: console (human-readable dev / JSON prod) + daily-rotate file `core-%DATE%.log`. File records are JSON `{ ts, svc: "core", msg }`.

**Single swap point: the `transports` array in `src/common/logger/winston.config.ts`.**

## What you need to do

1. **Add the SDK dependency.**
2. **Initialize once at bootstrap** (in `src/main.ts`): `init(project: "tradeoxy", service: "core")`. Emits the `service.start` restart marker (this directly fixes the "after restart I don't know where the logs begin" problem) and sets resource attributes.
3. **Add an OTLP transport** to the Winston `transports` array, alongside console/file (additive). All ~112 call sites stay unchanged.
4. **Bind incoming trace context per request.** core is the *callee* of the broker over gRPC. Add a gRPC interceptor that extracts the trace id from incoming gRPC metadata and runs the handler inside the SDK's `AsyncLocalStorage` context, so every core log emitted while handling a broker call carries the broker's `trace_id`. This is the "broker → core responded" leg of the chain. Propagate context on any outgoing calls.
5. **Honor conventions:** map Winston levels to SDK levels; the existing `svc: "core"` becomes `service=core`; the per-call context (`ServiceName.name`) and ids go into structured fields, not labels (only `project`, `service`, `level` are labels).

## Project-specific gotchas

- There is **no correlation id between broker and core today** — this integration introduces it. The whole value of doing core + broker together is seeing one webhook produce a single correlated chain.
- Bind trace context per gRPC call via interceptor; logs outside a request (startup, schedulers) simply carry no `trace_id`.

## Out of scope for now

Exact SDK API, OTLP transport options, endpoint config — deferred until the Node/TS SDK is built.

## Definition of done

- `init(project: "tradeoxy", service: "core")` at bootstrap; `service.start` visible in Grafana on restart.
- Existing log lines appear in Loki tagged `project=tradeoxy`, `service=core`, queryable via LogQL.
- A webhook handled by the broker and forwarded to core produces broker + core logs sharing one `trace_id`.
- No call sites rewritten; console/file logging preserved as desired; no Docker introduced.
