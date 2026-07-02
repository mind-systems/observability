# Plan Review 3: Server Docker Compose

**Plan:** `.ai-factory/plans/01-server-docker-compose.md`
**Spec note:** `.ai-factory/notes/08-server-docker-compose.md`
**Prior reviews:** `01-server-docker-compose-plan-review-1.md`, `01-server-docker-compose-plan-review-2.md`
**Files Reviewed:** plan v3 + spec note + `backend/loki/loki.yaml`, `backend/grafana/grafana.ini`, `backend/grafana/provisioning/datasources/loki.yaml`, root `Makefile`, `observe-write-proxy/` (`Dockerfile`, `.dockerignore`, `internal/config/config.go`, `internal/store/store.go`, `cmd/proxy/main.go`)

## Code Review Summary

**Files Reviewed:** 10
**Risk Level:** 🟢 Low

## Regression check against plan-review-2

The one remaining substantive finding from review-2 is resolved:

- **Critical #1 (proxy `proxy-data:/data` root-owned → uid 65532 `EACCES` crash-loop):** resolved. Design decision "Proxy env/port wiring…" now explicitly states the blocking precondition, and **Task 7** adds the concrete cross-repo Dockerfile fix (create `/data` in the `golang` builder stage, `COPY --from=build --chown=65532:65532 /data /data` into the distroless final stage). Constraints and Design decisions both flag it as a hard, cross-repo precondition that must land before `docker compose up` can succeed. Verified against `observe-write-proxy/Dockerfile`: final stage is `gcr.io/distroless/static:nonroot`, `USER nonroot:nonroot`, only `COPY --from=build /proxy /proxy` — the fix is correct and necessary.
- **Other (restart policy):** resolved. Task 3 declares `restart: unless-stopped` on every service.
- **Other (healthcheck binary):** carried forward as an explicit confirm-at-pinned-version item in Task 3.
- **Other (Loki 3.x pin):** carried forward and emphasized in Task 6.

All five review-1 findings remain resolved (verified independently below).

## Verification of the corrected mechanism

