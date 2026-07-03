SHELL       := /bin/bash
.SHELLFLAGS := -euo pipefail -c

ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BREW  := $(shell brew --prefix)

LOKI_DATA    := $(HOME)/.local/share/observe/loki
GRAFANA_DATA := $(HOME)/.local/share/observe/grafana

LOKI_PID    := /tmp/obs-loki.pid
GRAFANA_PID := /tmp/obs-grafana.pid
LOKI_LOG    := /tmp/obs-loki.log
GRAFANA_LOG := /tmp/obs-grafana.log

PROXY_DIR  := $(ROOT)/observe-write-proxy
PROXY_BIN  := $(PROXY_DIR)/bin/proxy
PROXY_DATA := $(HOME)/.local/share/observe/proxy.db
PROXY_PID  := /tmp/obs-proxy.pid
PROXY_LOG  := /tmp/obs-proxy.log

.PHONY: backend-install backend-up backend-down backend-status backend-verify backend-clean # up/down/status/clean also cover the write proxy

## Install Loki and Grafana via Homebrew (idempotent).
backend-install:
	brew install loki grafana

## Start Loki, Grafana, and the write proxy with the repo's config (installs/builds first if needed).
backend-up:
	@if [ ! -d $(PROXY_DIR) ]; then \
		echo "observe-write-proxy sibling repo not found — clone it beside the root repo" >&2; \
		exit 1; \
	fi
	@command -v go >/dev/null 2>&1 || { echo "Go toolchain not found — install Go to build the proxy" >&2; exit 1; }
	@command -v loki    >/dev/null 2>&1 || brew install loki
	@command -v grafana >/dev/null 2>&1 || brew install grafana
	@mkdir -p $(LOKI_DATA)/chunks $(LOKI_DATA)/rules $(LOKI_DATA)/wal $(GRAFANA_DATA)
	@if [ -f $(LOKI_PID) ] && kill -0 "$$(cat $(LOKI_PID))" 2>/dev/null; then \
		echo "  loki already running (pid $$(cat $(LOKI_PID)))"; \
	else \
		loki -config.file=$(ROOT)/backend/loki/loki.yaml \
			-config.expand-env=true \
			-querier.query-ingesters-within=0 \
			>$(LOKI_LOG) 2>&1 & \
		echo $$! >$(LOKI_PID); \
		echo "→ loki started (pid $$(cat $(LOKI_PID)))  logs: $(LOKI_LOG)"; \
	fi
	@if [ -f $(GRAFANA_PID) ] && kill -0 "$$(cat $(GRAFANA_PID))" 2>/dev/null; then \
		echo "  grafana already running (pid $$(cat $(GRAFANA_PID)))"; \
	else \
		GF_PATHS_PROVISIONING=$(ROOT)/backend/grafana/provisioning \
		GF_PATHS_DATA=$(GRAFANA_DATA) \
		$(BREW)/bin/grafana server \
			--config=$(ROOT)/backend/grafana/grafana.ini \
			--homepath=$(BREW)/share/grafana \
			>$(GRAFANA_LOG) 2>&1 & \
		echo $$! >$(GRAFANA_PID); \
		echo "→ grafana started (pid $$(cat $(GRAFANA_PID)))  logs: $(GRAFANA_LOG)"; \
	fi
	@[ -x $(PROXY_BIN) ] || $(MAKE) -C $(PROXY_DIR) build
	@if [ -f $(PROXY_PID) ] && kill -0 "$$(cat $(PROXY_PID))" 2>/dev/null; then \
		echo "  proxy already running (pid $$(cat $(PROXY_PID)))"; \
	else \
		DB_PATH=$(PROXY_DATA) $(PROXY_BIN) >$(PROXY_LOG) 2>&1 & \
		echo $$! >$(PROXY_PID); \
		echo "→ proxy started (pid $$(cat $(PROXY_PID)))  logs: $(PROXY_LOG)"; \
	fi
	@echo ""
	@echo "  Loki     http://localhost:3100        OTLP: POST /otlp/v1/logs"
	@echo "  Grafana  http://localhost:3000        login: admin / admin"
	@echo "  Proxy    http://localhost:4318        OTLP writes: POST /v1/logs (Bearer)   admin GUI: /"

## Stop Loki, Grafana, and the write proxy (data is preserved).
backend-down:
	@if [ -f $(LOKI_PID) ]; then \
		kill "$$(cat $(LOKI_PID))" 2>/dev/null && echo "→ loki stopped" || true; \
		rm -f $(LOKI_PID); \
	else echo "  loki not running"; fi
	@if [ -f $(GRAFANA_PID) ]; then \
		kill "$$(cat $(GRAFANA_PID))" 2>/dev/null && echo "→ grafana stopped" || true; \
		rm -f $(GRAFANA_PID); \
	else echo "  grafana not running"; fi
	@if [ -f $(PROXY_PID) ]; then \
		kill "$$(cat $(PROXY_PID))" 2>/dev/null && echo "→ proxy stopped" || true; \
		rm -f $(PROXY_PID); \
	else echo "  proxy not running"; fi

## Show whether Loki, Grafana, and the write proxy are running and reachable.
backend-status:
	@echo "Loki:"; \
	if [ -f $(LOKI_PID) ] && kill -0 "$$(cat $(LOKI_PID))" 2>/dev/null; then \
		echo "  process  running (pid $$(cat $(LOKI_PID)))"; \
		curl -sf http://localhost:3100/ready >/dev/null && echo "  /ready   OK" || echo "  /ready   not responding (starting up?)"; \
	else echo "  stopped"; fi
	@echo "Grafana:"; \
	if [ -f $(GRAFANA_PID) ] && kill -0 "$$(cat $(GRAFANA_PID))" 2>/dev/null; then \
		echo "  process  running (pid $$(cat $(GRAFANA_PID)))"; \
		curl -sf http://localhost:3000/api/health >/dev/null && echo "  /health  OK" || echo "  /health  not responding (starting up?)"; \
	else echo "  stopped"; fi
	@echo "Proxy:"; \
	if [ -f $(PROXY_PID) ] && kill -0 "$$(cat $(PROXY_PID))" 2>/dev/null; then \
		echo "  process  running (pid $$(cat $(PROXY_PID)))"; \
		curl -sf http://localhost:4318/healthz >/dev/null && echo "  /healthz  OK" || echo "  /healthz  not responding (starting up?)"; \
	else echo "  stopped"; fi

## Run the end-to-end verification against the frozen contract fixtures.
backend-verify:
	@$(ROOT)/backend/verify.sh

## Delete all persisted Loki, Grafana, and proxy data (full reset; does not stop running processes).
backend-clean:
	@echo "Removing $(LOKI_DATA), $(GRAFANA_DATA), and $(PROXY_DATA) ..."
	@echo "  WARNING: removing $(PROXY_DATA) deletes all minted write tokens — every SDK using a local token must be re-pointed at a freshly minted one after this."
	@rm -rf $(LOKI_DATA) $(GRAFANA_DATA)
	@rm -f $(PROXY_DATA) $(PROXY_DATA)-wal $(PROXY_DATA)-shm
	@echo "Done. Run 'make backend-up' to reinitialise."
