# Proxy in `make backend-up` — native local run

**Date:** 2026-07-03
**Source:** conversation context

## Key Findings

- `make backend-up` today starts only Loki and Grafana, as plain background processes with PID files in `/tmp` (`Makefile:22-51`) — **not** `brew services`/launchd. It is manual (one command per session/reboot) and idempotent via a `kill -0 $(cat PID)` guard. There is no auto-start at boot for any component; this task matches that model, it does not introduce launchd.
- The proxy is a sibling sub-repo at `$(ROOT)/observe-write-proxy` with its own `Makefile` whose `build` target emits `bin/proxy` (`CGO_ENABLED=0`, static, embeds `web/`). The root repo can build it via `make -C $(ROOT)/observe-write-proxy build`.
- The proxy's canon config defaults already fit the local native stack: listens `:4318`, forwards to `http://localhost:3100` (native Loki), validates admin tokens against `http://localhost:3000` (native Grafana — the `:3030` mapping is Docker-only, irrelevant here). Only `DB_PATH` needs overriding away from the default `./proxy.db` (CWD) to a persistent path.
- Goal is symmetry with the current UX: `make backend-up` brings up all three; the developer never thinks about the proxy, exactly as they don't think about Loki today. Once running, the local write path goes SDK → proxy `:4318` → Loki, so the Bearer-auth path is actually exercised locally instead of bypassed.

## Details

### Makefile changes (root `Makefile`)

Add variables alongside the existing ones (`Makefile:7-13`):

```makefile
PROXY_DIR := $(ROOT)/observe-write-proxy
PROXY_BIN := $(PROXY_DIR)/bin/proxy
PROXY_DATA := $(HOME)/.local/share/observe/proxy.db
PROXY_PID := /tmp/obs-proxy.pid
PROXY_LOG := /tmp/obs-proxy.log
```

**`backend-up`** — after the Grafana block, add a third block that mirrors the loki/grafana pattern:
- Build if the binary is missing: `[ -x $(PROXY_BIN) ] || make -C $(PROXY_DIR) build`.
- Idempotent guard: if `$(PROXY_PID)` exists and the pid is alive, print "already running" and skip.
- Else launch in background with only `DB_PATH` overridden (the rest are canon defaults):
  ```
  DB_PATH=$(PROXY_DATA) $(PROXY_BIN) >$(PROXY_LOG) 2>&1 &
  echo $$! >$(PROXY_PID)
  ```
- Start it **after** Loki (it forwards to Loki). Grafana ordering does not matter — the proxy only calls Grafana per admin request, not at startup.
- Extend the trailing summary echo (`Makefile:48-50`) with a proxy line, e.g.:
  ```
  Proxy    http://localhost:4318        OTLP writes: POST /v1/logs (Bearer)   admin GUI: /
  ```

**`backend-down`** — add a proxy block mirroring `Makefile:54-61`: kill `$(cat $(PROXY_PID))`, `rm -f` the pid file, else print "proxy not running". A `kill` (SIGTERM) triggers the proxy's graceful shutdown (`signal.NotifyContext` + `server.Shutdown`, already implemented).

**`backend-status`** — add a proxy section mirroring `Makefile:64-74`: process-alive check via PID, then `curl -sf http://localhost:4318/healthz` → OK / not responding.

**`backend-clean`** — extend `Makefile:81-84` to also `rm -f $(PROXY_DATA)` (and its `-wal`/`-shm` siblings if present). **Flag the consequence in the echo:** wiping `proxy.db` deletes all minted write tokens, so every SDK using a local token must be re-pointed at a freshly minted one after a clean. This is acceptable for a full reset but must be stated, not silent.

Add `proxy` mentions to the `.PHONY` comment lines only where relevant; no new phony targets are required (all changes live inside existing targets).

### Ordering & failure behavior

- Sequence in `backend-up`: Loki → Grafana → proxy. The proxy tolerates Loki not being ready yet (it only dials Loki on an actual write), so a race at startup is harmless; no readiness-gate/wait loop is needed.
- If the proxy build fails, `backend-up` should surface the error and stop (the `-e` shell flag already does this) rather than half-starting the stack.
- Keep every proxy line consistent with the existing bash-in-make style (`.SHELLFLAGS := -euo pipefail -c`, `$$` for runtime shell vars, PID-file idempotency).

### docs/backend.md

- Add the proxy to the "what `backend-up` starts" description and the after-startup endpoint list: `http://localhost:4318` — OTLP writes via `POST /v1/logs` (Bearer write-token), admin GUI at `/`.
- Note that the token store persists at `~/.local/share/observe/proxy.db` (beside loki/grafana data) and that `make backend-clean` wipes it too, dropping minted tokens.
- One line on how a local SDK points at it: OTLP endpoint `http://localhost:4318/v1/logs` + `Authorization: Bearer <token>` minted in the GUI — cross-reference `docs/log-destinations.md` for the *whether* switch (`LOG_DESTINATION`) vs the *where* (endpoint). Keep prose, no trees.

## Scope

- **In:** root `Makefile` (`backend-up`/`down`/`status`/`clean`), `docs/backend.md`.
- **Out:** `backend/docker-compose.yml` and anything Docker/server (Phase 4 owns that). No launchd/`brew services` boot-persistence — that is a separate, larger "Variant B" enhancement affecting all three components, explicitly deferred. No SDK or consumer-project config (each project wires its own `LOG_DESTINATION`/endpoint).

## Open Questions

None outstanding.

- Boot-persistence (survive reboot without `make backend-up`) via launchd is deliberately **not** in scope — it would need Loki/Grafana on launchd too for consistency and is a future opt-in.
- `DB_PATH` location fixed at `~/.local/share/observe/proxy.db` to sit beside `LOKI_DATA`/`GRAFANA_DATA` (`Makefile:7-8`), so `backend-clean` treats all persisted state uniformly.
