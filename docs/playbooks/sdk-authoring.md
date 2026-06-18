# Authoring a new observe-* SDK

> **Read this before implementing a new platform SDK** in the family (e.g. a Python or Kotlin target). It is the cross-platform playbook distilled from the first three SDKs — the reference `observe-js` plus `observe-dart` and `observe-swift`. It captures the frozen invariants, the generic task sequence every SDK repeats, the watch-points each one paid for, and the decisions to settle per platform. Your job is to map this onto your platform's idioms — never to re-derive it, and never to change the contract to fit your language.

## Read-first map (rehydrate from these, in order)

- **`observe-contract` @ the latest tag (currently `v0.1.2`)** — the frozen wire/API/conventions contract. Your SDK must emit payloads **byte-compatible** with its golden fixtures. This is the law; consume it as a git submodule pinned to that tag.
- **`observe-js`** — the **reference SDK**. Mirror its module boundaries and its conformance + live-smoke harness *shape*; adapt the idioms. When in doubt about structure, copy how observe-js did it.
- **`observe-dart`, `observe-swift`** — two more worked, single-platform examples (non-JS idioms). Their `.ai-factory/notes/` hold the platform-specific watch-points and the per-task spec format to follow.
- **This playbook** — the common vector across all three, below.

## What an observe-* SDK is

A thin, generic library that ships a host's existing logs over **OTLP/HTTP**. Its only knowledge of the outside world is **one OTLP endpoint URL**, supplied by config. It owns transport, the record shape, ambient trace correlation, and graceful degradation. It owns **no** business logic and **no** backend specifics (never "Loki"/"Grafana"). Uniform public API and wire shape across every platform — that uniformity is the whole point.

## Cross-platform invariants (frozen — identical on every platform)

These come straight from the contract; do not let platform idioms drift them.

