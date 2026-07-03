# Environment setup

> Bring the local observability backend (Loki + Grafana) up on a fresh machine. The backend is **off-the-shelf and native — no Docker**. macOS has a one-command path; other OSes run the same two binaries with the repo's config by hand.

## What you're setting up

The backend is two off-the-shelf binaries, run as native processes:

- **Loki** — log storage + query, HTTP on `:3100` (native OTLP ingest at `/otlp/v1/logs`).
- **Grafana** — UI, HTTP on `:3000`.

This repo ships **only their run-config** (`backend/loki/`, `backend/grafana/`) — the binaries come from your platform's package source. There is no engine code here and no external services. (The SDKs are separate repos; this is just the backend they ship logs to.)

## Prerequisites

- **Loki ≥ 3.0** (native OTLP ingestion landed in 3.0 — earlier versions won't accept `/otlp/v1/logs`) and **Grafana**, installed natively for your OS. No Docker.
  - **macOS** → Homebrew (`brew install loki grafana`) — automated below.
  - **Linux** → your distro's package or the Grafana Labs release binaries.
  - **Windows** → `winget`/`scoop` or the Grafana Labs installers/binaries.
- **The `observe-write-proxy` sibling repo**, cloned beside this root repo, plus a **Go toolchain** — unlike Loki/Grafana, the proxy is not auto-installed via Homebrew; `make backend-up` builds it from source with `go build` on first run. Without both, `make backend-up` stops with a clear error before starting anything.
- **Git** (the SDK repos, and the `observe-write-proxy` repo above, clone alongside the root).

## macOS — one command

1. Clone the workspace (the prompt in the README's **"Cloning the workspace"** section).
2. From the repo root:
   ```
   make backend-up       # installs Loki + Grafana via Homebrew if missing, creates data dirs, starts both
   make backend-verify   # end-to-end check against the contract fixtures
   ```
   `backend-up` is idempotent. `make backend-down` / `backend-status` / `backend-clean` manage it afterwards.

## Other platforms (Linux / Windows) — the same, by hand

The `Makefile` is macOS/Homebrew-specific, but it only does three things you can replicate on any OS:

1. **Install** Loki (≥ 3.0) and Grafana natively (your package manager or the Grafana Labs downloads).
2. **Create the data directory** the Loki config points at — by default `${HOME}/.local/share/observe/loki` (and `…/observe/grafana` for Grafana). The Loki config references `${HOME}` and is expanded at launch via `-config.expand-env=true`, so ensure `HOME` (or its equivalent) is set, or edit the paths in `backend/loki/loki.yaml`.
3. **Run the two binaries with the repo's config** — mirror the Makefile's `backend-up`:
   - **Loki:**
     ```
     loki -config.file=backend/loki/loki.yaml -config.expand-env=true -querier.query-ingesters-within=0
     ```
     (`-querier.query-ingesters-within=0` must be a CLI flag — Loki ignores it from the YAML; see `docs/backend.md`.)
   - **Grafana** — point it at the repo's config + provisioning, and at a writable data dir:
     ```
     GF_PATHS_PROVISIONING=backend/grafana/provisioning \
     GF_PATHS_DATA=<your data dir> \
     grafana server --config=backend/grafana/grafana.ini --homepath=<Grafana's install home>
     ```
     `--homepath` is Grafana's installation home (the directory containing `public/` and `conf/`) — e.g. `/usr/share/grafana` on Linux, the extracted folder on Windows, `$(brew --prefix)/share/grafana` on macOS.

On Windows, `make`/`brew` aren't available — run those two commands directly (PowerShell), or wrap them in a small script / a service. The config files are identical across OSes; only the install + launch mechanics differ.

## After start — endpoints

| Service | URL |
|---|---|
| Grafana | `http://localhost:3000` (login `admin` / `admin`) |
| Loki | `http://localhost:3100` |
| OTLP log ingest | `POST http://localhost:3100/otlp/v1/logs` |

## Verify

- macOS: `make backend-verify`.
- Any OS with `bash` + `curl`: run `backend/verify.sh` — it posts the frozen contract golden fixtures, queries them back via LogQL, and asserts the label set is exactly `project` / `service_name` / `level`.
- Or read logs interactively with the `observe-logs` skill.

## Pointing a project at the backend

A consuming project sets its `LOG_DESTINATION` (`file` / `grafana` / `both`) and its OTLP endpoint — see `docs/log-destinations.md` and `docs/playbooks/sdk-integration.md`. From a device, emulator, or another host, use the backend machine's network address, **not** `localhost` (which won't resolve to your machine from there).

## Data & reset

Data persists under `${HOME}/.local/share/observe/{loki,grafana}` and survives reboots. `make backend-down` stops the processes but keeps the data; `make backend-clean` wipes it for a fresh start (on other OSes, delete those directories). Deeper operational notes and the configuration rationale (label policy, the 3.x query-sharding fix, WAL/disk, historical-data handling) live in `docs/backend.md`.

## Why native, no Docker

A project constraint: Docker is not acceptable on the target machine, so the backend runs as native processes. Loki and Grafana are off-the-shelf and cross-platform, so this works natively on Linux and Windows as well — only the install and launch mechanics differ from the macOS `make` path; the run-config is the same everywhere.
