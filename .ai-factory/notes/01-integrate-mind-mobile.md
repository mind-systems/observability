# mind_mobile — Integrate the observability logging SDK (Dart/Flutter)

**Date:** 2026-06-18
**Source:** conversation context

## Context (read this if you have none)

There is a local observability system — the `observability` project under `~/projects`. It replaces the current situation where every service writes its own log files (or just prints to console) and those have to be merged by hand on timestamps. Instead, every service ships its logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker). The payoff: all logs in one queryable place, correlated across services by a shared `trace_id`, with clear restart markers, browsable in a Grafana GUI and queryable programmatically (via the `observe-logs` skill).

Integration is **transport-only**: you keep your existing, curated log lines; you do **not** rewrite call sites. You only change where log output goes, and you add a one-time init at startup.

## Your SDK

**`observe-dart`** — built and released, frozen at tag **`v0.1.0`** (conforms to `observe-contract@v0.1.2`). Add it as a pub `git:` dependency pinned to that tag:

```yaml
dependencies:
  observe:
    git:
      url: https://github.com/mind-systems/observe-dart.git
      ref: v0.1.0
```

It is pure Dart (Flutter is touched only by the sink adapter), one runtime dependency (`http`). Public surface (import `package:observe/observe.dart`): `init`, `log`, `flush`, `shutdown`, `startSpan`/`withSpan`, `inject`/`extract` (+ `Level`, `Carrier`/`MapCarrier`, `Span`), and the sink adapter `observeSink` / `observeLogPrint`. Confirm exact signatures against the `v0.1.0` tag.

## Current logging in this project

- Custom logger: `logPrint(Object?)` / `log(...)` in **`lib/Logger.dart`**, wrapping `dart:developer.log`. Format `[HH:mm:ss.SS] <message>`. **Console only — no persistence.**
- Network logging today: HTTP errors in `lib/Core/Api/HttpClient.dart`; gRPC errors via `lib/Core/Grpc/GrpcLoggingInterceptor.dart`.

**Single swap point: `lib/Logger.dart`** — the one place where output is produced.

## What you need to do

1. **Add the dependency** (above) and run `pub get`.
2. **Initialize once at app startup** (`lib/main_dev.dart` / `lib/main_prod.dart`):
   `init(project: "mind", service: "mind_mobile", endpoint: <otlp url>)`. This sets resource attributes and emits the `service.start` restart marker (so logs after each launch are clearly delimited). `init` is idempotent (second call no-ops). Run the app inside the SDK's ambient context (native `Zone`) so `trace_id` flows automatically.
3. **Route the sink through the SDK** in `lib/Logger.dart`: forward each record to **`observeSink(message, level: …)`** from `observe-dart`, **in addition to** the existing `dart:developer.log` console output. The level-less `logPrint` maps to `info` (the contract's host→canonical default). Call sites that use `log()` / `logPrint()` stay unchanged. (`observeLogPrint()` returns a drop-in `void Function(Object?)` if you prefer a closure.)
4. **Originate traces on user actions.** mind_mobile is the *start* of the chain ("button pressed"). Wrap the action handler in `withSpan(...)` (or mint via `startSpan()`), then **inject `traceparent`**:
   - outgoing HTTP in `HttpClient.dart`: wrap the request headers map in a `MapCarrier` and call `inject` — adds the `traceparent` header;
   - outgoing gRPC in `GrpcLoggingInterceptor.dart`: wrap the call metadata in a `MapCarrier` and `inject`.
   This is what lets mind_api's logs share the same `trace_id` as the originating tap (propagation is carrier-agnostic — no gRPC dependency in the SDK).
5. **Honor conventions:** only `project`, `service`, `level` are low-cardinality labels — never put ids or free text where labels are expected (the SDK already enforces this; just don't fight it).

## Endpoint (must be set per build type)

`init(endpoint:)` is **required** and environment-specific: the backend runs on the developer's machine, so plain `localhost` is **not** reachable from an emulator / simulator / physical device. mind_mobile already configures URLs per build type — **the OTLP endpoint URL belongs in that existing build-type config; the planner decides where.** This note does not prescribe values or touch that config — it only flags that the URL must be supplied and is build-dependent.

## Log destination switch (`LOG_DESTINATION`)

The workspace convention (see root `docs/log-destinations.md`) is one switch, `LOG_DESTINATION` ∈ `file | grafana | both`, read at the swap point. For mobile there is no file sink, so:
- `file` → existing `dart:developer.log` console output only (SDK not wired);
- `grafana` → OTLP via `observeSink` only;
- `both` → console + OTLP.

Default per build is the project's call (e.g. `both` for dev). Use the same variable name and values as every other project.

## Project-specific gotchas

- **No file logging on Flutter** — the SDK ships over the network (OTLP/HTTP). It already batches, tolerates offline / flaky mobile networks (bounded buffer, drop-oldest), and degrades silently; a failed export never throws into `logPrint`/`log` or affects the UI. (These are guarantees of `observe-dart`, not something you implement.)
- Ambient context on Dart is native `Zone` — real propagation across `await`. The app must run within the SDK's context for `trace_id` to attach without touching call sites.

## Definition of done

- `init(project: "mind", service: "mind_mobile", endpoint: …)` at startup; a `service.start` appears in Grafana after each app launch (verify: `observe-logs since-restart mind_mobile --project mind`).
- The app's existing log lines appear in Loki tagged `project=mind`, `service_name=mind_mobile`, queryable via LogQL / `observe-logs window … --project mind --service mind_mobile`.
- A user action that calls the backend produces logs in mind_mobile **and** mind_api sharing one `trace_id` (verify: `observe-logs trace <id>`).
- `LOG_DESTINATION` honored (file / grafana / both).
- No call sites rewritten; console output preserved; no Docker introduced.
