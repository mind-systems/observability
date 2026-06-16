# tradeoxy_gui — Integrate the observability logging SDK (Web JS, Angular)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. Instead of scattered console output and per-service log files merged by hand, every part of the system ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, browsable in Grafana and queryable programmatically.

This note is the scope/checklist for **tradeoxy_gui**. It is intentionally light on SDK API specifics — the Web JS SDK is not built yet and will be refined once it exists.

## Your SDK

**Web JS SDK** (built by the observability project — Phase 2; framework-agnostic, the same SDK used by mind_web). Prerequisite: that SDK milestone must be done first.

## Current logging in this project

- **No custom logger.** Angular 21 app using native `console.*`.

**No single existing sink to swap** — you introduce a thin logging facade (an Angular logging service is the natural shape) that calls the SDK and becomes the project's logger.

## What you need to do

1. **Add the SDK dependency.**
2. **Initialize once at startup** (app bootstrap / `APP_INITIALIZER`): `init(project: "tradeoxy", service: "tradeoxy_gui")`. Sets resource attributes and emits the `service.start` marker on each load.
3. **Introduce a logging facade** — an injectable Angular service (`log.info/warn/error`) that forwards to the SDK (keep `console` in dev if useful). Adopt it across the app incrementally; start with error paths and HTTP failures.
4. **Originate traces on user actions.** tradeoxy_gui is the "button pressed" origin for the tradeoxy chain. On a user action that calls the backend, the SDK begins a trace and **injects `traceparent` on outgoing HTTP requests** (an Angular `HttpInterceptor` is the clean place) to the broker/core APIs, so their logs share the originating click's `trace_id`.
5. **Honor conventions:** levels mapped to SDK levels; only `project`, `service`, `level` are low-cardinality labels.

## Project-specific gotchas

- Browser environment: keep footprint small; ambient context is `Zone`-based (Angular already runs in Zone.js — coordinate so `trace_id` attaches cleanly). The SDK ships over the network and must degrade silently — never surface export failures to the user.
- Same Web JS SDK as mind_web — only the `project`/`service` tags and the framework glue (Angular interceptor vs React fetch wrapper) differ.

## Out of scope for now

Exact SDK API, the facade/interceptor final shape, batching and endpoint config — deferred until the Web JS SDK is built.

## Definition of done

- `init(project: "tradeoxy", service: "tradeoxy_gui")` at startup; `service.start` visible in Grafana on load.
- Logs routed through the facade appear in Loki tagged `project=tradeoxy`, `service=tradeoxy_gui`.
- A user action that calls the backend produces gui + backend logs sharing one `trace_id`.
- No Docker introduced.
