# mind_mcp — Integrate the observability logging SDK (Node/TS, MCP server)

**Date:** 2026-06-17
**Source:** conversation context

## Context (read this if you have none)

There is a new local observability system — the `observability` project under `~/projects`. Every service ships logs over **OpenTelemetry OTLP** to one shared, native **Grafana + Loki** backend running locally (no Docker): one queryable place, correlated by a shared `trace_id`, with restart markers, browsable in Grafana and queryable programmatically.

This note is the scope/checklist for **mind_mcp**. It is intentionally light on SDK API specifics — the Node/TS SDK is not built yet and this note will be refined once it exists.

## Your SDK

**Node/TS SDK** (built by the observability project — Phase 2; shared with mind_api and tradeoxy_core). Prerequisite: that SDK milestone must be done first.

## Current logging in this project

- Minimal: a single `console.error("mind-mcp server started")` in `src/index.ts`. Node/TS, Model Context Protocol SDK.

**Single swap point: `src/index.ts`** (and any future logging — wrap it in the SDK from the start).

## What you need to do

1. **Add the SDK dependency.**
2. **Initialize once at startup** (in `src/index.ts`, after the server connects): `init(project: "mind", service: "mind_mcp")`. Emits the `service.start` marker and sets resource attributes.
3. **Route logging through the SDK.** Replace the bare `console.error` startup line and any future logs with SDK calls. Low volume — the main value here is the restart marker plus any error/diagnostic lines.
4. **Honor conventions:** levels mapped to SDK levels; only `project`, `service`, `level` as low-cardinality labels.

## Project-specific gotchas — CRITICAL

- **stdout is reserved for the MCP protocol.** Logs must **never** be written to stdout — doing so corrupts the MCP stdio transport and breaks the server. The SDK ships logs over OTLP/HTTP (off-channel), which is exactly what we want; keep any local echo on **stderr** only. Verify nothing in the logging path writes to stdout.

## Out of scope for now

Exact SDK API and endpoint config — deferred until the Node/TS SDK is built.

## Definition of done

- `init(project: "mind", service: "mind_mcp")` at startup; `service.start` visible in Grafana on restart.
- Logs appear in Loki tagged `project=mind`, `service=mind_mcp`.
- stdout remains clean (MCP protocol intact); any local echo is stderr-only.
- No Docker introduced.
