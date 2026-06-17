# tradeoxy_gui — Integrate the observability logging SDK (observe-js, browser, Angular)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. Instead of scattered console output and per-service log files merged by hand, every part of the system ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, browsable in Grafana and queryable via the `observe-logs` skill.

## Your SDK

**`observe-js`** — built and released, frozen at tag **`v0.1.0`** (isomorphic Node + browser; framework-agnostic; conforms to `observe-contract@v0.1.2`; the same package mind_web uses). Add it as an npm git dependency pinned to that tag (the Angular/esbuild bundler resolves the `browser` export condition):

```jsonc
// package.json
"dependencies": {
  "observe-js": "git+https://github.com/mind-systems/observe-js.git#v0.1.0"
}
```

Browser surface (`import … from "observe-js"`): `init`, `log`, `flush`, `shutdown`, `startSpan`/`withSpan`, `inject`/`extract`, `withTraceparent`, `objectCarrier`/`headersCarrier` (+ `Level`, `Carrier`). Note `tracedFetch` is a `fetch` helper — **Angular uses `HttpClient`, so propagate via an `HttpInterceptor`** with `inject`/`withTraceparent` instead (see below). Confirm signatures against `v0.1.0`.

## Current logging in this project

- **No custom logger.** Angular app using native `console.*`.

**No single existing sink to swap** — you introduce a thin logging facade (an injectable Angular logging service is the natural shape) that calls the SDK and becomes the project's logger.

## What you need to do

1. **Add the dependency** (above).
2. **Initialize once at startup** (`APP_INITIALIZER` / app bootstrap): `init({ project: "tradeoxy", service: "tradeoxy_gui", endpoint: <otlp url> })`. Sets resource attributes and emits the `service.start` marker on each load; idempotent. The browser `init` auto-registers the unload flush (`pagehide`/`visibilitychange` → `sendBeacon`).
3. **Introduce a logging facade** — an injectable Angular service (`log.info/warn/error`) forwarding to the SDK `log` (keep `console` in dev if useful). Adopt incrementally; start with error paths and HTTP failures.
4. **Originate traces on user actions + an `HttpInterceptor` for propagation.** tradeoxy_gui is the "button pressed" origin for the tradeoxy chain. In the action handler open a span (`withSpan`/`startSpan`); add an Angular `HttpInterceptor` that injects `traceparent` onto outgoing requests — read the active context and set the header on the cloned `HttpRequest` (via `withTraceparent` over a headers map, or `inject` into a carrier). So broker/core logs share the originating click's `trace_id`.
5. **Honor conventions:** map console-style levels to SDK `Level`; only `project`, `service`, `level` are low-cardinality labels.

## Browser ambient context — explicit, NOT Angular's `zone.js` (read this — it changed)

The SDK's ambient context is a **lightweight explicit mechanism**; it deliberately does **not** use `zone.js`. Angular ships its own Zone.js for change detection, but that is **unrelated** — do **not** try to attach `trace_id` through Angular's zone. Just use `withSpan`/`startSpan` and the interceptor.

Be honest about the boundary: the active span holds within the **synchronous call stack and the immediately-chained microtask**. So the `HttpInterceptor` sees the active context only when the request is **dispatched within the synchronous span scope**. If the user action → HTTP dispatch goes through `async`/`await` or a multi-step **RxJS** pipeline first, the explicit context can be gone by the time the interceptor runs (no `trace_id` on that request). Practical guidance: keep the span scope tight around the dispatch, or carry the span/context explicitly to the call when an async hop sits between the click and the request. Deep async propagation is deferred until TC39 `AsyncContext`.

## Endpoint & CORS (browser-specific gotcha)

`init(endpoint:)` is **required**. In local dev the browser reaches the backend at `http://localhost:3100/otlp/v1/logs`, but the Angular app is served from a different origin, so posting to Loki is **cross-origin → a CORS preflight**. Either allow the dev origin on the backend (CORS) or route the OTLP path through the Angular dev-server proxy. Supply the endpoint via Angular environment config — the planner decides where and how to handle CORS. This note flags the gotcha; it does not prescribe the config.

## Log destination switch (`LOG_DESTINATION`)

Workspace convention (root `docs/log-destinations.md`): `LOG_DESTINATION` ∈ `file | grafana | both`, applied in the facade. No file in the browser:
- `file` → `console.*` only;
- `grafana` → SDK (OTLP) only;
- `both` → console + OTLP.

Same variable name and values as every other project.

## Project-specific gotchas

- Same SDK as mind_web — only the `project`/`service` tags and the framework glue differ (**Angular `HttpInterceptor`** here vs the React `tracedFetch` wrapper there).
- Keep the footprint small. A failed/slow export degrades silently (bounded buffer, drop-oldest) and never surfaces to the user — a guarantee of the SDK.

## Definition of done

- `init({ project: "tradeoxy", service: "tradeoxy_gui", endpoint })` at startup; `service.start` visible on load (verify: `observe-logs since-restart tradeoxy_gui --project tradeoxy`).
- Logs routed through the facade appear in Loki tagged `project=tradeoxy`, `service_name=tradeoxy_gui`.
- A user action that calls the backend produces gui + backend logs sharing one `trace_id` (verify: `observe-logs trace <id>`).
- `LOG_DESTINATION` honored; CORS path working for `grafana`/`both`.
- No Docker introduced.
