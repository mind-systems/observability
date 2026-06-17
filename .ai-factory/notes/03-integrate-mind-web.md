# mind_web — Integrate the observability logging SDK (observe-js, browser, React)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. Instead of scattered console output and per-service log files merged by hand, every part of the system ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated across services by a shared `trace_id`, browsable in Grafana and queryable via the `observe-logs` skill.

## Your SDK

**`observe-js`** — built and released, frozen at tag **`v0.1.0`** (isomorphic Node + browser; framework-agnostic; conforms to `observe-contract@v0.1.2`; shared with tradeoxy_gui). Add it as an npm git dependency pinned to that tag (Vite/the bundler resolves the `browser` export condition automatically):

```jsonc
// package.json
"dependencies": {
  "observe-js": "git+https://github.com/mind-systems/observe-js.git#v0.1.0"
}
```

Browser surface (`import … from "observe-js"`): `init`, `log`, `flush`, `shutdown`, `startSpan`/`withSpan`, `inject`/`extract`, **`tracedFetch`** / `withTraceparent` (the browser propagation helpers), `objectCarrier`/`headersCarrier` (+ `Level`, `Carrier`). The browser `init` also auto-registers an unload flush (`pagehide` / `visibilitychange` → `navigator.sendBeacon`) — you don't implement it. Confirm exact signatures against the `v0.1.0` tag.

## Current logging in this project

- **No custom logger.** Uses native `console.*` directly. The only notable call site found is `console.error(...)` in `src/pages/SessionsPage/useBiometricChunks.ts`.
- React 19 + TypeScript + Vite.

**Unlike the other projects, there is no single existing sink to swap** — you introduce a thin logging facade that calls the SDK and becomes the project's logger going forward.

## What you need to do

1. **Add the dependency** (above).
2. **Initialize once at app entry**: `init({ project: "mind", service: "mind_web", endpoint: <otlp url> })`. Sets resource attributes and emits the `service.start` marker on each load/reload; idempotent.
3. **Introduce a minimal logging facade** (e.g. `log.info/warn/error`) that forwards to the SDK `log` (and may keep `console` in dev). Replace ad-hoc `console.*` incrementally — start with error paths like `useBiometricChunks.ts`. There's no large body of curated lines here, so keep it lightweight.
4. **Originate traces on user actions.** mind_web is a *start* of the chain ("button pressed"). In the action handler, open a span and use the SDK's fetch helper for the outgoing call to mind_api: `withSpan(startSpan(), () => tracedFetch(...))` — `tracedFetch` injects `traceparent` from the active span, so mind_api's logs share the originating click's `trace_id`. (`withTraceparent(headers)` is the lower-level option if you don't use `tracedFetch`.)
5. **Honor conventions:** map console-style levels to SDK `Level`; only `project`, `service`, `level` are low-cardinality labels.

## Browser ambient-context boundary (read this — it changed)

Ambient context in the browser is a **lightweight explicit mechanism, NOT `zone.js`** (the contract deliberately avoids zone.js — heavy, invasive, Angular-specific). Be honest about its reach: the active span holds within the **synchronous call stack and the immediately-chained microtask** — enough for the dominant case (a click handler that *synchronously* calls `tracedFetch`). It does **not** survive arbitrary `await` hops; deep async propagation is deferred until TC39 `AsyncContext`. Practically: open the span and fire the traced request in the same handler, don't expect a span opened before a long `await` chain to still be active several awaits later.

## Endpoint & CORS (browser-specific gotcha)

`init(endpoint:)` is **required**. In local dev the browser can reach the backend at `http://localhost:3100/otlp/v1/logs`, but the web app is served from a different origin (e.g. Vite on `:5173`), so posting to Loki is **cross-origin → a CORS preflight**. Either allow the dev origin on the backend (CORS) or route the OTLP path through Vite's dev proxy. Supply the endpoint via Vite env (`import.meta.env.…`) — the planner decides where and how to handle CORS. This note flags the gotcha; it does not prescribe the config.

## Log destination switch (`LOG_DESTINATION`)

Workspace convention (root `docs/log-destinations.md`): `LOG_DESTINATION` ∈ `file | grafana | both`, applied in the facade. There is no file in the browser, so:
- `file` → `console.*` only;
- `grafana` → SDK (OTLP) only;
- `both` → console + OTLP.

Same variable name and values as every other project.

## Project-specific gotchas

- Keep the SDK footprint small. A failed/slow/unreachable export degrades silently (bounded buffer, drop-oldest) and never surfaces to the user or blocks the UI — a guarantee of the SDK, not something you implement.
- Because there's no existing logger, the main initial value is: restart/load markers, error capture, and being the trace origin for the mind chain.

## Definition of done

- `init({ project: "mind", service: "mind_web", endpoint })` at entry; `service.start` visible on load (verify: `observe-logs since-restart mind_web --project mind`).
- Logs routed through the facade appear in Loki tagged `project=mind`, `service_name=mind_web`.
- A user action that calls mind_api produces logs in both sharing one `trace_id` (verify: `observe-logs trace <id>`).
- `LOG_DESTINATION` honored; CORS path working for `grafana`/`both`.
- No Docker introduced.
