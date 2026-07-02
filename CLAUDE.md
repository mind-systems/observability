# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **local, no-Docker observability stack + a thin multi-platform SDK** for debugging across projects. It replaces per-service file logging (each service writes its own files, manually merged by timestamp) with one place where structured logs — and later traces and profiles — are correlated automatically by `trace_id`.

This root repo is the **coordination layer**. It holds the architecture, roadmap, AI context, and the local backend run-config and tooling. The platform SDKs each live in their own git repository cloned inside this directory. The SDK is the integration surface: drop it into any project on any supported platform and only the existing logger's transport changes. Two consumers from day one — **tradeoxy** and **mind** (both under `~/projects`) — but the SDK is project-agnostic. Local only for now; cloud is a planned later step.

## Repository structure

The SDKs — and the `observe-write-proxy` service — are **separate git repositories** (each has its own `.git`) living inside this root as subdirectories, excluded from the root's tracking via `.gitignore`.

| Directory | GitHub | Stack | Purpose |
|---|---|---|---|
| `observe-swift/` | [observe-swift](https://github.com/mind-systems/observe-swift) | Swift / SwiftPM | Swift OTLP/HTTP logging SDK — separate git repo |
| `observe-dart/` | [observe-dart](https://github.com/mind-systems/observe-dart) | Dart / Flutter | Dart OTLP/HTTP logging SDK — separate git repo |
| `observe-js/` | [observe-js](https://github.com/mind-systems/observe-js) | TypeScript (isomorphic Node + browser) | JS/TS OTLP/HTTP logging SDK — separate git repo |
| `observe-contract/` | [observe-contract](https://github.com/mind-systems/observe-contract) | Markdown spec + JSON golden fixtures | Frozen cross-platform logging contract — separate git repo; every SDK pins it by git URL at a tag |
| `observe-write-proxy/` | [observe-write-proxy](https://github.com/mind-systems/observe-write-proxy) | Go (single static binary) | OTLP write-auth proxy guarding the Loki write path — separate git repo; a **deployed service** (native binary / container), **not** an SDK and not pinned by consumers |

**Git operations** (status, diff, commit, branch, push) must be run **inside the respective sub-directory**, not from the root — the root has no visibility into changes inside the SDK repos. Consumers install an SDK by **git URL pinned to a tag**; there is no registry release.

**Working inside a sub-repo? Read its own `CLAUDE.md` first.** Each SDK is a separate project with its own agent context — the source of truth for that platform's detailed contract (public API, ambient context mechanism, propagation, distribution, build). This root `CLAUDE.md` is the coordination layer; it does **not** replace the sub-repo's. When a task touches one of these directories, read the matching file before doing anything there:

- `observe-swift/CLAUDE.md`
- `observe-dart/CLAUDE.md`
- `observe-js/CLAUDE.md`
- `observe-contract/CLAUDE.md`
- `observe-write-proxy/CLAUDE.md`

## This repo is the coordinator

The root holds cross-project plans, roadmaps, and AI context (`.ai-factory/`), shared skills (`.claude/`), and two **local-only** pieces that are not shipped to consumers:

- `backend/` — run config for the off-the-shelf engine: Loki config (OTLP log ingestion, low-cardinality labels, local-FS storage), Grafana provisioning (Loki datasource, dashboards), and `docker-compose.yml` — the cross-service wiring for the **server** deployment (Loki + Grafana + `observe-write-proxy`). Locally everything runs native (Homebrew binaries / `brew services`); the compose file is server-only. No engine code.

The developer browses and selects log lines in Grafana; Claude pulls slices through the **`observe-logs` skill**, which queries the Loki HTTP API (LogQL) directly for the common debug slices: since-last-restart, by `trace_id`, by level/project/time window.

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

- Work scoped to a single sub-repo (an SDK, the contract, the proxy) → operate **inside** it; its plans/roadmaps go to that repo's own `.ai-factory/`.
- Cross-project, backend, tooling, or architectural work → use the **root** `.ai-factory/`.
- **Sub-repo code changes never go into the root ROADMAP.** A task that touches `observe-*` source belongs in that repo's own `.ai-factory/ROADMAP.md`. The root ROADMAP covers backend infrastructure and tooling only.

### Routing tables (from the root)

| Argument prefix | Target |
|---|---|
| `swift` | `observe-swift/.ai-factory/` |
| `dart` | `observe-dart/.ai-factory/` |
| `js` | `observe-js/.ai-factory/` |
| `contract` | `observe-contract/.ai-factory/` |
| `proxy` | `observe-write-proxy/.ai-factory/` |

**Otherwise detect from the task description:**

| Keywords in description | Target |
|---|---|
| Swift, SwiftPM, `@TaskLocal`, actor Logger, broker | `observe-swift/.ai-factory/` |
| Dart, Flutter, `Zone`, `logPrint`, mobile | `observe-dart/.ai-factory/` |
| TypeScript, Node, browser, web, `AsyncLocalStorage`, Winston, isomorphic | `observe-js/.ai-factory/` |
| contract, golden record, fixtures, severity mapping, label policy | `observe-contract/.ai-factory/` |
| proxy, write auth, write token, admin plane | `observe-write-proxy/.ai-factory/` |
| backend, Loki, Grafana, query, architecture, cross-project | root `.ai-factory/` |

If detection is ambiguous, ask which repo the task is for.

## Architecture

See `.ai-factory/ARCHITECTURE.md` for module boundaries, the OTLP contract, the polyrepo folder structure, and dependency rules.

## Language

All files — docs, plans, config, generated files — are written in **English**, regardless of the conversation language.

## Documentation

| Guide | Path | Description |
|-------|------|-------------|
| Backend | `docs/backend.md` | Loki + Grafana setup, configuration decisions, and operational notes |
| Log destinations | `docs/log-destinations.md` | The `LOG_DESTINATION` switch (`file` / `grafana` / `both`) each project uses to send logs to a local file, the shared Grafana, or both |

## Read this first — start here, then your playbook

- **Fresh machine — set up the backend?** Read **`docs/playbooks/environment-setup.md`** — Loki + Grafana as native processes (no Docker): one command on macOS (`make backend-up`), the same two binaries run by hand on Linux/Windows.
- **Integrating an `observe-*` SDK into a consuming project?** Read **`docs/playbooks/sdk-integration.md`** — the distilled playbook from the first three integrations (mind_mobile, mind_api, mind_web): the non-negotiable principles (transport swap only, zero new log lines, zero call-site changes), the generic **Phase 1 (sink swap) / Phase 2 (trace correlation)** task sequence, and the platform gotchas. Each project's specific scope lives in its `.ai-factory/notes/0N-integrate-*.md`.
- **Implementing a new platform SDK (a new `observe-*` target, e.g. Python)?** Read **`docs/playbooks/sdk-authoring.md`** — the cross-platform invariants, the generic Foundation→Core→Adapters→Verification task sequence, and the watch-points distilled from the existing SDKs. The frozen contract (`observe-contract`) and the reference SDK (`observe-js`) are its anchors.

Both are the cross-cutting how-and-why that each effort otherwise rediscovers the hard way.

## Status

The backend (Loki + Grafana) is up and verified. The SDKs are built and integrated into the first consumers (see the playbooks). The scope right now is **logs only**.
