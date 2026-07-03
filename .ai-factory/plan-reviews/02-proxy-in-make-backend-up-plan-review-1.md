## Plan Review: Proxy in `make backend-up`

**Plan:** `.ai-factory/plans/02-proxy-in-make-backend-up.md`
**Spec:** `.ai-factory/notes/09-proxy-native-run.md`
**Files Reviewed:** plan + `Makefile`, `docs/backend.md`, `docs/playbooks/environment-setup.md`, `observe-write-proxy` (Makefile, `internal/config/config.go`, `cmd/proxy/main.go`, `internal/store`)
**Risk Level:** 🟡 Medium

### Context Gates
- **Architecture (`ARCHITECTURE.md`):** No boundary violation. The plan touches only the root coordinator's `Makefile` and `docs/` — exactly the "local backend run-config and tooling" the root owns. It does not touch `docker-compose.yml` or any SDK, matching the spec's scope fence. OK.
- **Roadmap:** Aligns cleanly with the Phase 5 milestone "Proxy in `make backend-up`". The milestone's `Spec:` points at `.ai-factory/notes/09-proxy-native-run.md`, which exists and matches the plan point-for-point (variables, ordering Loki→proxy, `DB_PATH`-only override, `backend-clean` token-wipe warning, docs). OK.
- **Rules:** No `.ai-factory/RULES.md` and no `aif-review` skill-context present — no project-specific overrides to apply.

### Verified Against the Codebase (assumptions that hold)
- Proxy build: `make -C $(PROXY_DIR) build` emits `bin/proxy` relative to the sub-repo (`observe-write-proxy/Makefile`), so `PROXY_BIN := $(PROXY_DIR)/bin/proxy` is correct.
- Config defaults match: `ListenAddr :4318`, `LOKI_URL http://localhost:3100`, `GRAFANA_URL http://localhost:3000`, `DB_PATH ./proxy.db` (`internal/config/config.go:36-39`). Overriding only `DB_PATH` is exactly right; the other three canon defaults fit the native stack.
- `/healthz` is a real liveness handler returning `200 ok` with no upstream dependency (`cmd/proxy/main.go:110,121-124`), so the `backend-status` `curl -sf .../healthz` check is valid.
- `/v1/logs` is the write route (`main.go:111`), so the summary line and docs endpoint are correct.
- SIGTERM → graceful drain is implemented (`signal.NotifyContext` + `srv.Shutdown`, `main.go:66-95`), so a plain `kill` in `backend-down` is the right stop signal.

### Issues

**1. `backend-up` gains two silent prerequisites that contradict existing docs (most important)**
The current flow auto-installs Loki/Grafana via Homebrew when missing, so `docs/backend.md` promises "a new machine needs only `make backend-up`" and `docs/playbooks/environment-setup.md:20` states outright: *"the SDK repos clone alongside the root; the backend itself doesn't need them."* This plan breaks both:
- `make -C $(PROXY_DIR) build` requires the **`observe-write-proxy` sibling repo to be cloned**. It is a separate git repo, `.gitignore`d from the root — a fresh checkout of only the root will not have it, and `make -C` fails with a raw "No such file or directory" instead of a helpful message.
- It requires a **Go toolchain**. Unlike Loki/Grafana (auto-`brew install`), the proxy build does not install or check for Go; if Go is absent the build fails hard mid-`backend-up`.

Neither is a code bug, but both undercut the milestone's own stated goal ("one command brings up the whole local stack"). Recommend: (a) guard the build block with `[ -d $(PROXY_DIR) ]` (and ideally `command -v go`) emitting a clear "clone observe-write-proxy / install Go" message before falling over; and (b) **Task 7 must also update `docs/playbooks/environment-setup.md`** (its line 20 is now false) and the backend.md "a new machine needs only `make backend-up`" claim — currently Task 7 only edits `docs/backend.md`, leaving the playbook stale.

**2. Task 4 drops the `|| true` guard the mirrored blocks rely on**
The existing `backend-down` blocks use `kill "$$(cat …)" 2>/dev/null && echo … || true` (`Makefile:55,59`) precisely because `.SHELLFLAGS := -euo pipefail -c` would otherwise abort the whole target if the pid is already dead. Task 4's explicit text is just `kill "$$(cat $(PROXY_PID))" … and echo …` with no `2>/dev/null … || true`. Implemented literally, killing a stale/dead pid aborts `backend-down` before the `rm -f` and before Loki/Grafana are stopped. Keep the guard — mirror the loki/grafana lines faithfully.

**3. Binary is never rebuilt after proxy source changes (minor)**
The `[ -x $(PROXY_BIN) ] || make -C $(PROXY_DIR) build` guard builds only when the binary is *absent*. After pulling proxy updates, `backend-up` keeps running the stale binary silently. This matches the brew "install once" model and is acceptable, but worth a one-line note in docs/backend.md that refreshing the proxy needs an explicit `rm observe-write-proxy/bin/proxy` (or `make -C … build`). Non-blocking.

### Positive Notes
- Task 2's concern about `mkdir -p` covering `PROXY_DATA`'s parent is already doubly safe: `store.Open` does `os.MkdirAll(filepath.Dir(path))` itself (`internal/store`), and the existing `mkdir -p $(LOKI_DATA)/… $(GRAFANA_DATA)` already creates the shared `~/.local/share/observe` parent. The plan flags it as "confirm/add if not," which is the right instinct — no change actually needed, but harmless if added.
- The `backend-clean` task correctly treats `proxy.db` as a file (with `-wal`/`-shm` siblings), not a directory like `LOKI_DATA`/`GRAFANA_DATA`, and rightly insists the destroyed-tokens consequence be printed rather than silent — good operational hygiene.
- No readiness/wait loop for the proxy is correct: `/healthz` is liveness-only and the forwarder dials Loki only on an actual write, so the Loki→proxy startup race is genuinely harmless as the plan states.
- Scope discipline is clean: native-only, no `docker-compose.yml` touch, `DB_PATH` deliberately placed beside `loki`/`grafana` data so `backend-clean` stays uniform.

Overall the plan is technically accurate against the proxy code and internally consistent; the medium risk is entirely about the two undocumented host prerequisites (Issue 1) reaching beyond the Makefile edit, plus the small `|| true` correctness point (Issue 2). Address those and it's ready.
