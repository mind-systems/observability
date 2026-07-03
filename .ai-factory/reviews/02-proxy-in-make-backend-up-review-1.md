# Code Review: Proxy in `make backend-up`

**Plan:** `.ai-factory/plans/02-proxy-in-make-backend-up.md`
**Files changed (code/docs):** `Makefile`, `docs/backend.md`, `docs/playbooks/environment-setup.md` (other staged files are planning artifacts, not reviewed for runtime behavior)
**Risk Level:** 🟡 Low–Medium

## Summary

The Makefile wiring is faithful to the loki/grafana pattern: PID-file idempotency, `2>/dev/null … || true` guards in `backend-down`, `/healthz` liveness check in `backend-status`, `proxy.db` treated as a file with `-wal`/`-shm` siblings in `backend-clean`, `DB_PATH`-only override, and Loki-before-proxy start ordering. Build target, endpoint, and paths all match the verified proxy code. One real bug and a couple of minor points below.

## Findings

### 1. Prerequisite guards run *after* Loki + Grafana are already started — contradicts the doc and half-starts the stack (main finding)

`Makefile:29-53` start Loki and Grafana. Only afterward, at `Makefile:54-58`, do the `[ ! -d $(PROXY_DIR) ]` and `command -v go` guards run and `exit 1`.

But `docs/playbooks/environment-setup.md` (new line) states:

> Without both, `make backend-up` stops with a clear error **before starting anything**.

This is false as implemented. On a machine that has the root repo but not the `observe-write-proxy` sibling repo (it is a separate, `.gitignore`d repo, so a root-only checkout won't have it) or lacks a Go toolchain, `make backend-up`:
1. starts Loki (writes `/tmp/obs-loki.pid`),
2. starts Grafana (writes `/tmp/obs-grafana.pid`),
3. *then* hits the guard and exits 1 — leaving a **half-started stack** with a non-zero exit.

This also mildly regresses the previous behavior where a root-only checkout could bring up Loki+Grafana cleanly (exit 0); now the same checkout hard-fails unless the proxy repo + Go are present.

**Fix (pick one):**
- Preferred: move the two guards (`[ -d $(PROXY_DIR) ]` and `command -v go`) to the **top of the `backend-up` recipe**, above the Loki block, so the promise "stops before starting anything" holds. The proxy *start* still stays after Loki; only the cheap precondition checks move up.
- Or: correct the doc sentence to say the error surfaces after Loki/Grafana are up, and note the stack is left partially running. (Weaker — the half-start remains.)

The spec's intent ("rather than half-starting the stack", `notes/09-proxy-native-run.md:52`) favors the first option.

### 2. `backend-clean` unlinks `proxy.db` while the proxy may still be running (minor)

`backend-clean` (`Makefile:110-114`) `rm -f`s `proxy.db`/`-wal`/`-shm` without stopping the proxy (the target explicitly "does not stop running processes"). A live proxy holds the SQLite handle open; removing the WAL/SHM files out from under an open SQLite connection can corrupt the next checkpoint or cause write errors in the still-running process. Loki/Grafana share the "clean doesn't stop" pattern, but a directory `rm -rf` of their data dir is less immediately hostile to an open handle than deleting a SQLite WAL set. Low impact because the documented recovery is `backend-clean` → `backend-up`, and the sensible sequence is `backend-down` first. Consider one doc line: run `make backend-down` before `make backend-clean` if the proxy is running. Non-blocking.

### 3. Stale-binary refresh is documented but silent at runtime (accepted, noted)

`[ -x $(PROXY_BIN) ] || $(MAKE) -C $(PROXY_DIR) build` (`Makefile:59`) rebuilds only when the binary is absent, so after pulling proxy source updates `backend-up` silently runs the stale binary. This matches the brew "install once" model and is now correctly documented in `docs/backend.md` (`rm observe-write-proxy/bin/proxy` to force a rebuild). No change required.

## Verified OK

- Proxy build path: `$(MAKE) -C $(PROXY_DIR) build` emits `$(PROXY_DIR)/bin/proxy` = `PROXY_BIN`. Correct.
- `DB_PATH=$(PROXY_DATA)` is absolute, so the proxy's CWD is irrelevant; the parent dir `~/.local/share/observe` is created by the existing `mkdir -p $(LOKI_DATA)/…`, and the proxy's `store.Open` also `MkdirAll`s. No missing-dir failure.
- No port conflict: Loki 3100, Grafana 3000, proxy 4318.
- `backend-down` proxy block keeps the `2>/dev/null && echo … || true` guard, so a dead/stale pid won't abort the target under `-euo pipefail`. Correct.
- `backend-status` `curl -sf …/healthz … || echo …` masks curl's exit code; `/healthz` is a dependency-free liveness handler. Correct.
- `.PHONY` trailing `#` comment is valid make; the phony list is unaffected.
- Docs endpoint/paths (`:4318/v1/logs`, Bearer, admin GUI at `/`, `proxy.db` under `~/.local/share/observe/`) match the Makefile and proxy config.

Address finding 1 (and optionally 2) and this is ready.