- **Task 1 (Loki docker config):** `${HOME}` appears in exactly four config lines of `backend/loki/loki.yaml` (24 `path_prefix`, 27 `chunks_directory`, 28 `rules_directory`, 37 `wal.dir`) plus two comment lines. Task 1's "four storage paths" is exact, and dropping `-config.expand-env=true` is safe because the Docker config carries no `${...}` after the rewrite. Default config path `/etc/loki/local-config.yaml` is the grafana/loki image default. Correct.
- **Task 2 + overlay mount (Task 3):** placing `loki.datasource.docker.yaml` *outside* `provisioning/` and overlaying it via a deeper (file-level) bind mount onto `.../datasources/loki.yaml` is sound — Docker applies nested mounts by destination depth, so Grafana sees exactly one Loki datasource at `loki:3100` and no duplicate is auto-loaded. The native file stays byte-for-byte untouched. Correct.
- **Proxy wiring:** re-verified against `internal/config/config.go` — `LOKI_URL` / `GRAFANA_URL` / `DB_PATH` env names and the `:4318` listen default are exact; `LOKI_URL` is the base URL (proxy joins `/otlp/v1/logs`); `GRAFANA_URL=http://grafana:3000` correctly uses the internal port, not the `3030` host mapping. `build: ../observe-write-proxy` resolves correctly relative to `backend/`.
- **Admin credentials:** compose-native `${GRAFANA_ADMIN_PASSWORD:?...}` / `${GRAFANA_ADMIN_USER:-admin}` interpolation is used at the correct layer (Docker Compose supports `:?`/`:-`; Grafana provisioning does not — the exact distinction that broke review-1). `GF_SECURITY_ADMIN_PASSWORD` overrides the `admin/admin` baked into the read-only `grafana.ini` on every boot. Correct.
- **Spec-note smoke check stays valid:** `/healthz` exists in `cmd/proxy/main.go` (`mux.HandleFunc("/healthz", handleHealthz)`), so the note-08 reference `curl localhost:4318/healthz` that Task 5 reconciles is accurate — no correction needed there.

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** ⚠️ WARN (non-blocking, unchanged from review-2). ARCHITECTURE.md still carries hard "no Docker" rules; this plan introduces Docker for the server path. Task 5 correctly keeps the "Server deployment (Docker) — additive, separate from the native macOS path" carve-out as an out-of-scope, note-only *recommendation*, consistent with the plan's `Docs: no` setting. Acceptable; the carve-out should be honored when docs are next in scope.
- **Rules (`.ai-factory/RULES.md`):** not present — skipped.
- **Roadmap (`.ai-factory/ROADMAP.md`):** ✅ Linked (Phase 4 → "Server Docker Compose"). Task 5 reconciles both the ROADMAP line and the spec note with the corrected mechanism, closing review-1's "fix must be mirrored to all three artifacts" requirement.
- **skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`):** not present — no project overrides applied.

## Critical Issues

None. All path-breaking defects from prior rounds are resolved.

## Other Findings (non-blocking)

- **`loki-data` / `grafana-data` volume ownership is asserted, not verified — and it is the same failure class Task 7 exists to fix.** Design decision "Proxy env/port wiring…" states "`loki-data`/`grafana-data` are unaffected — those images chown their data dirs to their runtime users." This is almost certainly true (`grafana/grafana` creates `/var/lib/grafana` owned by uid 472; `grafana/loki` creates and chowns `/loki` to uid 10001), so a fresh named volume inherits the correct owner. But note the asymmetry: this is the *exact* root-owned-fresh-volume mechanism that required a whole cross-repo task (Task 7) for the proxy, and here it is written as settled fact the "write-only, don't run" implementer cannot check. Recommend the deployer confirm at the Task 6-pinned tags that Loki (uid 10001) can write to `/loki` on first `up`; if the pinned Loki image does not pre-create/chown `/loki`, Loki would crash-loop identically to the pre-fix proxy. Low risk, but worth an explicit deploy-time verification line rather than an assertion.
- **`COPY --from=build --chown=65532:65532 /data /data` of an *empty* directory (Task 7).** The chown-on-copy pattern for a distroless data dir is standard and works under BuildKit (`# syntax=docker/dockerfile:1` is present), but copying an empty directory has historically been the fiddly case in Docker's "contents vs. directory" COPY semantics. Since Task 7 gives this as `e.g.` guidance, the implementer should confirm the built image actually contains `/data` owned by `65532:65532` (e.g. via image inspection) before declaring the stack ready. If it proves flaky, `WORKDIR /data` in the builder (which creates the dir) before the `COPY --from` is a robust fallback. Low risk.
- **Healthcheck binary at pinned versions (already flagged in Task 3).** `wget -qO- localhost:3100/ready` and `wget -qO- localhost:3000/api/health` rely on BusyBox `wget` in the Alpine-based grafana/loki and grafana/grafana images; both `grafana` and `proxy` gate on `service_healthy`, so a missing `wget` would silently block startup. The plan already calls for a one-line confirmation at the Task 6 tags — good; just don't drop it.
- **Proxy waits on `grafana: service_healthy` (informational).** The write path does not need Grafana at startup (Grafana is only consulted per-request for admin-token validation), so gating the proxy on Grafana health only slows cold start; it is not incorrect. No change needed.

## Positive Notes

- The `*.docker.yaml` parallel-file strategy plus overlay bind-mount keeps the compose layer purely additive — not a byte of the native Homebrew path changes, and the plan enumerates exactly which native files stay untouched.
- Task 7 turns review-2's abstract "one-line change needed somewhere" into a concrete, correct, distroless-aware Dockerfile edit (numeric uid rather than the name `nonroot`, builder-stage create + `--chown` copy), and correctly scopes the git operation to the separate `observe-write-proxy` repo.
- Interpolation is handled at the right layer throughout — compose `${VAR:?}`/`${VAR:-}` where it is supported, literal URLs in Grafana provisioning where it is not.
- Server-deployment hardening (restart policies, required admin password, gitignored `.env`, reverse-proxy/TLS warning for the `3030` publish, pinned non-`:latest` images with an explicit Loki-3.x constraint) is complete and appropriate for a server target.
- Cross-repo dependency is surfaced in both Design decisions and Constraints, with instruction to flag it in the milestone completion note if Task 7 cannot land in the same pass — the right way to keep "ready to run" honest.

## Verdict

The plan is solid. Every critical and security finding from the two prior rounds is resolved, the corrected mechanism is verified against the actual config, proxy source, and Dockerfile, and the sole cross-repo precondition is now an explicit, correctly-scoped task. The remaining items are deploy-time verification notes (volume ownership, empty-dir COPY, healthcheck binary), not plan defects. Cleared for implementation.

PLAN_REVIEW_PASS
