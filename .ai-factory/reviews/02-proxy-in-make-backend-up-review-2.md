# Code Review (round 2): Proxy in `make backend-up`

**Plan:** `.ai-factory/plans/02-proxy-in-make-backend-up.md`
**Files changed (code/docs):** `Makefile`, `docs/backend.md`, `docs/playbooks/environment-setup.md` (remaining staged files are planning artifacts)
**Prior review:** `.ai-factory/reviews/02-proxy-in-make-backend-up-review-1.md`
**Risk Level:** 🟢 Low

## Round-1 findings — status

1. **Prereq guards ran after Loki/Grafana started (main finding) — RESOLVED.** The `[ -d $(PROXY_DIR) ]` and `command -v go` guards now sit at the very top of `backend-up` (`Makefile:29-33`), above the loki/grafana install and start blocks. On a root-only checkout (missing sibling repo) or a machine without Go, `backend-up` now exits 1 before starting or installing anything, so the doc claim in `environment-setup.md` ("stops with a clear error before starting anything") is now accurate. Idempotent re-runs still pass the guards cleanly.
2. **`backend-clean` unlinking a live `proxy.db` (minor) — RESOLVED.** `docs/backend.md` now instructs running `make backend-down` first and explains the SQLite WAL/SHM corruption risk.
3. **Silent stale-binary reuse (accepted) — documented** in `docs/backend.md` with the explicit `rm observe-write-proxy/bin/proxy` refresh step. No change required.

## Re-verified

- Guard ordering, PID-file idempotency, `2>/dev/null … || true` in `backend-down`, `/healthz` check in `backend-status`, `DB_PATH`-only override with an absolute path, `proxy.db` treated as a file with `-wal`/`-shm` siblings in `backend-clean`, and Loki-before-proxy start ordering all hold.
- `$(MAKE) -C $(PROXY_DIR) build` (recursive make, not `make`) is correct and emits `$(PROXY_BIN)`.
- No port conflicts (Loki 3100 / Grafana 3000 / proxy 4318); endpoints in docs match the Makefile and proxy config.

## Non-blocking observation

The one-time build step `@[ -x $(PROXY_BIN) ] || $(MAKE) -C $(PROXY_DIR) build` (`Makefile:59`) still runs **after** Loki and Grafana are started. The top-of-recipe guards catch the two common first-run failures (missing repo, missing Go), so this only matters if `go build` itself fails on first run (e.g. a compile error, or a Go version too old) — in that narrow case Loki+Grafana are already up when `backend-up` exits non-zero. The recipe comment says "installs/builds first if needed," so moving this build line up to just after the `go` guard (`Makefile:33`) would both honor that wording and fully close the half-start window. Purely optional — the code is correct as written and the documented failure cases are handled up front.

No bugs, correctness, or security issues found.

REVIEW_PASS
