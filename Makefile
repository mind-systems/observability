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

.PHONY: backend-install backend-up backend-down backend-status backend-verify backend-clean

## Install Loki and Grafana via Homebrew (idempotent).
backend-install:
	brew install loki grafana

## Start Loki and Grafana with the repo's config (installs first if needed).
backend-up:
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
	@echo ""
	@echo "  Loki     http://localhost:3100        OTLP: POST /otlp/v1/logs"
	@echo "  Grafana  http://localhost:3000        login: admin / admin"

## Stop Loki and Grafana (data is preserved).
backend-down:
	@if [ -f $(LOKI_PID) ]; then \
		kill "$$(cat $(LOKI_PID))" 2>/dev/null && echo "→ loki stopped" || true; \
		rm -f $(LOKI_PID); \
	else echo "  loki not running"; fi
	@if [ -f $(GRAFANA_PID) ]; then \
		kill "$$(cat $(GRAFANA_PID))" 2>/dev/null && echo "→ grafana stopped" || true; \
		rm -f $(GRAFANA_PID); \
	else echo "  grafana not running"; fi

## Show whether Loki and Grafana are running and reachable.
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

## Run the end-to-end verification against the frozen contract fixtures.
backend-verify:
	@$(ROOT)/backend/verify.sh

## Delete all persisted Loki and Grafana data (full reset; does not stop running processes).
backend-clean:
	@echo "Removing $(LOKI_DATA) and $(GRAFANA_DATA) ..."
	@rm -rf $(LOKI_DATA) $(GRAFANA_DATA)
	@echo "Done. Run 'make backend-up' to reinitialise."
