# Observability Stack & Multi-Platform SDK

## Overview

A local, generic observability stack plus a thin multi-platform SDK for debugging across projects. It replaces per-service file logging — where each service writes its own files that must be merged by hand on timestamps — with one place where structured logs (and, later, traces and profiles) are correlated automatically.

The SDK is the integration surface: drop it into any project on a supported platform and only the existing logger's transport changes. The deliberately curated, custom loggers in each project keep their call sites unchanged. Two consumers from day one — **tradeoxy** and **mind** — but the design is project-agnostic. It currently runs locally only; a cloud deployment is a planned later step.

## Hard Constraints

- **No Docker.** Must not be required on the target machine; Docker-only tools on macOS are disqualified.
- **Native on macOS.** Backend components run as native Homebrew processes.

## Scope

Logging only, for now. Traces and profiling are on the roadmap but not yet built. The design adds them later with no re-platforming.

## Core Features

- **Transport-only integration.** Each project keeps its custom logger; only the output sink is swapped to ship over OTLP. No call sites are rewritten.
- **Cross-service correlation.** A `trace_id` propagates web → broker → core and is injected transparently via ambient context, so a full chain (button pressed → webhook → broker handled → core responded) is reconstructed without manual timestamp merging.
- **Multi-project isolation via resource attributes.** Every service tags `project=<name>` and a `service.name`; filtering gives per-project and cross-project views.
- **Restart markers.** Each service emits a `service.start` event with a fresh `service.instance.id`, so "logs since last restart" is a precise query.
- **LLM- and human-friendly querying.** Logs live in a queryable backend with an HTTP API (LogQL) and a GUI (Grafana), so the developer can browse and select lines while an agent pulls exact slices programmatically.

## Tech Stack

- **SDK platforms:** Swift (broker), Node/TypeScript (core, mind_api, mcp), web JS — framework-agnostic (mind_web React, tradeoxy_gui Angular), Dart/Flutter (mind_mobile)
- **Transport / protocol:** OpenTelemetry OTLP over HTTP (thin house exporter per platform) — the swappable boundary
- **Backend (off-the-shelf, native, no Docker):** Grafana family — **Loki** (logs, now), with **Tempo** (traces), **Pyroscope** (profiling/flamegraphs), **Mimir** (metrics) on the growth path; **Grafana** as the UI
- **Ambient trace context:** `@TaskLocal` (Swift), `AsyncLocalStorage` (Node), `Zone` (Dart/web)

## Architecture

Detailed guidelines in `.ai-factory/ARCHITECTURE.md`.
Pattern: contract-driven integration — OTLP is the single boundary between host apps and a swappable, off-the-shelf backend.

## Architecture Notes

Two layers are kept strictly separate so the backend is swappable without touching application code:

- **Transport / SDK** — a thin house library per platform that speaks OTLP/HTTP, with a uniform minimal API (`init(project, service)`, `log(level, msg, attrs?)`, `startSpan` / `withSpan`, context inject/extract). The house approach is chosen because official OTel SDKs are uneven across our platforms (Dart/Flutter and browser logging are weak).
- **Backend / storage / query / UI** — the Grafana family is taken off the shelf and run natively; the engine is not built here. Grafana was chosen over single-binary alternatives (e.g. OpenObserve) because it is the only ecosystem that covers the full roadmap — logs, traces, **profiling/flamegraphs**, metrics, and cloud — in one correlated stack.

What is built here: the four SDKs, the native (no-Docker) Loki + Grafana run configuration, the trace-context propagation glue, and a thin query/MCP wrapper for common debug slices.

## Non-Functional Requirements

- **No Docker; native macOS** — hard constraints on the backend.
- **Integration cost:** swapping transport must touch a single sink point per project; call sites stay untouched.
- **Logging:** structured records carry `project`, `service.name`, `service.instance.id`, level, message, `trace_id`. Loki labels stay low-cardinality (`project`, `service`, `level` only).
- **Correlation:** `trace_id` injected via ambient context, never threaded through call sites.
- **Portability:** uniform SDK API across all four platforms, and OTLP as the wire so the backend (local → cloud, logs → traces → profiles) can change without touching host apps.
