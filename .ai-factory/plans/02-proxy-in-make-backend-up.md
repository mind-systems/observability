# Plan: Proxy in `make backend-up`

## Context
Extend the root `Makefile` so `make backend-up`/`backend-down`/`backend-status`/`backend-clean` also build and run `observe-write-proxy` as a third native background process, bringing the whole local stack (Loki + Grafana + proxy) up with one command so the write-auth path is actually exercised locally.

## Settings
- Testing: no
- Logging: minimal
- Docs: yes (docs/backend.md)

## Tasks

### Phase 1: Makefile wiring

- [x] **Task 1: Add proxy variables**
  Files: `Makefile`
  Alongside the existing variables (`Makefile:4-13`), add:
  `PROXY_DIR := $(ROOT)/observe-write-proxy`, `PROXY_BIN := $(PROXY_DIR)/bin/proxy`, `PROXY_DATA := $(HOME)/.local/share/observe/proxy.db`, `PROXY_PID := /tmp/obs-proxy.pid`, `PROXY_LOG := /tmp/obs-proxy.log`. Keep the existing alignment/style. No new `.PHONY` targets are needed (all changes live inside existing targets); only add a `proxy` mention to the `.PHONY` comment/description lines where relevant.

- [x] **Task 2: Start the proxy in `backend-up`** (depends on Task 1)
  Files: `Makefile`
  After the Grafana block (`Makefile:36-47`) and before the summary echo (`Makefile:48-50`), add a third block mirroring the loki/grafana pattern:
  - **Guard the two new host prerequisites before building** (unlike Loki/Grafana, which auto-`brew install`, the proxy needs its sibling repo cloned and a Go toolchain — neither is auto-provisioned):
    - If `$(PROXY_DIR)` is not a directory, print a clear message (`observe-write-proxy sibling repo not found — clone it beside the root repo`) and stop.
    - If `command -v go` fails, print a clear message (`Go toolchain not found — install Go to build the proxy`) and stop.
    Both must fail with a helpful message, not a raw `make -C … No such file or directory`.
  - Build if the binary is missing: `[ -x $(PROXY_BIN) ] || make -C $(PROXY_DIR) build`. On build failure `backend-up` must surface the error and stop (the `-euo pipefail` shell flag already enforces this) — do not half-start.
  - Idempotent PID-file guard: if `$(PROXY_PID)` exists and `kill -0 "$$(cat $(PROXY_PID))"` succeeds, print `  proxy already running (pid ...)` and skip; else launch.
  - Launch in background with only `DB_PATH` overridden (all other config uses canon defaults `:4318`, `LOKI_URL=http://localhost:3100`, `GRAFANA_URL=http://localhost:3000`):
    `DB_PATH=$(PROXY_DATA) $(PROXY_BIN) >$(PROXY_LOG) 2>&1 &` then `echo $$! >$(PROXY_PID)` and an `→ proxy started` echo with pid + log path.
  - Ensure `~/.local/share/observe` exists so the SQLite `DB_PATH` is writable (extend the existing `mkdir -p` on `Makefile:25` — the parent dir is already created for loki/grafana data, so confirm it covers `PROXY_DATA`'s parent; add if not).
  - Order: proxy block comes **after** the Loki block (it forwards to Loki). No readiness wait loop — the proxy only dials Loki on an actual write, so a startup race is harmless.

- [x] **Task 3: Extend the `backend-up` summary echo** (depends on Task 2)
  Files: `Makefile`
  Add a proxy line to the trailing summary (`Makefile:48-50`), consistent with the existing two lines, e.g.:
  `  Proxy    http://localhost:4318        OTLP writes: POST /v1/logs (Bearer)   admin GUI: /`

- [x] **Task 4: Stop the proxy in `backend-down`** (depends on Task 1)
  Files: `Makefile`
  Add a proxy block mirroring the loki/grafana blocks (`Makefile:54-61`) **faithfully, including the `2>/dev/null … || true` guard**: if `$(PROXY_PID)` exists, `kill "$$(cat $(PROXY_PID))" 2>/dev/null && echo "→ proxy stopped" || true` (SIGTERM triggers the proxy's graceful shutdown; the `|| true` prevents a dead/stale pid from aborting the target under `-euo pipefail` before `rm -f` and before Loki/Grafana are stopped), then `rm -f $(PROXY_PID)`; else print `  proxy not running`.

- [x] **Task 5: Report the proxy in `backend-status`** (depends on Task 1)
  Files: `Makefile`
  Add a `Proxy:` section mirroring the loki/grafana sections (`Makefile:64-74`): process-alive check via `$(PROXY_PID)` + `kill -0`, then `curl -sf http://localhost:4318/healthz >/dev/null` → `  /healthz  OK` / `  /healthz  not responding (starting up?)`; else `  stopped`.

- [x] **Task 6: Wipe the token store in `backend-clean`** (depends on Task 1)
  Files: `Makefile`
  Extend `backend-clean` (`Makefile:81-84`) to also `rm -f $(PROXY_DATA)` and its `$(PROXY_DATA)-wal` / `$(PROXY_DATA)-shm` siblings. Update the echo to **explicitly flag** that removing `proxy.db` deletes all minted write tokens, so every SDK using a local token must be re-pointed at a freshly minted one after a clean — state this, do not do it silently.

### Phase 2: Docs

- [x] **Task 7: Document the proxy in `docs/backend.md` and fix the now-stale prerequisite claims** (depends on Task 3, Task 6)
  Files: `docs/backend.md`, `docs/playbooks/environment-setup.md`
  In `docs/backend.md`:
  - Add the proxy to the running/after-startup descriptions: extend the command list intro and the endpoint table with `http://localhost:4318` — OTLP writes via `POST /v1/logs` (Bearer write-token), admin GUI at `/`.
  - In the Data storage section, note the token store persists at `~/.local/share/observe/proxy.db` (beside loki/grafana data) and that `make backend-clean` wipes it too, dropping minted tokens.
  - Add one line on how a local SDK points at it: OTLP endpoint `http://localhost:4318/v1/logs` + `Authorization: Bearer <token>` minted in the GUI; cross-reference `docs/log-destinations.md` for the `LOG_DESTINATION` *whether* switch vs the *where* (endpoint). Prose only, no directory trees.
  - **Correct the "a new machine needs only `make backend-up`" claim** (`docs/backend.md:14`): the proxy adds two prerequisites Homebrew does not cover — the `observe-write-proxy` sibling repo must be cloned beside the root, and a Go toolchain must be present. State this.
  - **Add a one-line refresh note:** the proxy binary is built once (only when absent), so after pulling proxy source updates, rebuild explicitly with `rm observe-write-proxy/bin/proxy` (or `make -C observe-write-proxy build`) before the next `make backend-up`.
  In `docs/playbooks/environment-setup.md`:
  - **Fix the false line 20** ("the backend itself doesn't need them") — the proxy now requires the `observe-write-proxy` sibling repo cloned alongside the root plus a Go toolchain. Update that statement to reflect the proxy's prerequisites without contradicting the Loki/Grafana auto-install story.

## Commit Plan
- **Commit 1** (after tasks 1-6): "Run the write proxy as a third native process in make backend-up"
- **Commit 2** (after task 7): "Document the native proxy run in backend docs"
