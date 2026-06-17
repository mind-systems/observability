# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **local, no-Docker observability stack + a thin multi-platform SDK** for debugging across projects. It replaces per-service file logging (each service writes its own files, manually merged by timestamp) with one place where structured logs — and later traces and profiles — are correlated automatically by `trace_id`.

This root repo is the **coordination layer**. It holds the architecture, roadmap, AI context, and the local backend run-config and tooling. The platform SDKs each live in their own git repository cloned inside this directory. The SDK is the integration surface: drop it into any project on any supported platform and only the existing logger's transport changes. Two consumers from day one — **tradeoxy** and **mind** (both under `~/projects`) — but the SDK is project-agnostic. Local only for now; cloud is a planned later step.

## Repository structure

The SDKs are **separate git repositories** (each has its own `.git`) living inside this root as subdirectories, excluded from the root's tracking via `.gitignore`.

| Directory | GitHub | Stack | Purpose |
|---|---|---|---|
| `observe-swift/` | [observe-swift](https://github.com/mind-systems/observe-swift) | Swift / SwiftPM | Swift OTLP/HTTP logging SDK — separate git repo |
| `observe-dart/` | [observe-dart](https://github.com/mind-systems/observe-dart) | Dart / Flutter | Dart OTLP/HTTP logging SDK — separate git repo |
| `observe-js/` | [observe-js](https://github.com/mind-systems/observe-js) | TypeScript (isomorphic Node + browser) | JS/TS OTLP/HTTP logging SDK — separate git repo |
| `observe-contract/` | [observe-contract](https://github.com/mind-systems/observe-contract) | Markdown spec + JSON golden fixtures | Frozen cross-platform logging contract — separate git repo; every SDK pins it by git URL at a tag |

**Git operations** (status, diff, commit, branch, push) must be run **inside the respective sub-directory**, not from the root — the root has no visibility into changes inside the SDK repos. Consumers install an SDK by **git URL pinned to a tag**; there is no registry release.

Read a sub-repo's `CLAUDE.md` before working within it — it is the source of truth for that platform's detailed contract (public API, ambient context mechanism, propagation, distribution).

## This repo is the coordinator

The root holds cross-project plans, roadmaps, and AI context (`.ai-factory/`), shared skills (`.claude/`), and two **local-only** pieces that are not shipped to consumers:

- `backend/` — native run config for the off-the-shelf engine: Loki config (OTLP log ingestion, low-cardinality labels, local-FS storage) and Grafana provisioning (Loki datasource, dashboards). No engine code — the binaries come from Homebrew.
- `tools/` — a thin query / MCP wrapper over the Loki HTTP API (LogQL) for common debug slices: since-last-restart, by `trace_id`, by level/project/time window.

The developer browses and selects log lines in Grafana; Claude pulls slices programmatically through `tools/`.

## Hard constraints

- **No Docker.** Docker is not acceptable on the target machine — it must not be required. Anything that only runs via Docker on macOS is disqualified (this is why SigNoz was rejected).
- **Native on macOS.** Backend components must run as native processes (Homebrew binaries / `brew services`).

## Backend decision: don't build the engine

Structured logging, distributed tracing via correlation IDs, and continuous profiling are solved problems, so the storage/query/UI engine is taken off the shelf, not written. What gets built here is a thin SDK and a set of conventions. The real future-proofing is **OTLP at the SDK boundary**: every SDK emits OTLP, the only contract host apps depend on, so the backend behind it stays swappable.

The backend is the **Grafana family**, chosen because it covers the whole roadmap in one place with cross-signal correlation: **Loki** (logs), Tempo (traces), Pyroscope (profiling), Mimir (metrics), visualized in **Grafana**, all OTLP-native, with a mature cloud story (Grafana Cloud ingests OTLP directly). **Now we stand up only Grafana + Loki (logs).** Everything else is deferred — see Growth path.

## The loggers are custom — only the transport moves

Every consuming project already has a deliberately curated, custom logger; the developer writes exactly the lines they care about. **No call sites are rewritten.** In each project the output sink is localized to a single place; that single sink is the only thing that changes, plus a one-time `init` at startup. `trace_id` is attached automatically from ambient context, so individual log statements are never touched.

| Project | Stack | Logger | Single swap point | Target SDK |
|---|---|---|---|---|
| tradeoxy_broker | Swift | custom `actor Logger`, API `log(svc:_:)`, ~168 sites, JSON `{ts,svc,msg}`, **independent of swift-log** | `Logger.append(svc:msg:)` in `Sources/App/Managers/Logger.swift` | `observe-swift` |
| tradeoxy_core | NestJS | Winston (nest-winston), ~112 sites, JSON `{ts,svc,msg}` | `transports` in `src/common/logger/winston.config.ts` | `observe-js` (Node) |
| mind_api | NestJS | Winston, JSON | `WinstonModule` in `src/main.ts` | `observe-js` (Node) |
| mind_mobile | Flutter/Dart | `logPrint`/`log` in `lib/Logger.dart` (`dart:developer.log`) | `lib/Logger.dart` | `observe-dart` |
| mind_web | React/TS | none (bare `console`) | new thin wrapper | `observe-js` (browser) |
| tradeoxy_gui | Angular | none (bare `console`) | new thin wrapper | `observe-js` (browser) |

Isolation across projects is by **resource attributes**: every service sets `project` (`tradeoxy`, `mind`) plus a `service.name`, giving per-project and cross-project views. The shared OTLP contract — public API, resource attributes, the `service.start` restart marker, ambient `trace_id` propagation, low-cardinality label policy, never-break-the-host — is defined in `.ai-factory/ARCHITECTURE.md` and in each sub-repo's `CLAUDE.md`; it is not duplicated here.

## Growth path (deferred, no re-platform)

- **Traces** → add Tempo; SDKs already export spans over the same OTLP endpoint; Grafana gains service graph / pipelines.
- **Profiling / flamegraphs** → add Pyroscope; trace→profile correlation in Grafana.
- **Metrics** → add Mimir.
- **Cloud** → point the OTLP exporter at Grafana Cloud (it ingests OTLP directly). SDKs and call sites do not change.
- **E2E from observed flows** → build on recorded traces via the backend query API.

## Scope routing

- Work scoped to a single SDK → operate **inside** that sub-repo; its plans/roadmaps go to that repo's own `.ai-factory/`.
- Cross-project, backend, tooling, or architectural work → use the **root** `.ai-factory/`.

### `/aif-plan` routing rules

When `/aif-plan` is run, first check the current working directory:

- **CWD is inside a sub-repo** (`observe-swift/`, `observe-dart/`, `observe-js/`) → save the plan to `.ai-factory/plans/` relative to CWD. No detection needed.
- **CWD is the root** → detect the target from the task description:

| Keywords in description | Target | Plan path |
|---|---|---|
| Swift, SwiftPM, `@TaskLocal`, actor Logger, broker | `observe-swift` | `observe-swift/.ai-factory/plans/` |
| Dart, Flutter, `Zone`, `logPrint`, mobile | `observe-dart` | `observe-dart/.ai-factory/plans/` |
| TypeScript, Node, browser, web, `AsyncLocalStorage`, Winston, isomorphic | `observe-js` | `observe-js/.ai-factory/plans/` |
| backend, Loki, Grafana, tools, query, MCP, architecture, roadmap, cross-project, or ambiguous | root | `.ai-factory/plans/` |

If detection is ambiguous, ask which target the plan is for.

### `/aif-roadmap` routing rules

Default: works relative to CWD — no detection needed when already inside a sub-repo. When run from the root, or when the user names a target in the argument:

| Argument prefix | Target |
|---|---|
| `swift` | `observe-swift/.ai-factory/ROADMAP.md` |
| `dart` | `observe-dart/.ai-factory/ROADMAP.md` |
| `js` | `observe-js/.ai-factory/ROADMAP.md` |
| no prefix / `check` / vision text | `.ai-factory/ROADMAP.md` relative to CWD |

Strip the target prefix before processing the remaining argument.

## Architecture

See `.ai-factory/ARCHITECTURE.md` for module boundaries, the OTLP contract, the polyrepo folder structure, and dependency rules.

## Language

All files — docs, plans, config, generated files — are written in **English**, regardless of the conversation language.

## Documentation

| Guide | Path | Description |
|-------|------|-------------|
| Backend | `docs/backend.md` | Loki + Grafana setup, configuration decisions, and operational notes |
| Log destinations | `docs/log-destinations.md` | The `LOG_DESTINATION` switch (`file` / `grafana` / `both`) each project uses to send logs to a local file, the shared Grafana, or both |

## Status

The backend (Loki + Grafana) is up and verified. The scope right now is **logs only**. This file and the linked docs capture the architecture decisions agreed before implementation.
