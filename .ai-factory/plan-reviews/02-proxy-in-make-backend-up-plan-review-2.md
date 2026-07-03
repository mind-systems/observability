## Plan Review: Proxy in `make backend-up` (round 2)

**Plan:** `.ai-factory/plans/02-proxy-in-make-backend-up.md`
**Spec:** `.ai-factory/notes/09-proxy-native-run.md`
**Files Reviewed:** plan + `Makefile`, `docs/backend.md`, `docs/playbooks/environment-setup.md`, `.ai-factory/ROADMAP.md`, `.ai-factory/ARCHITECTURE.md` context; `observe-write-proxy` (`Makefile`, `internal/config/config.go`, `cmd/proxy/main.go`, `internal/store/store.go`)
**Risk Level:** 🟢 Low

### Context Gates
- **Architecture (`ARCHITECTURE.md`):** No boundary violation. The plan touches only the root coordinator's `Makefile` and `docs/` — the "local backend run-config and tooling" the root owns. It does not touch `docker-compose.yml` or any SDK, matching the spec's scope fence. **OK.**
- **Roadmap:** Aligns with the Phase 5 milestone "Proxy in `make backend-up`" (`ROADMAP.md:32`). The milestone line prescribes exactly what the plan does — build via `make -C $(ROOT)/observe-write-proxy build`, start after Loki, PID-file idempotency, `DB_PATH=$(HOME)/.local/share/observe/proxy.db`, summary/status/clean updates, `docs/backend.md`. Its `Spec:` points at `.ai-factory/notes/09-proxy-native-run.md`, which exists and matches point-for-point. **OK.**
- **Rules:** No `.ai-factory/RULES.md` and no `aif-review` skill-context present — no project-specific overrides to apply. **OK.**

### Round-1 Issues — all resolved
- **Issue 1 (silent prerequisites contradicting docs):** Task 2 now guards both new host prerequisites before building — `[ -d $(PROXY_DIR) ]` with a "clone observe-write-proxy" message and `command -v go` with an "install Go" message, both failing helpfully instead of a raw `make -C … No such file or directory`. Task 7 now edits **both** `docs/backend.md:14` (the "a new machine needs only `make backend-up`" claim) **and** `docs/playbooks/environment-setup.md:20` (the false "the backend itself doesn't need them" line). Both stale-doc targets verified to exist at the cited lines. **Resolved.**
- **Issue 2 (dropped `|| true` in `backend-down`):** Task 4 now explicitly requires mirroring the loki/grafana lines "faithfully, including the `2>/dev/null … || true` guard," and spells out why (`-euo pipefail` would otherwise abort the target on a stale/dead pid before `rm -f` and before Loki/Grafana are stopped). **Resolved.**
- **Issue 3 (stale binary never rebuilt):** Task 7 now adds a one-line refresh note (`rm observe-write-proxy/bin/proxy` or `make -C … build` before the next `backend-up`). **Resolved.**

### Verified Against the Codebase (assumptions that hold)
- Build: `observe-write-proxy/Makefile` `build` target emits `bin/proxy`, so `PROXY_BIN := $(PROXY_DIR)/bin/proxy` and `[ -x $(PROXY_BIN) ] || make -C $(PROXY_DIR) build` are correct.
- Config defaults (`internal/config/config.go:35-39`): `defaultListen ":4318"`, `defaultLoki "http://localhost:3100"`, `defaultGrafana "http://localhost:3000"`, `defaultDBPath "./proxy.db"`. Overriding only `DB_PATH` is exactly right; the listen-address override env is `PROXY_LISTEN`, deliberately left at default — consistent with the plan.
- `/healthz` is a real liveness handler returning `200 ok` with no upstream dependency (`cmd/proxy/main.go` `handleHealthz`), so the `backend-status` `curl -sf .../healthz` check is valid; the "no readiness wait loop" decision is sound.
- `/v1/logs` is the Bearer-gated write route and `/` serves the ungated embedded admin GUI (`newMux`), so the summary line (`OTLP writes: POST /v1/logs (Bearer) … admin GUI: /`) and the docs endpoint description are accurate.
- SIGTERM → graceful drain is implemented (`signal.NotifyContext` + `srv.Shutdown` with a 10s timeout), so a plain `kill` in `backend-down` is the correct stop signal.
- `store.Open` runs `os.MkdirAll(filepath.Dir(path), 0o755)` itself, and the existing `mkdir -p … $(GRAFANA_DATA)` already creates the shared `~/.local/share/observe` parent — so Task 2's "confirm it covers `PROXY_DATA`'s parent; add if not" resolves to a no-op, exactly as the plan anticipates.
- The store opens with `journal_mode(WAL)` (`store.go` DSN), so `proxy.db-wal` / `proxy.db-shm` sidecar files genuinely exist — Task 6's removal of the `-wal`/`-shm` siblings is warranted, and treating `proxy.db` as a file (not a directory like `LOKI_DATA`/`GRAFANA_DATA`) is correct.

### Minor Observations (non-blocking, no change required)
- **`backend-down` stop order:** the plan leaves the proxy-stop block's position to "mirror the loki/grafana blocks." Stopping the proxy *before* Loki would drain the forward path slightly more cleanly, but since the proxy only dials Loki on an actual write and the drain is local, either order is harmless. Not worth prescribing.
- **`backend-clean` while running:** like the existing loki/grafana clean, this target intentionally does not stop processes. Removing `proxy.db` while the proxy still holds the WAL handle mirrors the existing behavior for loki/grafana data — consistent and acceptable; the plan already insists the destroyed-tokens consequence be printed rather than silent, which is the important operational point.

### Positive Notes
- The prerequisite guards (Task 2) go one step beyond the roadmap line's minimum, turning two would-be hard failures into actionable messages — good defensive UX for the "one command brings up the whole stack" goal.
- Scope discipline is clean: native-only, no `docker-compose.yml` touch, `DB_PATH` deliberately placed beside `loki`/`grafana` data so `backend-clean` stays uniform, no launchd/boot-persistence creep.
- Task 7 correctly widens the docs fix to the playbook, closing the cross-doc consistency gap that round 1 flagged; both stale lines were verified to exist exactly where cited.
- Line references throughout the plan (`Makefile:4-13`, `36-47`, `48-50`, `54-61`, `64-74`, `81-84`; `docs/backend.md:14`; `environment-setup.md:20`) all resolve to the correct anchors in the current tree.

The plan is technically accurate against the proxy code, internally consistent, correctly scoped, and all three round-1 issues are fully addressed. No blocking findings.

PLAN_REVIEW_PASS
