# Handoff — observe-swift task decomposition

## 1. Frame
Backend + frozen contract (`observe-contract@v0.1.2`) are done; the reference SDK `observe-js` is implemented and reviewed, and `observe-dart` is fully decomposed (two-tier, reviewed) — the next job is to decompose the **`observe-swift` SDK** milestone into two-tier atomic tasks (contract line + spec note each), using `observe-js` (implemented) and `observe-dart` (decomposed) as two worked references. Chat is compacted; knowledge is durable in the files below — rehydrate from them, don't trust memory. You are opened inside `~/projects/observability` (root coordination repo; each SDK + the contract are separate git repos in subfolders).

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `observe-contract/otlp-logging-contract.md` — the frozen wire/API/conventions contract (tag `v0.1.2`) every SDK conforms to. ← lead here.
- `observe-dart/.ai-factory/ROADMAP.md` + `observe-dart/.ai-factory/notes/01..11` — the **closest reference**: a single-platform SDK already decomposed two-tier (no browser layer, native ambient mechanism, vendored level table + test-asserted equality, sink-adapter at the edge). Swift mirrors this shape most directly.
- `observe-js/.ai-factory/ROADMAP.md` + `observe-js/.ai-factory/notes/01..13` — the original reference + the **note-13 institutional guard** (public entry must re-export the full API; tests must import via the consumer path).
- `observe-js/src/core/` — the worked reference implementation of the module boundaries.
- `observe-swift/CLAUDE.md` — the Swift SDK's generic contract doc (Swift specifics: `@TaskLocal`, non-blocking export, flush on shutdown).
- `.ai-factory/notes/06-integrate-tradeoxy-broker.md` — the lone Swift consumer's integration note (the broker's custom `actor Logger`, the single swap point, `LoggerShutdownHandler`).
- `/Users/max/.claude/skills/roadmap-decompose` (skill) — the two-tier procedure; every task = a contract line ending in `` Spec: `…` `` + a manually-written spec note.

### Read on demand
- `observe-contract/golden-record.json`, `observe-contract/fixtures/service-start.json`, `observe-contract/levels.json` — the **oracle** the Swift conformance test must match field-for-field.
- `.ai-factory/ROADMAP.md` (root) — the `observe-swift` milestone line (Phase 2).
- `.ai-factory/ARCHITECTURE.md` — polyrepo structure, OTLP boundary, dependency rules.
- `docs/backend.md` — the running local Loki (`make backend-up`) the live-smoke task targets.
- `.ai-factory/handoffs/02-observe-dart-decomposition.md` — the prior (Dart) decomposition handoff; this one mirrors it.

## 3. Current state

