# Handoff — observe-dart task decomposition

## 1. Frame
Backend (Loki+Grafana) and the frozen wire contract (`observe-contract@v0.1.2`) are done, and the **reference SDK `observe-js` is fully implemented and reviewed**; the next job is to decompose the **`observe-dart` SDK** milestone into two-tier atomic tasks (contract line + spec note each), using `observe-js` as the worked reference — chat is compacted, knowledge is durable in the files below; rehydrate from them, don't trust memory. You are opened inside `~/projects/observability` (root coordination repo; each SDK + the contract are separate git repos in subfolders).

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `observe-contract/otlp-logging-contract.md` — the frozen wire/API/conventions contract (tag `v0.1.2`) every SDK conforms to. ← lead here.
- `observe-js/.ai-factory/ROADMAP.md` — the **reference decomposition**: the exact two-tier shape (Foundation/Core/Adapters/Verification, `Spec:` tags) to mirror for Dart, plus the `### Follow-ups` convention.
- `observe-js/.ai-factory/notes/01-package-skeleton.md` … `12-live-smoke-loki.md` — the reference spec notes: copy their depth/structure (Goal / Design w/ signatures+defaults / Edge cases / Out of scope / Done when). Note `13-node-entry-public-api-exports.md` is a follow-up-style note.
- `observe-js/src/core/`, `observe-js/src/node/`, `observe-js/src/browser/` — the **worked reference implementation**; Dart mirrors its module boundaries (wire, levels, encode, resource, exporter, batcher, context, span, propagation, sdk; node winston adapter; browser layer).
- `observe-dart/CLAUDE.md` — the Dart SDK's generic contract doc (Dart-specific: native `Zone`, `logPrint` sink, offline-tolerant batching).
- `.ai-factory/notes/01-integrate-mind-mobile.md` — the lone Dart consumer's integration note (Flutter, `lib/Logger.dart`).
- `/Users/max/.claude/skills/roadmap-decompose` (skill) — the two-tier procedure; every task = contract line ending with `` Spec: `…` `` + a manually-written spec note.

### Read on demand
- `observe-contract/golden-record.json`, `observe-contract/fixtures/service-start.json`, `observe-contract/levels.json` — the **oracle** the Dart conformance test must match field-for-field.
- `.ai-factory/ROADMAP.md` (root) — the `observe-dart` milestone line (Phase 2).
- `.ai-factory/ARCHITECTURE.md` — polyrepo structure, OTLP boundary, dependency rules.
- `docs/backend.md` — the running local Loki (`make backend-up`) the Dart live-smoke task targets.
- `.ai-factory/handoffs/01-observability-sdk-polyrepo-restructure.md` — original project handoff (deep background).

## 3. Current state

**Done:**
- Backend bootstrap: Loki 3.7.2 + Grafana, native (no Docker), persistent data under `${HOME}/.local/share/observe/`; `make backend-up && make backend-verify` green. 3.x single-binary query sharding deadlock fixed in `backend/loki/loki.yaml` (`parallelise_shardable_queries:false`, `split_queries_by_interval:0`, `querier.max_concurrent:2`). Root commits pushed.
- Contract frozen: `observe-contract` tags `v0.1.0`/`v0.1.1`/`v0.1.2` all pushed. `v0.1.2` = browser ambient is explicit (not `zone.js`) + carrier-agnostic propagation (doc-only; wire + golden fixtures identical across all three tags).
- `observe-js` (reference SDK) implemented and pushed (12 tasks), and reviewed this session. Decomposed two-tier (12 tasks + notes 01–12). One **open follow-up** (note 13): the Node package entry omits `init`/`log`/`flush`/`shutdown` — handled by a separate implementer agent, NOT this handoff's job.
- Root roadmap: Phase 1 both `[x]`; `observe-js` milestone still `[ ]` pending follow-up 13.

**In-flight:**
- **`observe-dart` decomposition — NOT started; this is your task.**
- `observe-js` follow-up 13 fix — separate agent; out of scope here.

**Uncommitted working-tree state:**
- In `observe-js` (separate repo): `.ai-factory/ROADMAP.md` modified (added `### Follow-ups` task 13) + `.ai-factory/notes/13-node-entry-public-api-exports.md` untracked — awaiting owner's commit word. Do not touch from the Dart work.
- Root and `observe-contract`: clean / pushed.

## 4. Next step
In this (fresh) agent, run `/roadmap-decompose` for **observe-dart**: decompose the root milestone "`observe-dart` SDK" into atomic **two-tier** tasks written to `observe-dart/.ai-factory/ROADMAP.md`, each with a spec note in `observe-dart/.ai-factory/notes/NN-slug.md`, mirroring the `observe-js` decomposition and pointing the implementer at the `observe-js` source as the worked reference. **First ask the owner the Dart-specific open questions (§7) and get answers before writing** — that is how `observe-js` was decomposed. Then link the root milestone to the sub-repo roadmap (as `observe-js` does). Do NOT write SDK code.

