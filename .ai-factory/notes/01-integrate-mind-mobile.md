# mind_mobile — Integrate the observability logging SDK (Dart/Flutter)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. It replaces the current situation where every service writes its own log files (or just prints to console) and those have to be merged by hand on timestamps. Instead, every service ships its logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker). The payoff: all logs in one queryable place, correlated across services by a shared `trace_id`, with clear restart markers, browsable in a Grafana GUI and queryable programmatically.

Integration is **transport-only**: you keep your existing, curated log lines; you do **not** rewrite call sites. You only change where log output goes, and you add a one-time init at startup.

This note is the scope/checklist for integrating **mind_mobile**. It is intentionally light on SDK API specifics — the Dart/Flutter SDK is not built yet. It will be refined once the SDK exists. Do not implement against a guessed API; treat this as what-and-why.

## Your SDK

**Dart/Flutter SDK** (built by the observability project — Phase 2). Prerequisite: that SDK milestone must be done before this task starts.

## Current logging in this project

- Custom logger: `logPrint(Object?)` / `log(...)` in **`lib/Logger.dart`**, wrapping `dart:developer.log`. Format `[HH:mm:ss.SS] <message>`. **Console only — no persistence.**
- Network logging today: HTTP errors in `lib/Core/Api/HttpClient.dart`; gRPC errors via `lib/Core/Grpc/GrpcLoggingInterceptor.dart`.

**Single swap point: `lib/Logger.dart`** — the one place where output is produced.

## What you need to do

1. **Add the SDK dependency** to `pubspec.yaml`.
2. **Initialize once at app startup** (in `lib/main_dev.dart` / `lib/main_prod.dart`): `init(project: "mind", service: "mind_mobile")`. This sets resource attributes and emits the `service.start` restart marker (so logs after each launch are clearly delimited). Run the app inside the SDK's ambient context (`Zone`-based) so `trace_id` flows automatically.
3. **Route the sink through the SDK** in `lib/Logger.dart`: forward each record to the SDK **in addition to** the existing `dart:developer.log` console output (keep console for local dev). Call sites that use `log()` / `logPrint()` stay unchanged.
4. **Originate traces on user actions.** mind_mobile is the *start* of the chain ("button pressed"). On a user action that triggers a backend call, the SDK begins a trace; **inject `traceparent` on outgoing HTTP requests** (in `HttpClient.dart`) and trace id into **gRPC metadata** (in `GrpcLoggingInterceptor.dart`). This is what lets mind_api's logs share the same `trace_id` as the originating tap.
5. **Honor conventions:** levels mapped to the SDK's levels; only `project`, `service`, `level` are low-cardinality labels — never put ids or free text where labels are expected.

## Project-specific gotchas

- **No file logging on Flutter** — the SDK ships over the network (OTLP/HTTP). It must **batch** and tolerate offline / flaky mobile networks, buffering and degrading silently; a failed export must never throw into `logPrint`/`log` or affect the UI.
- Ambient context on Dart is `Zone`-based; the app must run within the SDK zone for `trace_id` to attach without touching call sites.

## Out of scope for now

Exact SDK method names, batching/buffer config, and endpoint configuration — deferred until the Dart/Flutter SDK is built. This note will be updated then.

## Definition of done

- `init(project: "mind", service: "mind_mobile")` called at startup; a `service.start` appears in Grafana after each app launch.
- The app's existing log lines appear in Loki tagged `project=mind`, `service=mind_mobile`, queryable via LogQL.
- A user action that calls the backend produces logs in mind_mobile **and** mind_api sharing one `trace_id`.
- No call sites rewritten; console output preserved; no Docker introduced.