**Done:**
- Backend: Loki 3.7.2 + Grafana, native (no Docker), persistent, `make backend-up && make backend-verify` green.
- Contract frozen: `observe-contract` tags `v0.1.0/v0.1.1/v0.1.2` pushed (v0.1.2 = explicit browser ambient + carrier-agnostic propagation; doc-only, wire + golden fixtures unchanged across all three).
- `observe-js` (reference SDK): implemented (12 tasks + node-entry fix), reviewed, 146/146 tests green. Locally committed; **12 commits unpushed to origin** (owner hasn't authorized push yet).
- `observe-dart`: fully decomposed two-tier (11 tasks + 11 notes), reviewed, note-13 barrel guard woven in. Not committed (untracked).
- Root roadmap: Phase 1 `[x][x]`; `observe-js` milestone `[x]`; `observe-dart` `[ ]` (decomposed, not implemented); `observe-swift` `[ ]` (this task).

**In-flight:**
- **`observe-swift` decomposition — NOT started; this is your task.**

**Uncommitted working-tree state (do not touch from the Swift work):**
- `observe-js`: 12 commits ahead of origin (unpushed) + uncommitted root-roadmap done-marks.
- `observe-dart`: `ROADMAP.md` + `notes/` untracked.
- Root: `.ai-factory/ROADMAP.md` modified + `handoffs/02`, `handoffs/03` untracked.
- `observe-contract`, backend/root commits: clean / pushed.

## 4. Next step
In this (fresh) agent, run `/roadmap-decompose` for **observe-swift**: decompose the root milestone "`observe-swift` SDK" into atomic **two-tier** tasks in `observe-swift/.ai-factory/ROADMAP.md`, each with a spec note in `observe-swift/.ai-factory/notes/NN-slug.md`, mirroring `observe-dart` (closest) and `observe-js`, and pointing the implementer at `observe-js/src/` as the worked reference. **First ask the owner the Swift-specific open questions (§7) and get answers before writing.** Apply the Atomicity Gate to each task. Bake in the three family watch-points and the note-13 guard (§7). Then link the root milestone to the sub-roadmap. Do NOT write SDK code.

## 5. Working discipline
- **Architects, not implementers.** Decompose into roadmap tasks + spec notes; do NOT write SDK code. Findings become tasks, not patches.
- **Ask before decomposing.** The owner answers a short Q-set first (done for js and dart). Offer a recommended default per question.
- **Two-tier is mandatory.** Each task = a contract line (~400–1000 chars naming files/types/guards, ending in `` Spec: `…` ``) + a manually-written spec note (Goal / Design w/ signatures+defaults / Edge cases / Out of scope / Done when). Proportional depth.
- **Discuss before doing; show diffs; commit/push/tag only with explicit owner permission.**
- **All generated files in English; chat in Russian.**
- **Run git inside the sub-repo** (`observe-swift/`), never from the root.

## 6. Error log (lessons from js + dart — do not repeat)
- **observe-js node entry omitted `init`/`log`** from the package entry; tests imported internals and missed it (note 13). **Swift analogue:** if the package splits into multiple modules, the public module must re-export the full API (Swift has no implicit re-export — use `@_exported import` or public typealiases), and conformance/live-smoke must `import Observe` (the consumer module), never an internal core module. Simplest avoidance: keep it one module. Bake this guard into the public-API + conformance tasks.
- **observe-js was first decomposed single-tier** (no `Spec:` tags/notes) — corrected to two-tier; also split two non-atomic tasks via the Atomicity Gate. Apply the gate from the start.
- **An agent once patched `observe-js` code during review** and was corrected ("архитекторы, не имплементеры"). Surface any gap as a task, never fix it in code.
- **Dart number-encoding trap (watch-point #1):** `JSONEncoder` emits the property's type — timestamps/`intValue` must be modeled as `String`, `severityNumber`/`flags` as `Int`, else golden diff fails. Same trap in Swift `Codable`.

## 7. Orientation (traps) + the open questions to ask the owner first
- **Swift ambient = `@TaskLocal`** (contract v0.1.2). Real propagation across `async`/`await` within the structured task tree — like Dart's native `Zone`, NOT like the browser's "sync+microtask" caveat. **Trap:** `@TaskLocal` does NOT propagate into `Task.detached` — document that detached work loses context (use structured child tasks or re-bind).
- **observe-swift consumer = `tradeoxy_broker`** only (Swift 6 + Vapor 4). Its logger is a **custom `actor Logger`**, API `log(svc:_:)`, ~168 sites, JSON `{ts,svc,msg}`, **independent of swift-log** — do NOT assume a swift-log backend swap. Single swap point: `Logger.append(svc:msg:)` in `Sources/App/Managers/Logger.swift`; flush on shutdown via the existing `LoggerShutdownHandler`.
- **The broker is the middle of the chain:** web → broker (`traceparent` HTTP header on the incoming webhook) → core (trace context in outgoing **gRPC metadata**). So Swift needs both `extract` (incoming HTTP) and `inject` (outgoing gRPC) — carrier-agnostic, no gRPC dependency in core.
- **Contract consumed as a git submodule pinned to `v0.1.2`** (uniform across SDKs).

**Ask the owner these before writing (with your recommended default):**
1. **Pure-Swift core vs Vapor/NIO-coupled?** (rec: core = pure Swift + Foundation only, no Vapor/NIO/grpc import; the broker's `actor Logger` sink is the only edge touch — mirrors pure-Dart-core.)
2. **HTTP transport for OTLP export:** Foundation `URLSession` (zero extra dep, works macOS + Linux server) vs `AsyncHTTPClient` (swift-server/NIO, already present in the Vapor broker). (rec: `URLSession` in core for zero-dep + a **pluggable exporter** seam — like observe-js's `exporter?` option — so the broker can inject an AsyncHTTPClient-backed exporter on its event loop if it prefers.)
3. **Module layout / note-13:** single `Observe` module (avoids the re-export trap entirely) vs core+public split with `@_exported import`? (rec: single module; if split, enforce `@_exported import` and tests import `Observe`.)
4. **`levels.json` in Swift** — Swift can't import JSON at compile time. (rec: a vendored typed `let kLevels` table in code (no runtime file I/O), with the conformance test reading `contract/levels.json` and asserting equality — exactly the Dart decision.)
5. **Live-smoke required?** (rec: required, guarded-skip, as a plain XCTest hitting `localhost:3100` via the chosen HTTP client — same as dart.)
6. **gRPC propagation** — carrier-agnostic, no `grpc-swift` dependency in core (broker supplies the metadata carrier at integration)? (rec: yes, mirror js/dart.)

## 8. Domain model spine (don't re-litigate)
- Backend = Grafana/Loki, native no-Docker; cloud later = Grafana Cloud (no compose). [`CLAUDE.md`]
- OTLP is the only contract; the SDK knows ONLY the endpoint URL. [`.ai-factory/ARCHITECTURE.md`]
- Contract frozen at `observe-contract@v0.1.2`; wire + golden fixtures unchanged 0.1.0–0.1.2. [`observe-contract` Changelog]
- Loki labels = `project`/`service_name`/`level` only; `service.name` materializes as `service_name`. [contract + `docs/backend.md`]
- `service.start`: `event.name` attribute is load-bearing for "since last restart"; OTLP `eventName` field also set. [contract + fixture]
- Spans v0 = correlation core only (ids + ambient + inject/extract); no span export until Tempo. [contract + observe-js note 06]

## 9. Hard rules
- Commit / push / tag only with explicit owner permission.
- All generated files in English; chat Russian.
- Memory writes only on an explicit trigger phrase (none).
- Commit messages: short noun phrase / imperative, sentence case, no `type:` prefix; harness appends the `Co-Authored-By` trailer.
- aif scope routing: SDK-scoped roadmap/notes live in that SDK's own `.ai-factory/`; cross-project in root.

## 10. Cross-cutting contracts / invariants checklist (must be identical across SDKs — enforce in the Swift tasks)
- **Public API:** `init(project, service[, endpoint, …])`; `log(level, msg, attrs?)`; `startSpan`/`withSpan`; `inject`/`extract` over a **carrier-agnostic** string get/set abstraction. Swift naming idioms apply (e.g. `withSpan { }`); names stay identical.
- **Resource attrs (exact keys):** `project`, `service.name`, `service.instance.id` (fresh per start — Foundation `UUID()`); emit the `service.start` marker on `init`.
- **Wire = OTLP/HTTP JSON:** `severityNumber` Int, `traceId`/`spanId` **lowercase** hex, `timeUnixNano`/`observedTimeUnixNano` decimal **strings**, `AnyValue.intValue` string, camelCase fields. Must equal `golden-record.json` field-for-field — compare **decoded structures**, not raw bytes (`JSONEncoder` key order isn't the fixture's).
- **Low-cardinality:** only `project`/`service`/`level` are label-worthy; `level` attribute value = canonical token.
- **Levels from the contract** (vendored table, test-asserted equal to `levels.json`); host→canonical map — the broker's level-less `log(svc:_:)` defaults to `info`.
- **Ambient `trace_id` via `@TaskLocal`** — never threaded through call sites; mind `Task.detached` does not inherit it.
- **Never break the host:** export is **non-blocking and never throws back into `append`**; failures degrade silently (drop / bounded buffer, drop-oldest); flush on shutdown via `LoggerShutdownHandler`; no file logging from the SDK path.
- **note-13 guard:** the full public API is reachable from the consumer's `import Observe`; conformance + live-smoke import the public module, not internal targets.
- **Distribution:** consumed via SwiftPM by git URL pinned to an exact tag; contract pulled as a git submodule at `v0.1.2`.

## 11. Per-unit map with watch-points (proposed Swift task set — mirror dart/js; confirm after §7 answers)
- **Package skeleton** — `Package.swift`, library product `Observe`, pure-Swift target (Foundation only), test target, `observe-contract` git submodule `@v0.1.2`, SwiftPM-by-tag distribution. Watch: dependency invariant — core imports no Vapor/NIO/grpc; single module (or `@_exported import` if split).
- **Record model + levels + resource** — `Codable` OTLP/JSON model; vendored `kLevels` table + conformance asserts vs `levels.json`; resource with the 3 keys + `UUID()` instance id. Watch: WP#1 — model timestamps/`intValue` as `String`, `severityNumber`/`flags` as `Int`.
- **OTLP/HTTP JSON exporter** — `URLSession` POST, 200/204, never throws; injectable for tests + pluggable for the broker. Watch: serialize per contract; HTTP-client decision (§7 Q2).
- **Bounded batching buffer** — an `actor` batcher: enqueue (non-blocking), size/interval flush, bounded drop-oldest, single in-flight, `flush()`/`shutdown()`. Watch: actor isolation; must not block the logger actor.
- **Ambient context — `@TaskLocal`** — `@TaskLocal static var current`; `getActiveContext`, `withContext`. Watch: real across-`await` propagation; `Task.detached` loses it — document.
- **Correlation core** — `traceId` (16 B→32 hex) / `spanId` (8 B→16 hex) from `SystemRandomNumberGenerator`, **lowercase**, retry all-zero; `startSpan`/`withSpan` via `@TaskLocal`. Watch: lowercase hex; no Swift-Crypto dep.
- **Carrier-agnostic propagation** — `Carrier` protocol (`get`/`set`) + a dictionary carrier; `inject`/`extract` W3C `traceparent`, parse/validate, ignore malformed. Watch: no grpc-swift dep; broker supplies HTTP-header and gRPC-metadata carriers.
- **Public API `init` + `log`** — `init` builds resource+exporter+batcher, emits `service.start` per fixture (eventName + `event.name` attr, level first), idempotent; `log` stamps active context, never throws, pre-`init` drop. Watch: note-13 — public surface reachable via `import Observe`.
- **`actor Logger` sink adapter** — Swift analogue of Winston/logPrint: integrate behind the broker's `Logger.append(svc:msg:)`; non-blocking hand-off to the batcher; level-less → `info`; flush on shutdown via `LoggerShutdownHandler`; no call-site changes (~168 sites untouched). Watch: never block/throw into `append`; actor reentrancy.
- **Contract conformance test (offline — required)** — XCTest decode-and-compare vs `golden-record.json` + `fixtures/service-start.json`; assert `kLevels` == `levels.json`; assert string/number encodings (WP#1) + `level`-first order; **`import Observe`** (consumer path, note-13); fail if submodule ≠ `v0.1.2`.
- **Live smoke vs local Loki (required, guarded-skip)** — XCTest: `init`+`log` → POST to `localhost:3100/otlp/v1/logs` → LogQL query back; assert labels `project`/`service_name`/`level` + `trace_id` as structured metadata; probe-and-skip when Loki down; `import Observe`.

~10–11 atomic tasks (cf. dart's 11). Apply the Atomicity Gate to each (expect exporter≠batcher, ambient≠correlation split, as in js/dart); single platform → no browser-layer task.
