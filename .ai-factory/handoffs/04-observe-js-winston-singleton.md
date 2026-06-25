# Handoff — observe-js Winston subpath duplicate-core-singleton bug

## 1. Frame
`observe-js` (the reference SDK) has a packaging bug: the `observe-js/winston` subpath silently drops every `Logger.log(...)` — in `mind_api` only the `service.start` marker reaches Loki. It is already diagnosed and decomposed (note 14); a separate agent will implement the fix, and the owner consults this coordinating agent for reference. Chat is compacted but the knowledge is durable in the files below — rehydrate from them, don't trust memory.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `observe-js/.ai-factory/notes/14-winston-subpath-shared-core-singleton.md` — **the spec for the fix** (root cause + fix options + regression guard). ← lead here.
- `observe-js/.ai-factory/ROADMAP.md` — the `### Follow-ups` task line (the contract for note 14) + `## Baseline decisions` (the `tsup` dual-bundle build that caused this).
- `observe-js/tsup.config.ts` — **where the root cause lives**: two config objects (`browser` entry; `core`+`node`+`winston` entries) built with **no `splitting`**, so each entry inlines its own copy of `core`.
- `observe-js/src/core/sdk.ts` — the module-level singletons that get duplicated: `_initialized`, `_batcher`, `_onError`. `init()` sets them; `log()` reads them.
- `observe-js/src/node/winston.ts` — `ObserveTransport`; its `log(info, cb)` calls core `log(...)`.
- `observe-js/package.json` `exports` — the entries: `"."` → `dist/node.*`, `"./winston"` → `dist/winston.*` (the two separate bundles).

### Read on demand
- `observe-dart/.ai-factory/notes/13-otlp-content-type-charset-fix.md` — the *analogous* transport bug we just fixed in dart; **same class** (a packaging/transport defect invisible to source/mock tests, surfaced only in real consumer integration). Read it for the debugging pattern.
- `observe-js/.ai-factory/notes/13-node-entry-public-api-exports.md` + `test/exports.smoke.test.ts` — the precedent for the right regression guard: assert against the **built `dist/*`**, not source.
- `docs/playbooks/sdk-authoring.md` — the cross-platform SDK invariants & watch-points.
- `docs/backend.md` + the `observe-logs` skill — run/verify against local Loki (`make backend-up` in the workspace root).
- `mind_api` (`~/projects/mind/mind_api`) — where the bug surfaced; its CLAUDE.md "## Logging" + the Winston transports wiring in `src/main.ts`.

## 3. Current state

**Done:**
- `observe-js` fully implemented (12 tasks) + reviewed; node-entry export fix (note 13) landed; `v0.1.0` **tagged + pushed** (re-cut with a `prepare` hook so git installs build `dist/`). Consumed by `mind_api` and `mind_web` (integrations committed + pushed).
- The Winston-drop bug is **diagnosed and decomposed** — note 14 + the roadmap follow-up line.

**In-flight:**
- **Implement note 14** — the Winston duplicate-core-singleton fix. This is the other agent's task.

**Uncommitted working-tree state (observe-js):**
- `M .ai-factory/ROADMAP.md` — the new `### Follow-ups` task line for note 14.
- `?? .ai-factory/notes/14-winston-subpath-shared-core-singleton.md` — the spec.
- **Code NOT yet changed** — the orchestrator implements from the spec (mirror the observe-dart flow: spec in tree, code untouched).

## 4. Next step
Implement note 14 in `observe-js`: make the `node` and `winston` outputs **share one `core` chunk** (tsup `splitting: true`, or externalize `core` from the `winston` entry and import it) so there is **one core singleton per process**. Add the regression guard from the note: a test that imports `init` from the **built** `dist/node.*` and `ObserveTransport` from the **built** `dist/winston.*`, drives a log, and asserts the record reaches a stubbed exporter (proves both bundles share the same `_batcher`). Then re-publish per the owner's branch-vs-tag decision (§5). Do not pre-apply code in this (architect) session — produce/confirm the spec; the implementer applies it.

