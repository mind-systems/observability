# mind_web — Integrate the observability logging SDK (Web JS, React)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. Instead of scattered console output and per-service log files merged by hand, every part of the system ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, browsable in Grafana and queryable programmatically.

This note is the scope/checklist for **mind_web**. It is intentionally light on SDK API specifics — the Web JS SDK is not built yet and this note will be refined once it exists.

## Your SDK

**Web JS SDK** (built by the observability project — Phase 2; framework-agnostic, shared with tradeoxy_gui). Prerequisite: that SDK milestone must be done first.

## Current logging in this project

- **No custom logger.** Uses native `console.*` directly. The only notable call site found is `console.error(...)` in `src/pages/SessionsPage/useBiometricChunks.ts`.
- React 19 + TypeScript + Vite.

**Unlike the other projects, there is no single existing sink to swap** — you introduce a thin logging facade that calls the SDK and becomes the project's logger going forward.

## What you need to do

1. **Add the SDK dependency.**
2. **Initialize once at app entry**: `init(project: "mind", service: "mind_web")`. Sets resource attributes and emits the `service.start` marker on each load/reload.
3. **Introduce a minimal logging facade** (e.g. `log.info/warn/error`) that forwards to the SDK (and may also keep `console` output in dev). Replace ad-hoc `console.*` calls with it incrementally — start with error paths like `useBiometricChunks.ts`. There is no large body of curated log lines here, so keep it lightweight.
4. **Originate traces on user actions.** mind_web is a *start* of the chain ("button pressed"). On a user action that triggers a backend call, the SDK begins a trace and **injects `traceparent` on outgoing HTTP requests** to mind_api (wrap the fetch/HTTP layer). This is what lets mind_api's logs share the originating click's `trace_id`.
5. **Honor conventions:** levels mapped to SDK levels; only `project`, `service`, `level` are low-cardinality labels.

## Project-specific gotchas

- Browser environment: keep the SDK footprint small; ambient context is `Zone`-based. The SDK ships over the network (OTLP/HTTP) and must degrade silently — a failed export must never surface to the user or block the UI.
- Because there's no existing logger, the main initial value is: restart/load markers, error capture, and being the trace origin for the mind chain.

## Out of scope for now

Exact SDK API, the facade's final shape, batching and endpoint config — deferred until the Web JS SDK is built.

## Definition of done

- `init(project: "mind", service: "mind_web")` at entry; `service.start` visible in Grafana on load.
- Logs routed through the facade appear in Loki tagged `project=mind`, `service=mind_web`.
- A user action that calls mind_api produces logs in both sharing one `trace_id`.
- No Docker introduced.
