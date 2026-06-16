# Handoff — observability SDK polyrepo restructure & decomposition plan

## 1. Frame
We designed the `observability` project end to end (local, no-Docker logging stack + a thin multi-platform SDK) and just decided to restructure it from a monorepo into a **root coordination repo with separate SDK sub-repos** (same shape as `tradeoxy/` and `mind/`). The chat is compacted but the knowledge is durable in the files below — rehydrate from them, don't trust memory. You are being opened **inside `~/projects/observability`** so paths are local.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `CLAUDE.md` — the single source of truth: all architecture decisions, the per-project logger swap-point table, hard constraints, growth path. ← lead here.
- `.ai-factory/ARCHITECTURE.md` — the "Contract-Driven Integration (OTLP boundary)" pattern + dependency rules. ⚠️ Its "Folder Structure" section still shows a monorepo (`sdks/swift`, `sdks/node`, …) — that is now OUTDATED by the polyrepo decision; reconcile it.
- `.ai-factory/ROADMAP.md` — milestones. The `---STOP---` line divides **our** work (above: backend bootstrap, OTLP contract, 4 SDKs, query/MCP tool) from **per-project integration** (below: 7 tasks owned by the consuming projects — we do NOT decompose those).
- `/Users/max/projects/tradeoxy/CLAUDE.md` — the structural template we are copying (root coordination layer + sub-repos as separate git repos inside it).

### Read on demand
- `.ai-factory/DESCRIPTION.md` — project spec (stack, constraints, non-functional).
- `.ai-factory/notes/01..07-integrate-*.md` — per-project integration notes (mind_mobile, mind_api, mind_web, mind_mcp, tradeoxy_core, tradeoxy_broker, tradeoxy_gui). Below STOP; do not decompose; refine after SDKs exist.
- `.ai-factory/rules/base.md` — project conventions.
- `.ai-factory/config.yaml` — aif config (lang ui=ru, artifacts=en; git base=main, create_branches=true).
- `README.md` — landing page.

## 3. Current state

**Done:**
- Repo `observability` created, initial commit `09fd3ea`, pushed to `https://github.com/mind-systems/observability.git` (branch `main`).
- All context artifacts written: `CLAUDE.md`, `README.md`, `AGENTS.md` (intentionally a stub pointing to CLAUDE.md), `.gitignore`, `.ai-factory/{config.yaml,DESCRIPTION.md,ARCHITECTURE.md,ROADMAP.md,rules/base.md}`, `.ai-factory/notes/01..07`.
- External skill `grafana/skills@opentelemetry` installed (in gitignored `.agents/`) — scanned clean (0 critical).
- Backend & SDK decisions all settled (see §8).

**In-flight:**
- Restructure to root + SDK sub-repos (NOT started — this is the next step).
- Task decomposition of the above-STOP milestones (NOT started — plan agreed, see §4 and §11).

**Uncommitted working-tree state:**
- This handoff note (`.ai-factory/handoffs/01-...md`) is new/untracked. Nothing else uncommitted.

## 4. Next step
Restructure `observability` into a **root coordination repo with SDK sub-repos** (mirror `tradeoxy/`). Concretely, inside `~/projects/observability`:
1. **Confirm with user first:** the JS layout — ONE isomorphic `observe-js` (Node + web) or TWO repos. This is the one open packaging question (see §7).
2. Create SDK subfolders, each its **own git repo** + matching GitHub repo under the `mind-systems` org: proposed `observe-swift`, `observe-dart`, and `observe-js` (names to confirm). No npm/registry release — consumers install by git URL pinned to a tag.
3. **Update root `CLAUDE.md`** into a coordination-layer doc modeled on `tradeoxy/CLAUDE.md`: repo-structure table (each SDK = separate git repo subfolder), "run git inside the subdir" note, scope routing.
4. **Update root `.gitignore`** to add the SDK subfolder names (the root repo must NOT track nested repos).
5. **Init `CLAUDE.md` inside each SDK subfolder.**
6. **Reconcile `.ai-factory/ARCHITECTURE.md`** "Folder Structure" to the polyrepo layout.

