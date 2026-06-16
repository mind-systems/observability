# observability

A local, no-Docker observability stack and a thin multi-platform SDK that gives every project one shared place to send its logs.

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

## Constraints

- **No Docker.** Every component runs natively. Anything that requires Docker on macOS is disqualified.
- **Native macOS.** The backend runs as Homebrew processes.

## Consumers

Two projects integrate this from the start — **mind** (mobile, API, web, MCP) and **tradeoxy** (broker, core, GUI) — but the SDK is project-agnostic and meant to drop into anything. SDKs target Swift, Node/TypeScript, web JavaScript, and Dart/Flutter.

## Status

Greenfield. The scope right now is **logs only**; the architecture is designed so traces and profiling can be added later without re-platforming. See `CLAUDE.md` for the architecture decisions and `.ai-factory/` for the roadmap, project specification, and per-project integration notes.
