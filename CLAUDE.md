# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **local, generic observability stack + multi-platform SDK** for debugging across projects. It replaces per-service file logging (each service writes its own files, manually merged by timestamp) with one place where structured logs — and later traces and profiles — are correlated automatically.

The SDK is the integration surface — drop it into any project on any supported platform and only the existing logger's transport changes. Two consumers from day one: **tradeoxy** and **mind** (both under `~/projects`). It currently runs **locally only**, for debugging on the developer's machine; a cloud deployment is a planned later step.

## Hard constraints

- **No Docker.** Docker is not acceptable on the target machine — it must not be required. Anything that only runs via Docker on macOS is disqualified (this is why SigNoz was rejected).
- **Native on macOS.** Backend components must run as native processes (Homebrew binaries / `brew services`).

## Scope now: logs only

Only logging is in scope right now. Traces and profiling are on the roadmap but **not** built yet. Everything below is designed so adding them later requires **no re-platforming** — see "Growth path".

## Core decision: don't build the engine

The need decomposes into solved problems — **structured logging**, **distributed tracing via correlation IDs**, and **continuous profiling** — so the storage/query/UI engine is taken off the shelf, not written. What gets built here is a thin SDK and a set of conventions.

The real future-proofing is **OTLP at the SDK boundary**: every SDK emits OpenTelemetry OTLP, which is the only contract the host apps depend on. The backend behind OTLP stays swappable — local today, cloud tomorrow, more signals over the same wire.

- **Transport / SDK → OTLP.** Each consuming project keeps its own logger and changes only the sink. Because the official OpenTelemetry SDKs are uneven across our platforms (Dart/Flutter and browser logging are weak), the SDK is a **thin house library per platform that speaks OTLP/HTTP**, with a uniform minimal API.
- **Backend → Grafana family (off-the-shelf, native, no Docker).** Chosen because it is the only ecosystem that covers the entire roadmap in one place with cross-signal correlation: **Loki** (logs), **Tempo** (traces → service graph / pipelines), **Pyroscope** (profiling → flamegraphs), **Mimir** (metrics), all visualized in **Grafana**, all OTLP-native, with a mature cloud story (Grafana Cloud ingests OTLP directly).

**Now we stand up only Grafana + Loki (logs).** Tempo, Pyroscope, Mimir, and cloud are deferred.

## The loggers are custom — only the transport moves

Every consuming project already has a deliberately curated, custom logger. The developer writes exactly the lines they care about and avoids noisy default framework logging. **No call sites are rewritten.** In each project the output sink is localized to a single place; that is the only thing that changes.

| Project | Stack | Logger | Single swap point |
|---|---|---|---|
| tradeoxy_broker | Swift | custom `actor Logger`, API `log(svc:_:)`, ~168 sites, JSON `{ts,svc,msg}`, **independent of swift-log** | `Logger.append(svc:msg:)` in `Sources/App/Managers/Logger.swift` |
| tradeoxy_core | NestJS | Winston (nest-winston), ~112 sites, JSON `{ts,svc,msg}` | `transports` in `src/common/logger/winston.config.ts` |
| mind_api | NestJS | Winston, JSON | `WinstonModule` in `src/main.ts` |
| mind_mobile | Flutter/Dart | `logPrint`/`log` in `lib/Logger.dart` (`dart:developer.log`) | `lib/Logger.dart` |
| mind_web | React/TS | none (bare `console`) | new thin wrapper |
| tradeoxy_gui | Angular | none (bare `console`) | new thin wrapper |
| mind_mcp | Node/TS | `console.error` → stderr | optional |

## SDK targets and API

Four platform targets cover everything: **Swift** (broker), **Node/TS** (core, mind_api, mcp), **web JS** (mind_web React, tradeoxy_gui Angular — framework-agnostic), **Dart/Flutter** (mind_mobile).

Uniform minimal surface on every platform:

- `init(project, service)` — sets resource attributes (`project`, `service.name`, a fresh `service.instance.id`) and emits the `service.start` restart marker.
- `log(level, msg, attrs?)` — what the project's existing sink calls (the custom `append`, the Winston transport, `logPrint`, etc.).
- trace context — `startSpan` / `withSpan`, plus inject/extract for HTTP headers and gRPC metadata. (Logs carry `trace_id` now; spans are exported once Tempo is added.)

## Cross-service correlation

The point: reconstruct a chain end to end — button pressed in web → webhook → broker handled it → core responded — as one correlated view, with no manual timestamp merging.

No correlation id exists between broker and core today (the only shared shape is the `{ts,svc,msg}` JSON). The SDK introduces `trace_id` transparently: it is injected automatically via ambient context storage — `@TaskLocal` (Swift), `AsyncLocalStorage` (Node), `Zone` (Dart/web) — so **call sites do not change**. Trace context propagates web → broker (`traceparent` header) → core (gRPC metadata). Now, every log line is stamped with `trace_id`; once Tempo is added, Grafana stitches logs↔traces by that id.

## Multi-project model

Isolation is handled with **resource attributes**: every service sets `project=<name>` (`tradeoxy`, `mind`) plus a `service.name`. Filtering by `project` in Grafana and the query API gives per-project and cross-project views.

**Loki labels stay low-cardinality** — only `project`, `service`, `level` become labels; `trace_id` and other high-cardinality fields live in the log body / structured metadata, never as labels.

## Restart markers

After a restart it must be obvious where to start reading. Each service gets a fresh `service.instance.id` on `init` and emits a `service.start` event. "Logs since last restart" is then a query for everything after the latest `service.start` for that service.

## How Claude queries logs

Claude pulls the needed slice itself via the **Loki HTTP API (LogQL)**, while the developer browses and selects lines visually in Grafana and hands them over. Typical requests: the full feed since a service's last `service.start`, logs in a time window filtered by level and `project`, or everything sharing a `trace_id`. (Tempo's TraceQL is added with traces later.)

## What gets built here

- The four platform SDKs (Swift, Node/TS, web JS, Dart/Flutter) with the API above and an OTLP/HTTP exporter.
- Native (no-Docker) run configuration for Grafana + Loki: Loki config + Grafana provisioning (datasource, dashboards).
- Trace-context propagation glue for webhook → broker → core → web.
- A thin query wrapper / MCP glue for the common debug slices.

## Growth path (deferred, no re-platform)

- **Traces** → add Tempo; SDKs already export spans over the same OTLP endpoint; Grafana gains service graph / pipelines.
- **Profiling / flamegraphs** → add Pyroscope; trace→profile correlation in Grafana.
- **Metrics** → add Mimir.
- **Cloud** → point the OTLP exporter at Grafana Cloud (it ingests OTLP directly). SDKs and call sites do not change.
- **E2E from observed flows** → build on recorded traces via the backend query API.

## Language

All files — docs, plans, config, generated files — are written in **English**, regardless of the conversation language.

## Architecture

See `.ai-factory/ARCHITECTURE.md` for module boundaries, the OTLP contract, folder structure, and dependency rules.

## Status

Greenfield. No application code yet. This file captures the architecture decisions agreed before implementation.