Only AFTER restructure → start decomposition (see §11), beginning with freezing the OTLP contract.

## 5. Working discipline
- **Discuss before doing.** User repeatedly says "давай обсудим" / "ничего не делай пока" before big or structural moves. Confirm direction before writing.
- **Tasks only — don't run/install.** User: "мы только таски можем делать". Do NOT `brew install`/run Grafana/Loki or boot anything yourself; backend bootstrap is a task to be planned, not executed by the agent.
- **Never commit without explicit permission** (global rule). The earlier commit+push was explicitly authorized; do not assume standing authorization for new repos — confirm.
- **All files in English; chat in Russian.**
- **Don't clutter context** — user trimmed the roadmap of deferred phases for this reason.
- **Verify platform/tool claims** (web search) before committing to them — see §6.

## 6. Error log
- **SigNoz recommended, then rejected.** It is Docker-only on macOS (single-binary is Linux-focused) and ClickHouse-based — violates the hard no-Docker + Postgres-preference constraints surfaced later. Lesson: verify native install before recommending.
- **CLAUDE.md wrongly claimed the broker logs via swift-log.** WRONG — the broker has a fully custom `actor Logger` independent of swift-log. Corrected. Do not assume a swift-log backend swap.
- **`tradeoxy_gui` was marked "Planned".** It is ACTIVE (Angular 21, live, real commits). Corrected in both `observability/CLAUDE.md` and `tradeoxy/CLAUDE.md`.
- **Leaned toward OpenObserve, then reversed to Grafana** once the user revealed the profiling/flamegraph + cloud roadmap (OpenObserve's profiling story is weak). Backend = Grafana family.
- **AGENTS.md first written full**, duplicating CLAUDE.md; user wanted it as a bare pointer to CLAUDE.md (the single source of truth). Corrected.
- **Roadmap first had growth Phases 3–5** (Tempo/Pyroscope/Mimir/cloud/e2e); user removed them — the roadmap concerns only observability itself. Rationale for the backend choice still lives in CLAUDE.md's growth path.

## 7. Orientation (traps)
- **`neiry_kit` is NOT a consumer** — it's a Dart BCI plugin, excluded. mind consumers = mind_mobile, mind_api, mind_web, mind_mcp.
- **The two JS frontends share ONE framework-agnostic web SDK** — mind_web (React) and tradeoxy_gui (Angular).
- **`mind_mcp`: stdout is reserved for the MCP protocol** — logs must NEVER go to stdout (breaks the server); ship over OTLP, echo only to stderr.
- **`observability` (the repo) is becoming a ROOT coordination layer**, not a code monorepo — like `tradeoxy/` and `mind/` roots which hold sub-projects as separate git repos.
- **ARCHITECTURE.md folder structure is stale** (assumes monorepo subdirs) — must be reconciled to polyrepo.
- **Open question:** JS = one isomorphic `observe-js` or two repos (node + web)? Unresolved — ask the user.

## 8. Domain model spine (don't re-litigate)
- **Backend = Grafana family, Loki for logs now; native (Homebrew), NO Docker.** [`CLAUDE.md`] SigNoz / OpenObserve / Postgres are decided-against — closed.
- **OTLP at the SDK boundary is the only contract; the backend stays swappable.** [`.ai-factory/ARCHITECTURE.md`]
- **Integration is transport-only:** each project keeps its curated custom logger; only the single output sink changes; no call sites are rewritten. [`CLAUDE.md` swap-point table + notes]
- **Polyrepo, install-by-git-URL, no registry release** (pin to git tags). [this handoff — not yet reflected in the docs]
- **Below-STOP integration tasks are owned by the consuming projects** and are not ours to decompose. [`.ai-factory/ROADMAP.md`]
- **Growth (Tempo traces, Pyroscope profiling, Mimir metrics, cloud) is deferred and intentionally NOT in the roadmap.** [`CLAUDE.md` growth path]

## 9. Hard rules
- Commit/push only with explicit user permission.
- All generated files in English regardless of chat language.
- Memory writes only on an explicit trigger phrase (none used this session).
- Commit messages: short noun phrase / imperative, sentence case, no `type:` prefix, no body for single-concern commits; harness appends the `Co-Authored-By` trailer.
- aif scope routing: with sub-repos, sub-scoped plans/roadmaps live in each SDK repo's own `.ai-factory/`; cross-project work uses the root.

## 10. Cross-cutting contracts / invariants checklist
These MUST be identical across all four SDKs — freeze them in the OTLP contract note before building any SDK:
- **Public API (uniform vocabulary on every platform):** `init(project, service)`; `log(level, msg, attrs?)`; `startSpan` / `withSpan`; context `inject`/`extract` for HTTP `traceparent` and gRPC metadata.
- **Resource attributes on every record:** `project`, `service.name`, `service.instance.id` (fresh per process start); a `service.start` event = the restart marker.
- **Loki labels are low-cardinality — ONLY `project`, `service`, `level`.** `trace_id`, ids, free text go in the log body / structured metadata, never labels.
- **`trace_id` is injected via ambient context, never threaded through call sites:** `@TaskLocal` (Swift), `AsyncLocalStorage` (Node), `Zone` (Dart + web).
- **Wire = OTLP/HTTP.** The SDK knows ONLY the OTLP endpoint URL — nothing backend-specific (never "Loki"/"Grafana").
- **The SDK never breaks the host:** a failed/unreachable export degrades silently (drop/buffer), never throws into the caller's `log()`.
- **Distribution:** consumers add the SDK by git URL pinned to a tag (e.g. `#v0.1.0`); no registry publish.

## 11. Per-unit map with watch-points (above-STOP milestones to decompose)
Agreed decomposition sequence: **freeze the contract → build Node/TS as the reference SDK → then fan out the other three SDKs to parallel agents**, each handed a tight brief = the contract note + the Node reference + that platform's integration note (this is how context transfers without polluting the main chat — do NOT fan out before the contract is frozen).
- **Backend bootstrap** — Grafana + Loki via Homebrew, verify OTLP log ingestion + low-cardinality labels. Watch: this is a *task to run*, not for the agent to execute itself (tasks-only rule).
- **OTLP contract & propagation conventions** — the KEYSTONE design note; everything copies it. Watch: API names + attributes must match §10 exactly; freeze before any SDK.
- **Node/TS SDK** (reference; covers core, mind_api, mcp) — `AsyncLocalStorage` context, Winston transport adapter. Watch: it sets the template the other three follow — get the API surface right here.
- **Swift SDK** (broker) — sink behind the custom `actor Logger.append(svc:msg:)`, `@TaskLocal`, gRPC-metadata propagation. Watch: actor isolation; export must be non-blocking and never throw back into `append`; flush on shutdown via existing `LoggerShutdownHandler`.
- **Web JS SDK** (mind_web React + tradeoxy_gui Angular) — framework-agnostic, `Zone` context, trace origination on user action. Watch: Angular already runs in Zone.js — coordinate so `trace_id` attaches cleanly.
- **Dart/Flutter SDK** (mind_mobile) — `Zone` context, `logPrint` sink adapter. Watch: no file logging on Flutter; must batch + tolerate offline, degrade silently.
- **Query/MCP wrapper** — thin tool over Loki HTTP API (LogQL) for debug slices (since-last-restart, by `trace_id`, by level/project/time window).

A typical SDK decomposes into ~6–9 atomic tasks: package skeleton + manifest → record model + level mapping → OTLP/HTTP exporter + batching → ambient trace context → public `init`/`log` API → framework adapter → propagation inject/extract → install-by-URL (tag) setup → smoke test against local Loki.
