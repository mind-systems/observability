# Backend bootstrap — native Grafana + Loki (no Docker)

**Date:** 2026-06-17
**Source:** conversation context
**Roadmap task:** Phase 1 → "Backend bootstrap" (`.ai-factory/ROADMAP.md`)
**Run this in a separate agent session** — it is the one above-STOP task that actually installs and runs software (the rest of this project is design/spec). Keeps the main context clean.

## Context (read this if you have none)

`observability` (this repo, under `~/projects`) is a local, **no-Docker** logging stack plus a thin multi-platform SDK. Services ship their logs over **OpenTelemetry OTLP** to one shared backend running **natively on macOS**, so all logs land in one queryable place, correlated by `trace_id`. Right now the scope is **logs only**; the backend is the **Grafana family — Loki for logs, Grafana for viewing**. Traces (Tempo), profiling (Pyroscope), metrics (Mimir), and cloud are deferred and must not be set up here.

This repo is a **polyrepo**: the root is a coordination layer; the SDKs are separate git repos in subfolders (`observe-swift`, `observe-dart`, `observe-js`); the shared wire contract is frozen in `observe-contract` (tag `v0.1.0`). `backend/` and `tools/` live in the **root** and are local-only (not shipped).

## Goal

A new developer on a fresh macOS machine brings the whole local backend up with **one command, run from the repo root**, with no Docker. After this task, the README documents that command.

## Hard constraints (do not violate)

- **No Docker.** Everything runs as native Homebrew processes / `brew services`. If a step seems to need a container, stop and reconsider.
- **Native macOS only.**
- **Low-cardinality Loki labels** are the whole point: labels must be **only `project`, `service`, `level`**. Everything else (`trace_id`, ids, free text) stays in the log body / structured metadata. Verify this, don't assume it.
- The SDK/contract is fixed — **do not change `observe-contract`**. The backend must accept what the contract already defines.

## What to build

All of this lives under the **root** repo (it is gitignored per-SDK but the root tracks `backend/` and the runner).

1. **`backend/loki/` — Loki config.**
   - Native OTLP log ingestion enabled (Loki exposes it at `POST /otlp/v1/logs`). Requires a Loki version with native OTLP support (3.x+) — check `brew info grafana/...` / `loki --version` and pin if needed.
   - **Local filesystem storage** (filesystem object store + TSDB schema) — no external object store, no cloud.
   - **Label policy** via `limits_config.otlp_config`: `ignore_defaults: true` (Loki promotes ~17 resource attributes by default — we don't want that) plus `attributes_config` with `action: index_label` selecting only what maps to `project`, `service`, `level`.
     - `project` ← resource attribute `project`.
     - `service` ← resource attribute `service.name`. **Caveat to resolve:** Loki sanitizes `service.name` to a label like `service_name`; decide whether to rename it to `service` (label mapping) or accept `service_name`, and record the decision. The contract names the logical label `service`.
     - `level` ← the per-record `level` attribute the contract emits (canonical token `info`/`warn`/…). **Caveat to resolve:** Loki may instead auto-derive `detected_level`; confirm which mechanism actually yields a `level` label and use it.

2. **`backend/grafana/` — Grafana provisioning.**
   - A provisioned **Loki datasource** pointing at the local Loki (default `http://localhost:3100`).
   - Optional: one starter dashboard or a saved Explore view. Not required for done.

3. **Root runner — one command.** A `Makefile` (or `justfile`) at the repo root with targets, all runnable from root:
   - `backend-install` — `brew install` Loki + Grafana (idempotent).
   - `backend-up` — start both with our config (`brew services start` or direct binaries with the config files), idempotent.
   - `backend-down` — stop cleanly.
   - `backend-status` — show whether both are up and reachable.
   - `backend-verify` — the end-to-end check below.
   - (`backend-up` may depend on `backend-install` so a brand-new machine needs only `make backend-up`.)

## End-to-end verification (the gate)

Use the **frozen contract fixtures** as the test oracle — this ties contract → backend for free:

1. Bring the backend up.
2. POST the golden payload to Loki's OTLP endpoint:
   ```
   curl -sS -X POST http://localhost:3100/otlp/v1/logs \
     -H 'Content-Type: application/json' \
     --data-binary @observe-contract/golden-record.json
   ```
   Then the same for `observe-contract/fixtures/service-start.json`.
3. Query it back via LogQL and confirm the record is there:
   ```
   curl -sS -G http://localhost:3100/loki/api/v1/query_range \
     --data-urlencode 'query={project="example-project"}'
   ```
4. **Assert the label set** is exactly `project`, `service` (or the agreed `service_name`), `level` — nothing high-cardinality:
   ```
   curl -sS http://localhost:3100/loki/api/v1/labels
   ```
   `trace_id` / `order.id` etc. must **not** appear as labels (they should be queryable as structured metadata instead).
5. **Confirm the restart marker is findable** — a query that isolates `service.start` (via the `event.name` attribute, which the contract makes load-bearing for "since last restart") returns the marker record.
6. Confirm the logs are visible in Grafana via the provisioned Loki datasource.

## README update (part of this task)

After the backend works, add a **"Run the backend locally"** section to the root `README.md`: the one command (`make backend-up`), the default URLs (Grafana `:3000`, Loki `:3100`, OTLP `:3100/otlp/v1/logs`), and a one-liner that an SDK points its OTLP endpoint at that URL. This is the second one-command alongside the existing clone prompt.

## Gotchas

- Verify Loki's installed version actually has native OTLP ingestion before writing config against it.
- The label-policy config is the trickiest part and the easiest to get subtly wrong — the `service.name`→`service` and `level` label questions above are real; resolve them empirically with step 4 and write down what worked.
- Keep `backend-up`/`down` idempotent and safe to re-run.

## Out of scope

- The SDKs themselves (Phase 2) — this is backend only.
- Tempo / Pyroscope / Mimir, and any cloud / Grafana Cloud setup (deferred; cloud = managed Grafana Cloud later, just repointing the OTLP URL — never self-hosted here).
- The query/MCP wrapper (`tools/`, Phase 3). Verification here uses raw `curl` LogQL, not that tool.
- Any change to `observe-contract`.

## Definition of done

- From a clean checkout, **one command from the repo root** brings up Loki + Grafana natively — **no Docker**.
- Loki ingests OTLP/JSON at `/otlp/v1/logs`; both contract fixtures ingest successfully.
- LogQL returns the ingested records; the **label set is exactly `project` / `service` / `level`** (high-cardinality fields are structured metadata, not labels) — verified, with the `service.name`/`level` label decisions recorded.
- The `service.start` marker is queryable (enables "logs since last restart").
- Grafana has the Loki datasource provisioned and logs are browsable.
- `README.md` has a "Run the backend locally" section.
- `backend-down` stops everything cleanly.