## 5. Working discipline
- **Architects, not implementers.** Decompose into roadmap tasks + spec notes; do NOT write SDK code. (This session the agent wrongly patched `observe-js` code and was corrected — see §6.) Findings become tasks, not patches.
- **Ask before decomposing.** The owner wants Q&A first (he answered a 7-question set before `observe-js` was decomposed). Offer recommended defaults per question so he can accept fast.
- **Two-tier is mandatory.** Every task = a contract line (~400–1000 chars naming files/types/guards, ending in `` Spec: `…` ``) + a manually-written spec note. Proportional depth: full notes (signatures, defaults, edge cases) for design-heavy tasks; short notes for trivial ones the contract+fixtures already pin.
- **Discuss before doing; show diffs; commit/push/tag only with explicit owner permission.**
- **All generated files in English; chat in Russian.**
- **Run git inside the sub-repo**, never from the root.

## 6. Error log
- **Agent patched `observe-js` code during review** (added `init`/`log` re-export to `src/node/index.ts` + a test). WRONG role — owner: "мы архитекторы а не имплементеры." Reverted both files; converted the finding into a two-tier task (`observe-js` roadmap `### Follow-ups` + note 13). Lesson for Dart: surface any gap as a task, never fix it.
- **First `observe-js` decomposition was single-tier** (no `Spec:` tags, no notes). The skill requires two-tier. Corrected: added `Spec:` tags + 12 notes; also **split two non-atomic tasks** (OTLP-exporter ≠ batching; ambient-Node ≠ browser-layer) via the Atomicity Gate. For Dart, apply the gate from the start.
- **`levels.json` self-version must track the contract tag** — bumped `0.1.0→0.1.1→0.1.2` alongside each tag; earlier drift was a recurring nit. (Informational; Dart only consumes the contract, doesn't re-tag it.)
- **Backend: do not downgrade Loki to 2.x** — native OTLP `/otlp/v1/logs` is 3.0+. The query hang was 3.x sharding in single-binary, fixed by config. (Background; affects the live-smoke task's assumptions.)

## 7. Orientation (traps) + the open questions to ask the owner first
- **Dart `Zone` is NATIVE Dart Zone and is KEPT** — do NOT carry over `observe-js`'s "no `zone.js`" decision. Contract v0.1.2 ambient mechanisms: `@TaskLocal` (Swift), `AsyncLocalStorage` (Node), **Dart native `Zone`** (Dart/Flutter — fine), explicit (browser only). The browser caveat is browser-specific; Dart's Zone gives real across-`await` propagation.
- **observe-dart consumer = `mind_mobile` only** (Flutter). `neiry_kit` is NOT a consumer.
- **observe-js is the TEMPLATE**, not a copy source — Dart mirrors its module boundaries and the conformance + live-smoke harness *shape*, in idiomatic Dart.
- **Contract consumed as a git submodule pinned to `v0.1.2`** (uniform across SDKs; no manifest added to the contract repo) — same decision as `observe-js`.

**Ask the owner these before writing (with your recommended default):**
1. **Pure-Dart core vs Flutter-coupled?** (rec: pure-Dart `core`, Flutter touched only at the `logPrint`/sink adapter edge, so the SDK is usable from non-Flutter Dart too.)
2. **HTTP transport:** `package:http` (cross-platform, one dep) vs `dart:io HttpClient` (zero-dep, no web). mind_mobile is mobile-only. (rec: decide explicitly — "zero runtime deps" was an `observe-js` goal but Dart has no global `fetch`.)
3. **How to consume `levels.json` in Dart** — Dart can't import JSON at compile time like TS. Runtime-parse the submodule file vs codegen vs a vendored constant kept in sync by the conformance test. (rec: runtime-parse the submodule JSON in the conformance test as the source of truth; a small typed map in code, asserted equal to it.)
4. **Offline buffer for mobile** — bigger bounded queue? persist across app restarts? (rec: bounded in-memory drop-oldest only for v0; no cross-restart persistence.)
5. **gRPC propagation** — keep carrier-agnostic and defer any gRPC dependency (host passes a `Map`-like carrier at integration)? (rec: yes, mirror `observe-js`.)

## 8. Domain model spine (don't re-litigate)
- Backend = Grafana/Loki, native no-Docker; cloud later = Grafana Cloud (no compose). [`CLAUDE.md`]
- OTLP is the only contract; the SDK knows ONLY the endpoint URL — nothing Loki/Grafana-specific. [`.ai-factory/ARCHITECTURE.md`]
- Contract frozen at `observe-contract@v0.1.2`; wire + golden fixtures unchanged across 0.1.0–0.1.2 (0.1.1/0.1.2 doc-only). [`observe-contract` Changelog]
- Loki label set = `project`/`service_name`/`level` only; `service.name` materializes as `service_name`. [contract "Loki label materialization" + `docs/backend.md`]
- `service.start` marker: the `event.name` attribute is load-bearing for "since last restart"; the OTLP `eventName` field is also set (forward-compat). [contract + `fixtures/service-start.json`]
- Spans v0 = correlation core only (id gen + ambient active span + inject/extract); no span export/timing/status until Tempo. [contract + `observe-js/.ai-factory/notes/06`]

## 9. Hard rules
- Commit / push / tag only with explicit owner permission.
- All generated files in English regardless of chat language.
- Memory writes only on an explicit trigger phrase (none this session).
- Commit messages: short noun phrase / imperative, sentence case, no `type:` prefix, no body for single-concern; harness appends the `Co-Authored-By` trailer.
- aif scope routing: SDK-scoped roadmap/plans/notes live in that SDK's own `.ai-factory/`; cross-project work uses the root.

## 10. Cross-cutting contracts / invariants checklist (must be identical across SDKs — enforce in the Dart tasks)
- **Public API:** `init(project, service[, endpoint, …])`; `log(level, msg, attrs?)`; `startSpan`/`withSpan`; `inject`/`extract` over a **carrier-agnostic** string get/set map (HTTP headers and gRPC metadata are both just carriers). Dart casing idioms apply; names stay identical.
- **Resource attrs (exact keys):** `project`, `service.name`, `service.instance.id` (fresh per start, UUIDv4); emit the `service.start` marker on `init`.
- **Wire = OTLP/HTTP JSON** to the endpoint URL: `severityNumber` integer, `traceId`/`spanId` lowercase hex, `timeUnixNano`/`observedTimeUnixNano` decimal strings, camelCase fields, `AnyValue` shapes. Must equal `golden-record.json` field-for-field.
- **Low-cardinality:** only `project`/`service`/`level` are label-worthy; `level` attribute value = canonical token (`info`/`warn`/…), not the host's raw level.
- **Levels from the contract:** import `levels.json` mapping; host→canonical map (`logPrint`/level-less sinks default to `info`).
- **Ambient `trace_id` via Dart `Zone`** — never threaded through call sites.
- **Never break the host:** export failure degrades silently (drop / bounded buffer, drop-oldest), never throws into `log`; no file logging; offline-tolerant batching.
- **Distribution:** consumed as a pub git dependency pinned to a tag; contract pulled as a git submodule at `v0.1.2`.

## 11. Per-unit map with watch-points (proposed Dart task set — mirror observe-js, adapt to Dart; confirm after §7 answers)
- **Package skeleton** — Dart package (`pubspec.yaml`), `lib/` layout (`core/` pure-Dart, sink adapter at the edge), dev_deps (`test`, lints), contract as git submodule `@v0.1.2`. Watch: keep `core` free of any Flutter import; no dual-build/conditional-exports problem like JS (single platform).
- **Record model + level mapping + resource** — typed records; level table sourced from `contract/levels.json`; resource with the 3 keys + UUIDv4 instance id. Watch: the levels.json consumption decision (§7 Q3).
- **OTLP/HTTP JSON exporter** — serialize per contract; POST to endpoint; accept 200/204; never throw. Watch: HTTP client choice (§7 Q2); serialization must match golden field-for-field.
- **Bounded batching buffer** — queue, size/interval flush, bounded drop-oldest, single in-flight, `flush`/`shutdown`. Watch: mobile offline-tolerance is elevated (§7 Q4).
- **Ambient context (Dart `Zone`)** — `getActiveContext`/`runWithContext` via `Zone.fork`/zone values. Watch: this is the native-Zone unit; real across-`await` propagation (unlike browser).
- **Correlation core** — trace/span id gen (16/8 bytes hex, all-zero retry), active span in zone, `startSpan`/`withSpan`. Watch: secure RNG source in Dart; no span export.
- **Carrier-agnostic propagation** — `inject`/`extract` over a `Map`-like carrier; W3C `traceparent` parse/format, ignore malformed. Watch: keep transport-free; gRPC carrier supplied by host (§7 Q5).
- **Public API `init`/`log`** *(reference ergonomics)* — resource + `service.start` (eventName + `event.name` attr), idempotent `init`, active-context stamping, never-throw, pre-`init` drop. Watch: match the contract vocabulary exactly; service.start must equal the fixture.
- **`logPrint` sink adapter** — wrap the host's `lib/Logger.dart` `logPrint`/`log`; additive, no call-site changes; level-less → `info`. Watch: this is Dart's analogue of the Winston adapter; offline-tolerant; no file logging on Flutter.
- **Contract conformance test (offline — required)** — field-for-field vs `golden-record.json` + `service-start.json`; level table vs `levels.json`.
- **Live smoke vs local Loki (required for this SDK?)** — for `observe-js` this was DoD because it's the reference; for Dart, confirm with owner whether live-smoke is required or optional (rec: optional for non-reference SDKs, but cheap since backend is up).

A typical SDK decomposed into ~10–12 atomic tasks (see `observe-js`). Apply the Atomicity Gate to each; expect to split any "X + Y" task whose halves ship independently.
