# Integrating an observe-* SDK into a project

> **Read this before integrating any `observe-*` SDK into a consuming project.** It is the distilled playbook from the first three integrations (mind_mobile, mind_api, mind_web) — the principles, the generic task sequence, and the platform gotchas that cost real iteration to find. Your project's specific scope lives in `.ai-factory/notes/0N-integrate-<project>.md`; **this** guide is the cross-cutting how-and-why that every integration repeats.

## The one idea

The integration is a **transport swap, not a feature.** The project keeps its exact log lines and every call site; only *where* the output goes changes, plus a one-time `init` at startup. If a step would require touching call sites or business code, it is out of scope.

## Non-negotiable principles

1. **Zero call-site changes.** A log call is fire-and-forget. You never change how or where logs are called. Only the sink/transport moves.
2. **Zero new log lines.** Route what is already logged. Never add a log line to "make something visible" — not even a "request received" anchor.
3. **One sink.** The swap only works if every log funnels through one facade. The integration's job is to make that true and keep it true (see Phase 1, T2 and T3).
4. **Never break the host.** A failed/slow/unreachable export degrades silently (bounded buffer, drop-oldest) and never throws into the caller or blocks the app/UI. The SDK guarantees this — you do not implement it. There is no file logging from the SDK path.
5. **Don't conflate transport with logging or RPC.** The SDK is purely a transport for existing logs. Wiring it must not couple logging to request/response code.
6. **No global context.** Never wrap the whole app/session in one trace context — that stamps every log with one static `trace_id` (noise). Trace context is per-request, established in infrastructure (Phase 2).
7. **Verify ground-truth; don't trust the brief.** Read the code. Across the first integrations the brief's "single swap point" was sometimes two real paths, and one "network log path" turned out to be dead code. Confirm before scoping.

## The generic task sequence (distilled across three integrations)

### Phase 1 — sink swap (always; delivers availability, restart markers, per-project/service tagging — DoD #1/#2/#4)

- **T1 — SDK lifecycle.** Add the SDK as a dependency **pinned to a tag**. Resolve `LOG_DESTINATION` and the OTLP endpoint from env; the resolver **must never throw** — a bad/absent endpoint degrades silently, never blocks the app. Call the SDK `init` once at the **earliest** startup point, **gated on the destination including `grafana`**, idempotent. Wire flush/shutdown so the buffer drains before the process exits.
- **T2 — route the sink.** Find the project's single logging mechanism and route it through the SDK **additively** (a transport/adapter alongside the existing console/file output). If the project has **more than one** logging path, first **normalize** them to one facade — a one-time mechanical rewrite of those calls (normalization, not call-site coupling) — then route the one facade. Repoint existing logs; add none.
- **T3 — the agent-context logging rule.** Add a short `## Logging` section to the project's agent-context file (`CLAUDE.md`/`AGENTS.md`) so every future agent logs through the one facade and never a raw bypass. This is the **durable guard** that keeps the single-sink invariant true over time — without it, new code reintroduces a bypass that silently never reaches the backend. Full task spec in the Appendix.

### Phase 2 — cross-service trace correlation (optional, droppable; delivers `trace_id` stitching — DoD #3)

- Lives **entirely in existing infrastructure** — the HTTP/gRPC client, a server interceptor, or middleware, configured once. **Never** in `onClick`/handlers/business code (the recurring mistake to refuse).
- **Originator** (the start of a chain — a UI or app): in the **outbound** HTTP/gRPC client, mint a fresh trace per request and `inject` the `traceparent`. The receiver stamps its logs with it.
- **Receiver** (a server): in a server **interceptor** (gRPC) / **middleware** (HTTP), `extract` the inbound `traceparent` and run the handler **inside the SDK ambient context**, so the existing per-request logs inherit the caller's `trace_id`.
- The anchor is always an **existing** log inheriting the trace via ambient context — never a new line.
- **Honest floor.** If the platform's ambient context does not survive the async boundary (e.g. a browser's explicit context across `await`), correlation is **one-way** (receiver only). Ship that floor; never add a log line to force two-way; if even one-way is unwanted, drop Phase 2 and keep Phase 1.

The two halves pair up: an originator's outbound `inject` is meaningless without the receiver's inbound `extract`. Match them per transport (e.g. gRPC inject ↔ gRPC extract, HTTP inject ↔ HTTP extract).

## The destination switch

One env var, `LOG_DESTINATION` ∈ `file | grafana | both`, read once at the sink — see `docs/log-destinations.md`. `file` is the project's existing local output (console / stderr — there is **no** file sink on mobile or browser); `grafana` is OTLP to the shared Loki; `both` runs them in parallel. Default `file` (safe; opt into grafana deliberately). The endpoint and the destination are independent settings: the endpoint is *where*, the destination is *whether*.

## Platform gotchas (the catalog)