- **Public API (same vocabulary, platform casing):** `init(project, service[, endpoint, …])`; `log(level, msg, attrs?)`; `startSpan` / `withSpan`; `inject` / `extract` over a **carrier-agnostic** string get/set abstraction (HTTP headers and gRPC metadata are just carriers — no transport dependency).
- **Resource attributes (exact keys):** `project`, `service.name`, `service.instance.id` — the instance id is **fresh per process/app start** (UUIDv4 from the platform's built-in). `init` emits the `service.start` marker.
- **Wire = OTLP/HTTP JSON**, assembled by hand per the contract (no `protoc`): `severityNumber` integer, `traceId`/`spanId` lowercase hex, `timeUnixNano`/`observedTimeUnixNano` decimal **strings**, `AnyValue.intValue` string, camelCase fields. Must equal `golden-record.json` field-for-field.
- **Levels** come from the contract's `levels.json` — the canonical token → `severityNumber`/`severityText` table. Host levels map to the canonical tokens (level-less sources default to `info`).
- **Low-cardinality labels:** only `project` / `service` / `level` are label-worthy; `level` carried as the canonical token; everything else (`trace_id`, ids, free text) stays in the body / attributes.
- **`service.start` marker:** an INFO record with the dedicated `eventName` field **and** an `event.name` attribute (the load-bearing one for "since last restart"), body `service.start` — field-for-field per `fixtures/service-start.json`.
- **Never break the host:** a failed/slow/unreachable export degrades silently (drop / bounded buffer, drop-oldest) and **never throws** into the caller's `log`; no file logging from the SDK path; flush on shutdown.
- **Ambient `trace_id`:** flows through the platform's native context, never threaded through call-site arguments. Spans in v0 = correlation only (id generation + active span + inject/extract); **no** span export, timing, status, or hierarchy beyond `parentSpanId` (those arrive with a tracing backend later).
- **Distribution:** consumed by git URL / submodule pinned to a **tag**; no registry release.

## The generic task sequence (the common vector across observe-js/-dart/-swift)

Decompose **two-tier** (a contract line in the SDK's own `.ai-factory/ROADMAP.md` + a spec note per task) and apply an Atomicity Gate. Roughly 10–11 atomic tasks:

**Foundation**
1. **Package skeleton + build/distribution** — manifest, `core/` (platform-neutral) + thin platform layers, the `observe-contract` git submodule pinned to the contract tag, dependency policy, distribution-by-tag. If the language has a build step, ensure a git install **builds on install** (see watch-points).
2. **Record model + level mapping + resource builder** — typed OTLP/JSON model; the level table sourced from the submodule's `levels.json`; the resource builder (`project`, `service.name`, `service.instance.id`).

**Core**
3. **OTLP/HTTP JSON exporter** — serialize per contract; POST to the endpoint; accept 200/204; never throw; expose it behind a small seam so the host can substitute the transport.
4. **Bounded batching buffer** — queue, flush on size + interval, bounded **drop-oldest**, single in-flight export, `flush()`/`shutdown()`.
5. **Ambient context** — the platform's native mechanism; a unified `getActiveContext` / `runWithContext` interface.
6. **Correlation core** — `trace_id` (16 B → 32 hex) / `span_id` (8 B → 16 hex), lowercase, retry on all-zero; `startSpan`/`withSpan`; logs stamp the active ids. No export.
7. **Carrier-agnostic propagation** — `inject`/`extract` over an abstract carrier; W3C `traceparent`; no transport/gRPC dependency in core.
8. **Public API `init` + `log`** *(reference ergonomics — vet carefully)* — resource + `service.start`; `log` builds a record, stamps the active trace, never throws (incl. pre-`init`); idempotent `init`.

**Adapters**
9. **The platform sink adapter** — the host-integration edge (a logging-framework transport, a sink hook, an actor handoff). Additive, level-less → `info`. This is the only place that touches a framework.

**Verification**
10. **Contract conformance test (offline — required)** — build records through the SDK and assert **field-for-field** equality against `golden-record.json` + `fixtures/service-start.json`, and the level table against `levels.json`.
11. **Live smoke vs local Loki** — `init` + `log` → POST to the local backend → query back; guarded/skippable when the backend is down.

Expect to split `exporter ≠ batcher` and `ambient ≠ correlation` (each half ships independently) — the Atomicity Gate forces this, as it did for js/dart/swift.

## Watch-points (paid for across three SDKs — don't re-pay)

- **WP1 — numbers as strings, compare decoded.** The language's JSON encoder emits by field type, so model `timeUnixNano`/`observedTimeUnixNano` and `AnyValue.intValue` as **strings**, `severityNumber`/`flags` as **integers**. The conformance test must compare **decoded structures**, not raw bytes — encoder key order is not the fixture's.
- **WP2 — ids without extra dependencies.** Generate `trace_id`/`span_id` from the platform's **secure RNG** (lowercase hex, retry all-zero) and the instance id from the platform's **built-in UUID**. Do not pull a crypto or uuid package.
- **WP3 — ambient mechanism + honest boundary.** Pick the platform's native context that propagates across `await`. If the platform has no such mechanism, document the honest boundary (as the browser does — sync stack + immediate microtask only) and accept one-way correlation. **Do not carry over another platform's caveat** — each has its own reach.
- **The note-13 guard — public-surface reachability.** The full public API must be reachable via the **consumer's import path** (the package's public module/barrel), and the conformance + live-smoke tests must import via **that** path, not internals. Then a missing re-export breaks the test build instead of silently shipping. (observe-js once shipped an entry that omitted `init`/`log` because tests imported internals — that is the failure to design out.)
- **Pure core / framework edge.** Keep `core/` free of any framework import; touch the framework only in the sink adapter (T9), so the SDK is usable outside that framework too.
- **Transport-dependency policy.** Aim for **zero runtime deps** where the platform has a usable global HTTP client (JS `fetch`, Swift `URLSession`). Where it doesn't, accept **one** thin cross-platform dep (as observe-dart did with `package:http`) — a conscious, documented departure, behind the exporter seam.
- **Build-on-install for git dependencies.** If the language compiles to an artifact that isn't committed (as TS → `dist/`), a git-URL install must build it on install (npm `prepare` hook), or consumers get an empty package. Source-based ecosystems (Dart `lib/`, Swift `Sources/`) don't have this — verify which yours is. If you re-cut a tag, remember consumers cache git refs by tag.

## Platform decisions to settle with the owner first (the recurring Q-set)

Run recon, then confirm before writing notes:

1. **Core purity** — framework-free `core`, framework only at the sink-adapter edge? (Default: yes.)
2. **HTTP transport** — global client (zero-dep) vs a library; always behind an `Exporter` seam for host substitution.
3. **`levels.json` consumption** — if the language can't import JSON at build time, vendor a typed table in code and have the conformance test assert it equals `contract/levels.json` (the contract stays the source of truth, enforced by the test).
4. **Ambient mechanism** — the platform's native across-`await` context, and its honest boundary.
5. **Packaging / public surface** — single module vs core+public split; if split, ensure the public surface re-exports the full API (the note-13 guard), and tests import the public surface.
6. **Propagation** — carrier-agnostic, no transport/gRPC dependency in core.
7. **Live-smoke required?** — required for the reference; per other SDKs, owner's call (cheap when the backend is up).
8. **Distribution** — the platform's git-dep + tag mechanism; build-on-install if needed.

### Ambient mechanism by platform (map your platform's equivalent)

| Platform | Mechanism | Across `await`? |
|---|---|---|
| Node | `AsyncLocalStorage` | yes |
| Dart / Flutter | native `Zone` | yes |
| Swift | `@TaskLocal` | yes, **except** `Task.detached` |
| Browser | lightweight explicit context (not `zone.js`) | no — sync stack + immediate microtask only (one-way correlation) |
| **A new platform** | find the native across-`await` context (e.g. Python `contextvars`) | document its reach honestly |

## Process

1. Rehydrate from the read-first map; read the contract and the reference SDK.
2. Run recon on the target host(s) and confirm the Q-set with the owner.
3. Two-tier decompose into the new SDK repo's own `.ai-factory/ROADMAP.md` + `notes/`, Atomicity Gate, the Foundation → Core → Adapters → Verification sequence above.
4. Pin the `observe-contract` submodule to the contract tag **first**; build the neutral `core`, then the platform layers and the sink adapter.
5. Conformance (offline, required) + live smoke; cut the SDK's `v0.1.0` tag only when DoD is met (with build-on-install wired if the platform needs it).
6. Commit / push / tag only with the owner's explicit permission.

## The contract is frozen — do not bend it to your platform

If your platform genuinely exposes a gap in the contract (a real cross-platform need, not a convenience), **raise it** — a contract change is a tag bump applied across **all** SDKs in lockstep, and the owner decides. Your SDK **conforms** to the contract; it does not redefine it. A platform difference is expressed as a documented SDK-internal decision (e.g. the ambient mechanism), never as a wire change.
