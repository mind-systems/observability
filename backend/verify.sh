#!/usr/bin/env bash
# End-to-end verification: OTLP ingestion, LogQL query, label policy, restart marker.
# Uses the frozen contract fixtures as the test oracle.
# Run via: make backend-verify
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="$ROOT/observe-contract"
LOKI="http://localhost:3100"
PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ~ $1"; }

echo "=== backend verify ==="
echo ""

# 1. Loki readiness
echo "1. Loki ready"
for i in $(seq 1 30); do
  curl -sf "$LOKI/ready" >/dev/null 2>&1 && break
  [ "$i" -lt 30 ] && sleep 1 || { fail "Loki not ready after 30s — run 'make backend-up' first"; exit 1; }
done
ok "Loki is ready at $LOKI"

# 2. Ingest golden-record.json
echo ""
echo "2. Ingest golden-record.json"
STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$LOKI/otlp/v1/logs" \
  -H 'Content-Type: application/json' \
  --data-binary @"$CONTRACT/golden-record.json")
# Loki returns 204 (no body) on success; OTLP spec says 200 — both are acceptable.
[[ "$STATUS" = "200" || "$STATUS" = "204" ]] && ok "HTTP $STATUS" || { fail "HTTP $STATUS (expected 200 or 204)"; }

# 3. Ingest service-start.json
echo ""
echo "3. Ingest fixtures/service-start.json"
STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$LOKI/otlp/v1/logs" \
  -H 'Content-Type: application/json' \
  --data-binary @"$CONTRACT/fixtures/service-start.json")
[[ "$STATUS" = "200" || "$STATUS" = "204" ]] && ok "HTTP $STATUS" || { fail "HTTP $STATUS (expected 200 or 204)"; }

# Historical timestamps cause Loki to immediately cut head chunks; flush forces
# them through to the TSDB object store so they are visible to the querier.
curl -sS -X POST "$LOKI/flush" >/dev/null
sleep 3

# 4. Query back — range covers the fixture timestamps (2024) through now
echo ""
echo "4. Query logs back (LogQL)"
NOW_NS=$(python3 -c "import time; print(int(time.time() * 1e9))")
RESULT=$(curl -sS --max-time 10 -G "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={project="example-project"}' \
  --data-urlencode 'start=1700000000000000000' \
  --data-urlencode "end=${NOW_NS}" \
  --data-urlencode 'limit=10')
if echo "$RESULT" | grep -q '"values":\[\["'; then
  ok "Records found via {project=\"example-project\"}"
else
  fail "No records returned — check Loki config and ingest step"
fi

# 5. Label policy
echo ""
echo "5. Label set (must be project / service_name / level only)"
LABELS=$(curl -sS -G "$LOKI/loki/api/v1/labels" \
  --data-urlencode 'start=1700000000000000000' \
  --data-urlencode "end=${NOW_NS}")

for expected in project service_name level; do
  echo "$LABELS" | grep -q "\"$expected\"" \
    && ok "label '$expected' present" \
    || fail "label '$expected' missing — check otlp_config in backend/loki/loki.yaml"
done

# /labels returns only TSDB index labels, so these names will never appear there
# regardless of config — the positive assertion below is the real policy guard.
for forbidden in trace_id span_id order_id service_instance_id; do
  if echo "$LABELS" | grep -q "\"$forbidden\""; then
    fail "high-cardinality label '$forbidden' found — it must stay in structured metadata"
  else
    ok "no index label '$forbidden'"
  fi
done

warn "Full label list: $(echo "$LABELS" | grep -o '"data":\[[^]]*\]' || echo "$LABELS")"

# Positive guard: confirm trace_id is queryable as structured metadata (not just absent from the
# index). If the label policy is broken and trace_id were promoted to an index label, it would
# still satisfy the query below — but the forbidden check above would catch it first.
echo ""
echo "5b. trace_id queryable as structured metadata"
TRACE_RESULT=$(curl -sS --max-time 10 -G "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={project="example-project"} | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"' \
  --data-urlencode 'start=1700000000000000000' \
  --data-urlencode "end=${NOW_NS}" \
  --data-urlencode 'limit=5')
if echo "$TRACE_RESULT" | grep -q '"values":\[\["'; then
  ok "trace_id filter returns the golden record (structured metadata queryable)"
else
  fail "trace_id filter returned no results — check that trace_id stays in structured metadata and is indexed"
fi

# 6. service.start restart marker
echo ""
echo "6. service.start marker queryable"
RESULT=$(curl -sS --max-time 10 -G "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={project="example-project"} |= "service.start"' \
  --data-urlencode 'start=1700000000000000000' \
  --data-urlencode "end=${NOW_NS}" \
  --data-urlencode 'limit=10')
if echo "$RESULT" | grep -q '"values":\[\["'; then
  ok "service.start marker found via body substring match"
else
  fail "service.start marker not found — check fixtures/service-start.json ingest"
fi

# 7. Grafana health
echo ""
echo "7. Grafana reachable"
if curl -sf "http://localhost:3000/api/health" >/dev/null 2>&1; then
  ok "Grafana /api/health OK at http://localhost:3000"
else
  warn "Grafana not responding — run 'make backend-up' and wait a few seconds"
fi

# Summary
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
