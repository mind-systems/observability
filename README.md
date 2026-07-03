# observability

A local, no-Docker observability stack and a thin multi-platform SDK that gives every project one shared place to send its logs.

This repository is the coordination layer. It holds the architecture, roadmap, and AI context; each platform SDK lives in its own git repository cloned inside this directory.

## Cloning the workspace

Copy the prompt below and send it to Claude Code in an empty directory. It clones the root and every sub-repository into the right places automatically.

---

```
Clone the observability workspace and all sub-repos (the SDKs and the write-auth proxy) into the correct directory structure.

Run these commands in order:
1. git clone https://github.com/mind-systems/observability.git observability
2. cd observability
3. git clone https://github.com/mind-systems/observe-swift.git observe-swift
4. git clone https://github.com/mind-systems/observe-dart.git observe-dart
5. git clone https://github.com/mind-systems/observe-js.git observe-js
6. git clone https://github.com/mind-systems/observe-write-proxy.git observe-write-proxy

Directory names must be preserved exactly — the root coordination layer references the SDKs by these paths.

After cloning, for each repository (root, observe-swift, observe-dart, observe-js, observe-write-proxy) find the most recently committed branch and switch to it:
- Run `git branch -r --sort=-committerdate` to list remote branches by recency
- Check out the top result (skip HEAD and main/master if a feature branch is more recent)
- If the most recent branch is already main/master, stay on it

After switching branches everywhere, read CLAUDE.md in the root and in each sub-project to understand the project structure and development workflow.
```

---

## Sub-repositories

| Directory | GitHub | Stack | Purpose |
|-----------|--------|-------|---------|
| `observe-swift/` | [observe-swift](https://github.com/mind-systems/observe-swift) | Swift / SwiftPM | Swift OTLP/HTTP logging SDK |
| `observe-dart/` | [observe-dart](https://github.com/mind-systems/observe-dart) | Dart / Flutter | Dart OTLP/HTTP logging SDK |
| `observe-js/` | [observe-js](https://github.com/mind-systems/observe-js) | TypeScript (isomorphic Node + browser) | JS/TS OTLP/HTTP logging SDK |
| `observe-write-proxy/` | [observe-write-proxy](https://github.com/mind-systems/observe-write-proxy) | Go (single static binary) | Bearer-authenticated OTLP write proxy in front of Loki |

Each sub-directory is an independent git repository. Run `git` commands from inside the sub-directory, not from the root.

## The problem

Each service writes its own log files. The broker logs to its files, core logs to its files, the mobile app prints to a console that persists nothing. Debugging anything that crosses a boundary means opening several logs and merging them by hand on timestamps. Restarts leave no trace, so after a fix it's unclear where the new logs begin. The logging in each project is already deliberately curated — the noise problem is solved — but it lives in disconnected places.

## What this does

Every service keeps its own curated logger and ships those same log lines over OpenTelemetry OTLP to one backend running locally. From there:

- **One place to read.** All services' logs land together, browsable in a Grafana UI and queryable programmatically over an HTTP API.
- **Chains reconstruct themselves.** A request carries a `trace_id` from where it starts through every service it touches, so a single action — a tap, a webhook — can be followed end to end without manual stitching.
- **Restarts are visible.** Each service announces itself on startup, so "everything since the last restart" is a precise query.
- **Projects stay separated.** Logs are tagged by project and service, so you can look at one project, one service, or across all of them.

## How it works

The integration is transport-only. A project does not rewrite the places where it logs — it changes only where the log output goes, at the single point in its code where output is produced, and adds a one-time initialization at startup. The correlation id is attached automatically from ambient context, so individual log statements never have to be touched.

The single contract between a project and the backend is OTLP. Everything behind that contract — where logs are stored, how they're queried, the UI — is off-the-shelf and replaceable. The backend is the Grafana family (Loki for logs), run as native macOS processes. This keeps the door open to add traces, profiling, and a cloud deployment later over the same wire, without changing any project's code.

## Log destinations

Each project chooses where its logs go via one environment variable, `LOG_DESTINATION`:

- `file` — a local log file in the project, as before; the observability stack does not see it.
- `grafana` — shipped over OTLP to the shared local Loki, browsable in Grafana.
- `both` — both in parallel.

The switch lives in each project's own logger config and is set per service. See `docs/log-destinations.md`.

## Constraints

- **No Docker.** Every component runs natively. Anything that requires Docker on macOS is disqualified.
- **Native macOS.** The backend runs as Homebrew processes.

## Consumers

Two projects integrate this from the start — **mind** (mobile, API, web) and **tradeoxy** (broker, core, GUI) — but the SDK is project-agnostic and meant to drop into anything. SDKs target Swift, Node/TypeScript, web JavaScript, and Dart/Flutter.

## Run the stack locally

```
make backend-up
```

That single command installs Loki and Grafana via Homebrew (if needed), builds the write proxy from the `observe-write-proxy` sibling repo (a Go toolchain is required for this one), and starts all three as native macOS processes. No Docker.

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | http://localhost:3000 | login: admin / admin |
| Loki    | http://localhost:3100 | internal store; SDKs do not write here directly |
| Write proxy | http://localhost:4318 | SDK log writes go to `POST /v1/logs` with `Authorization: Bearer <token>`; admin GUI at `/` |

A local SDK sends its logs to the proxy at `http://localhost:4318/v1/logs` with a write token minted in the proxy's admin GUI, not to Loki directly. See `docs/backend.md` for the run details and `docs/log-destinations.md` for the `LOG_DESTINATION` switch.

```
make backend-down     # stop all three
make backend-status   # check whether they're running
make backend-verify   # end-to-end test against the contract fixtures
```

## Status

The backend is up: Loki and Grafana, with the write proxy authenticating SDK log writes in front of Loki. The scope right now is **logs only**; the architecture is designed so traces and profiling can be added later without re-platforming. See `CLAUDE.md` for the architecture decisions and `.ai-factory/` for the roadmap, project specification, and per-project integration notes.