## 5. Working discipline
- **Architect vs implementer split.** This coordinating agent produces/verifies the spec and reverts any pre-applied code; the orchestrator/implementer writes the fix (exactly how the dart charset fix was handled). The owner comes here for *reference*, not implementation.
- **Test the BUILT artifacts, not source.** Source-based `vitest` runs `core` as a single in-process module, so it never reproduces the dual-bundle duplicate singleton — that is precisely why conformance + live-smoke passed while real `mind_api` dropped logs. The note-13 `exports.smoke` pattern (assert on `dist/*`) is the model; the new guard must cross the `dist/node.*` ↔ `dist/winston.*` boundary.
- **Verify against real Loki / real consumer.** This class of bug only shows end-to-end. After the fix, confirm via `mind_api` (or a built-artifact harness) that a normal `logger.log(...)` line — not just `service.start` — lands in Loki (`observe-logs window --project mind --service mind_api`).
- **Branch-vs-tag is a live decision — confirm with the owner.** Note 14 says "re-cut version + bump pins", but the owner just chose to pin `mind_mobile` to `observe-dart`'s **main** (no tag bump). Ask whether `observe-js` consumers (mind_api, mind_web, tradeoxy_core, tradeoxy_gui) should pin **main** the same way, or get a re-cut tag — do not assume a version bump.
- **No commit / push / tag without explicit owner permission.**
- **All files English; chat Russian.**
- Run git inside the sub-repo (`observe-js/`), not the root.

## 6. Error log (this session — the pattern that hides this class of bug)
- **observe-dart charset 400** (just fixed, note 13 there): `package:http` appended `; charset=utf-8` to a String body; Loki rejects any media-type parameter. Caught only in real `mind_mobile` integration because the `MockClient` unit test bypasses the socket (blind to the wire header) and the live-smoke is `guarded-skip` (skipped → counted as a DoD pass). Byte-body fix; version-independent. **observe-js is NOT affected by charset** — `fetch` sends an explicit `content-type: application/json` verbatim (audited).
- **observe-js node entry omitted `init`/`log`** (note 13 here): tests imported internals, not the built entry, so it shipped; fixed with a built-`dist/*` `exports.smoke` guard.
- **The through-line, and exactly this Winston bug:** *source/mock tests pass while the BUILT/real path fails.* The Winston conformance + live-smoke passed against source (one in-process module → init and the transport shared the singleton) → blind to the dual-bundle duplicate. Only a built-artifact cross-bundle test, or real `mind_api`, catches it. The fix's regression guard must therefore run on `dist/*`.

## 7. Orientation (the trap + the tell)
- **The trap:** in TypeScript bundlers, module-level singletons (`let _batcher` in `core/sdk.ts`) are **per-bundle**, not per-package. Two entry bundles that each inline `core` get two independent singletons. `init` writing one and the Winston transport reading the other is invisible in source (single module) and shows only in the built dual-bundle / real process.
- **The tell:** *only `service.start` reaches Loki, nothing else.* `init()` runs in the node bundle and emits the marker through *its* core copy (which it just initialized); `ObserveTransport.log()` runs through the winston bundle's *separate, uninitialized* core copy → the pre-`init` guard returns early (and treeshaking can fold `log` to `{ return; }`). If you see "marker yes, logs no," suspect duplicate singletons across subpath bundles.

## 8. Domain model spine (don't re-litigate)
- observe-js is **one isomorphic package** (Node + browser) with a platform-neutral `core` + thin `node`/`browser` layers selected by conditional `exports`. The Winston adapter is the `./winston` subpath. [`observe-js/.ai-factory/ROADMAP.md` Baseline]
- The OTLP **payload is correct** — this is a wiring/bundling defect, not a contract or serialization issue. Do not touch the record model, the contract, or `init`/`log` semantics. [note 14 guards]
- `ObserveTransport` must **not** call `init()` — the host calls `init` once at bootstrap; the transport only forwards. [note 09 / note 14]
- Contract is frozen at `observe-contract@v0.1.2`; unaffected here.

## 9. Hard rules
- Commit / push / tag only with explicit owner permission.
- Architect produces specs; implementer/orchestrator writes code. Don't pre-apply the fix in a reference session.
- Regression guards assert on **built `dist/*`**, crossing the relevant bundle boundary.
- All generated files English; chat Russian.

## 10. Cross-cutting invariants (must stay true)
- Public API unchanged: `init` / `log` / `startSpan` / `withSpan` / `inject` / `extract`; `ObserveTransport` at `observe-js/winston`. The fix changes the **build**, not the API.
- `exports` shape unchanged (`"."` → node, `"./winston"` → winston); zero runtime deps in core; dual ESM+CJS preserved.
- One core singleton **per process** after the fix — `init()` in the node entry and `ObserveTransport` in the winston entry must observe the same `_batcher`.
- Never break the host: `log`/transport stay non-throwing and fire-and-forget.