- **Env exposure differs.** Node servers read `process.env` directly — if the logger is built before the config layer parses `.env`, only real (shell/Docker) env is visible at that point; match the existing `LOG_LEVEL`/`NODE_ENV` idiom and do **not** add an early `dotenv` (it would retroactively shift other resolutions). Browser bundlers expose only prefixed vars (e.g. Vite `VITE_`). Mobile cannot reach `localhost` from a device/emulator — the endpoint binds to the dev machine's address in the project's build-type config. The endpoint is always a **full** OTLP URL (`…/otlp/v1/logs`), never a bare host.
- **Ambient context — mechanism and reach.** Node `AsyncLocalStorage` and Dart's native `Zone` propagate across `await` (real per-request context). Swift `@TaskLocal` propagates across `await` in the structured task tree but **not** into `Task.detached`. The browser uses a lightweight **explicit** context (deliberately **not** `zone.js`) that holds only within the synchronous stack and the immediately-chained microtask — it does not survive arbitrary `await`, which is why browser correlation is one-way.
- **CORS (browser).** Posting to Loki from a web app is cross-origin. Use the dev server's **proxy** (relative endpoint → same-origin → no preflight, and `sendBeacon` on unload works) rather than enabling CORS on the shared backend.
- **stdout is sacred for stdio servers.** A process that speaks a protocol over stdout (e.g. an MCP server) must never write logs to stdout — keep local echo on **stderr** and wire the SDK's `onError` to stderr or a no-op, never `console.log`. A single stray stdout write corrupts the transport.
- **Flush on shutdown.** Add an idempotent `SIGTERM`/`SIGINT` handler that closes the app **first** (so in-flight requests finish and log), **then** flushes/shuts down the SDK, then exits — not the reverse. Don't enable a framework's global shutdown hooks if that is a behavior change; a localized handler is the zero-side-effect option. On mobile, flush on background/`paused` as well — `detached` is unreliable.
- **JS git-dependency builds.** A TypeScript SDK consumed via a git URL builds `dist/` on install through its `prepare` script. Two things break this silently: (1) **git submodules** — `npm install` never runs `git submodule update --init`, so any build-time file pulled through a submodule is absent and the build fails; inline all such files as plain tracked files in the SDK repo instead. (2) **tag cache** — npm caches git refs by tag; when a consumer bumps the pinned tag, delete the lock entry for the package and re-run `npm install` to pick up the new ref.
- **Dead code.** Confirm the logging paths and the outbound HTTP choke point are actually live; exclude dead or standalone code (CLI scripts, unused clients) from scope.

## Process discipline

1. **Recon first** — read the code; confirm the real sink(s), the single HTTP choke point, and the env idioms. Don't write notes against the brief alone.
2. **Confirm the open decisions with the owner before writing** — env names/defaults, where `init` lives, the flush mechanism, the CORS approach, and whether Phase 2 even applies (does this project call an observed service?).
3. **Decompose two-tier** into the project's own `.ai-factory/ROADMAP.md` + `.ai-factory/notes/NN-*.md` (a contract line per task + a spec note), with an Atomicity Gate and the Phase 1 / Phase 2 split.
4. **Implement Phase 1 first** (zero risk). Phase 2 separately, droppable.
5. **Verify** with the `observe-logs` skill: `since-restart <service> --project <p>` (restart marker), `window … --project <p> --service <s>` (lines land), `trace <id>` (both legs share the trace).
6. **Commit only with the owner's explicit permission.**

## Appendix — T3: the agent-context logging-rule task

A self-contained task for adding the single-sink guard to a project. Hand it to the integrating agent as-is.

> **Task:** add a short logging instruction to this project's agent-context file (`CLAUDE.md`, `AGENTS.md`, or equivalent), so any future agent knows *which* primitive to log with from the first second of a session and never goes hunting for examples.
>
> **Steps:**
> 1. Determine the **one** facade through which this project already logs centrally — the logger wrapper or the framework logger used uniformly. You need only its **name and import path** (how to obtain it in code). Find it by reading how logging is done in several different places and identifying the single dominant mechanism. The import/name/idiom are this project's own (its language/framework dictate them) — do not carry anything over from another project, and do not guess from memory; take exactly what is actually used here.
> 2. Add a short `## Logging` section — literally 1–2 lines — near the **top** of the agent-context file so it is seen first. Its single rule: write **all** logs through that facade, never via raw `console`/`print`/`log`/stdout or any other logger. Name the facade (name + import path) and show the idiom for obtaining the logger. Match the language and style of the neighboring sections.
>
> **Hard constraints:**
> - Touch **only** the agent-context file. Do not edit code, specs, notes, or docs; do not "tidy" existing log calls to match the rule.
> - Do **not** describe which fields/levels/context to pass — the writer just emits a text message; parameters are optional and not their concern.
> - Do **not** describe where/how/why logs travel (transport, backend, format, correlation) — only *which method to log with*.
> - Scope the rule to **application code** (a standalone CLI/seed script using raw output is out of scope).
> - If the project has **no** single facade yet (not implemented, or logging is scattered raw with no common wrapper), write nothing and report back.
