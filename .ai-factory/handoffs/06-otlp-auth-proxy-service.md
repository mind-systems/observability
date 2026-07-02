# Handoff — otlp-auth-proxy-service

## 1. Frame
We need to design and build a thin custom OTLP auth proxy service that sits in front of Loki, validates per-client API tokens, and allows revoking individual client tokens via API/UI without restarting anything — the chat is compacted but decisions and constraints are in files; rehydrate from them, don't trust memory.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `CLAUDE.md` — architecture constraints (no Docker on local dev, native macOS only), SDK family structure, scope routing rules
- `.ai-factory/ROADMAP.md` — current roadmap state; Phases 1-3 done, no Phase 4 yet (server deployment not tasked — blocked on auth design)
- `docs/backend.md` — local backend (Loki + Grafana) operational details, label policy, WAL quirks

### Read on demand
- `observe-js/src/core/sdk.ts`, `observe-dart/lib/src/api.dart`, `observe-swift/Sources/Observe/Public/InitOptions.swift` — all three SDKs already have `headers` param implemented and shipped

## 3. Current state

**Done:**
- All three SDK `headers` params implemented and closed in their respective ROADMAPs:
  - `observe-dart`: `Map<String,String> headers = const {}` in `init()`, passed to `OtlpHttpExporter`
  - `observe-js`: `headers?: Record<string,string>` in `InitOptions`, both Node and browser exporters; caveat: `sendBeacon` path cannot carry custom headers (platform constraint, documented in `src/browser/init.ts:34-36`)
  - `observe-swift`: `headers: [String:String] = [:]` in `InitOptions`, applied in `URLSessionExporter`
- Root ROADMAP rolled back: Alloy Phase 3.5 removed entirely (`git reset --hard 617d0ef`) — repo is clean
- `CLAUDE.md` updated with rule: SDK code changes never go into root ROADMAP
- Research confirmed: no open-source solution exists for per-client token management + UI + no-restart revocation on OTLP ingestion. Only Grafana Enterprise Logs (paid) solves this out of the box.

**In-flight:**
- Auth architecture for server deployment is **undecided** — Alloy was rejected, custom proxy is the agreed direction but not yet designed or tasked
- Phase 4 (Server Deployment) exists in ROADMAP with one open task: Server Docker Compose (`notes/08-server-docker-compose.md`) — Loki + Grafana only, no proxy yet; will need updating once proxy is designed
- `observe-logs` skill auth (`OBS_LOKI_AUTH`) is in skills ROADMAP (`~/projects/skills/.ai-factory/ROADMAP.md`, note `26-observe-logs-remote-auth.md`) — still open, blocked on knowing the final auth scheme (Basic vs Bearer)

**Uncommitted working-tree state:**
- None — repo is clean

## 4. Next step
Design and build the custom OTLP auth proxy service. Concrete scope:

**The service must:**
- Accept OTLP/HTTP writes (`POST /v1/logs`) from SDKs
- Validate `Authorization: Bearer <token>` header against a token store
- Forward valid requests to Loki (`http://localhost:3100/otlp/v1/logs`)
- Reject invalid/missing tokens with 401
- Expose a management API: `POST /tokens` (create, returns token), `DELETE /tokens/:id` (revoke), `GET /tokens` (list) — **no restart needed** to take effect
- Token changes take effect immediately on the next request

**Constraints inherited from architecture:**
- Runs natively on macOS for local dev — no Docker required locally
- Same service runs in Docker on the server (docker-compose adds it alongside Loki, Grafana)
- SDKs send `Authorization: Bearer <token>` via the `headers` param — already supported
- Per-service tokens: each service gets its own token; revoking one has no effect on others

**Where the task goes:** Backend infrastructure → root `.ai-factory/ROADMAP.md`. Do NOT put tasks in SDK repos.

**Decide first with user:**
- Stack (Node/NestJS, Go, Python?) — single binary preferred for macOS native install
- Token store (SQLite is simplest, no external dep)
- API-only vs minimal UI (API-only is fine to start)

## 5. Working discipline
- Confirm plans before implementing — user reviews task list before any code is written
- Show diff / propose changes before editing existing files
- Stop and ask when architecture is ambiguous — don't invent; escalate to user
- Never commit without explicit "commit this" instruction
- SDK code changes go in SDK ROADMAP, not root

## 6. Error log
- **Alloy Phase 3.5 misfire:** Added Alloy as an auth layer before validating that token management requires file edits + service restart. Alloy has no runtime token revocation. Entire phase rolled back with `git reset --hard 617d0ef`. Do not revisit Alloy for auth.
- **Dead references in handoff (self):** First draft referenced `docs/server-deployment.md` and `.ai-factory/notes/09-sdk-remote-endpoint.md` — both were deleted (server-deployment.md described nginx basic auth which is now superseded by the custom proxy plan; note 09 was removed along with it). `notes/08-server-docker-compose.md` exists and is valid.

## 7. Orientation
- **Alloy ≠ token manager:** Alloy routes telemetry data. Token lifecycle requires file edits + restart. Do not revisit.
- **Grafana Service Account tokens** are for reading (dashboards, datasource proxy). They do not authenticate OTLP writes to Loki. Write auth is a completely separate concern.
- **`OBS_LOKI_URL` in `observe-logs` skill:** currently defaults to `http://localhost:3100` (Loki direct). For remote server, will eventually point at Grafana datasource proxy. Tracked in skills ROADMAP — do not conflate with write-path auth.

## 8. Domain model spine
- **Two auth planes:** Write auth (SDK → proxy → Loki) and read auth (agent/human → Grafana) are separate. Write uses Bearer tokens on the custom proxy; read uses Grafana Service Accounts. They never mix. (`CLAUDE.md`, `docs/backend.md`)
- **SDKs own one `init` call per project** — the `headers` param is the only change point. No call sites change. (`CLAUDE.md` consuming projects table)
- **Label policy is frozen:** Only `project`, `service_name`, `level` are Loki index labels. Everything else is structured metadata. The proxy must not add or modify labels. (`docs/backend.md` → Label policy section)
- **`observe-logs` reads, never writes** — skill does `GET` only. Proxy guards write path only. (`~/projects/skills/observe-logs/scripts/query-loki.sh`)

## 9. Hard rules
- No Docker on local macOS — proxy must be installable natively
- Server deployment uses Docker — proxy runs as container in `backend/docker-compose.yml`
- English in all files regardless of conversation language
- Never commit without explicit permission
- SDK code changes → SDK sub-repo ROADMAP; infrastructure → root ROADMAP
