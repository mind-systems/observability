# Backend: Loki + Grafana

The local observability backend is **Loki 3.x** (log storage and query) plus **Grafana** (UI and dashboards), both running as native macOS processes installed via Homebrew by default — no Docker required locally, no external services. One command brings the whole thing up from a fresh checkout. A separate Docker Compose stack (`backend/docker-compose.yml`) runs the same components for **server** deployment — additive, not a replacement for the native path.

## Running the backend

```
make backend-up       # start Loki, Grafana, and the write proxy (installs/builds first if needed)
make backend-down     # stop all three
make backend-status   # show whether processes are running and HTTP endpoints respond
make backend-verify   # end-to-end test against the frozen contract fixtures
```

`backend-up` is idempotent — safe to run if the processes are already running. It auto-installs Loki and Grafana via Homebrew on a machine that doesn't have them yet. The write proxy is different: it comes from the separate `observe-write-proxy` sibling repo, not Homebrew, so a new machine needs that repo cloned beside this one and a Go toolchain installed before `make backend-up` can build and start it — see `docs/playbooks/environment-setup.md`.

After startup:

| Service | URL |
|---------|-----|
| Grafana | http://localhost:3000 (admin / admin) |
| Loki    | http://localhost:3100 — internal; not used directly for writes (proxy) or reads (`observe-logs` goes through Grafana's datasource-proxy API) |
| OTLP ingest | `POST http://localhost:3100/otlp/v1/logs` — reached only via the write proxy, never called directly by SDKs |
| Proxy   | http://localhost:4318 — OTLP writes: `POST /v1/logs` (Bearer write-token), admin GUI at `/` |

`make backend-up` builds the proxy binary once, only when it is absent. After pulling proxy source updates, rebuild explicitly before the next `make backend-up` — either `rm observe-write-proxy/bin/proxy` or `make -C observe-write-proxy build`.

A local SDK points at the proxy by setting its OTLP endpoint to `http://localhost:4318/v1/logs` and sending `Authorization: Bearer <token>`, where `<token>` is a write token minted in the proxy's admin GUI (`http://localhost:4318/`). This is the *where* — see `docs/log-destinations.md` for the `LOG_DESTINATION` switch, which is the *whether*.

## Reading logs

There is no direct-Loki read path, locally or remotely. The `observe-logs` skill queries Loki exclusively through **Grafana's datasource-proxy API** (`/api/datasources/proxy/uid/<uid>/loki/api/v1/...`), resolved per environment from a registry the skill owns — never `http://localhost:3100` directly. This applies even to the local backend: register a `local` environment pointing at Grafana's own Loki datasource (`backend/grafana/provisioning/datasources/loki.yaml`) rather than Loki's port directly.

## Data storage

Loki, Grafana, and the write proxy persist data under `~/.local/share/observe/`:

| Path | Contents |
|------|----------|
| `~/.local/share/observe/loki/` | chunks, TSDB index, WAL, rules |
| `~/.local/share/observe/grafana/` | Grafana state (dashboards, sessions) |
| `~/.local/share/observe/proxy.db` | the write proxy's token store (minted write tokens) |

Both directories survive reboots, and so does the proxy's token store. `make backend-up` creates the data directories automatically on first run. `make backend-down` stops the processes but leaves the data intact. `make backend-clean` wipes everything for a fresh start — **including `proxy.db`**, which deletes every minted write token; any SDK pointed at a local token needs a freshly minted one after a clean. `backend-clean` does not stop running processes, so run `make backend-down` first if the proxy is running — deleting its SQLite WAL/SHM files out from under an open connection can corrupt the next checkpoint.

PID files and process logs (`/tmp/obs-loki.pid`, `/tmp/obs-loki.log`, etc.) remain in `/tmp` — they are ephemeral by nature and recreated on each `make backend-up`.

Repeated `make backend-verify` runs accumulate duplicate fixture records in the store (the same payloads are ingested each time). This does not affect verification — the script checks for non-empty results, not exact counts — but a long-running instance will accumulate historical fixture data over time. `make backend-clean` + `make backend-up` resets to a clean state.

## Why Loki 3.x

Loki's native OTLP log ingestion endpoint (`/otlp/v1/logs`) appeared in version 3.0. Earlier versions require a Prometheus push format or a collector in front. The SDKs speak OTLP and connect to Loki directly — no collector — so Loki 3.x is a hard requirement. Downgrading to 2.x would break native OTLP ingestion.

## Single-binary mode

Loki supports many deployment topologies. The local backend runs in **single-binary mode** (`target: all`): all Loki components — distributor, ingester, querier, query frontend — live in one process sharing an in-memory ring. No external key-value store, no distributed coordination.

### The sharding deadlock in Loki 3.7.x

In single-binary mode, Loki 3.7.x has a bug where the query frontend shards queries across the querier fleet. In a real distributed deployment this works: multiple querier processes handle the sub-queries. In single-binary mode the query frontend *is* the querier, so it deadlocks — the main query goroutine enqueues sub-queries and waits for the querier goroutine to dequeue them, but they're the same goroutine. The symptom is 100–200% CPU spin with queries that never return.

Three settings together prevent this deadlock:

```yaml
query_range:
  parallelise_shardable_queries: false  # disable query sharding

limits_config:
  split_queries_by_interval: 0          # disable time-range splitting into sub-queries

querier:
  max_concurrent: 2                     # cap concurrent querier goroutines
```

All three must be present. Removing any one of them allows the deadlock to re-emerge.

## Label policy

Loki indexes labels as TSDB series keys — every unique combination of label values is a separate series. High-cardinality labels (values that vary per record, like `trace_id` or `order.id`) create millions of unique series, which degrades Loki's index performance severely.

**Only three fields are index labels: `project`, `service_name`, `level`.** Everything else — `trace_id`, `span_id`, order IDs, instance IDs, event names — stays in structured metadata (Loki 3.x feature) or the log body. This keeps the index small regardless of traffic volume.

### How the policy is enforced

`limits_config.otlp_config` controls how Loki maps OTLP attributes to Loki labels:

- `resource_attributes.ignore_defaults: true` — suppresses Loki's default behavior of auto-promoting ~17 OTel resource attributes (like `service.instance.id`, `k8s.node.name`, etc.) as labels. Without this, Loki would create high-cardinality labels automatically.
- `resource_attributes.attributes_config` with `action: index_label` selects `project` and `service.name` from resource attributes.
- `log_attributes` with `action: index_label` selects `level` from per-record attributes.

Any attribute not explicitly listed as `index_label` goes to structured metadata automatically.

### `service.name` becomes `service_name`

Loki sanitizes dots in attribute keys to underscores when creating label keys. The OTLP resource attribute `service.name` becomes the Loki label `service_name`. This is Loki's built-in behavior. The contract's logical label name `service` is realized as `service_name` in Loki — both refer to the same concept.

## WAL and disk throttle

Loki's ingester uses a write-ahead log (WAL) to survive restarts. By default, Loki 3.x throttles WAL writes when the disk is above 90% capacity (`disk_full_threshold` defaults to `0.9`). On machines at 94%+ disk usage, every write is rejected.

```yaml
ingester:
  wal:
    enabled: true
    disk_full_threshold: 0   # 0 = disable the disk-fullness check
```

The WAL must stay enabled. Disabling it (`enabled: false`) breaks the ingester's ring membership mechanism even in single-binary mode and causes query deadlocks independent of the sharding issue above.

## Historical data and the flush behavior

Loki's ingester holds active log streams in memory as "head chunks". When a chunk ages out (default `max_chunk_age` is 2 hours) or when the stream goes idle, the ingester flushes it to the filesystem object store and the TSDB index updates.

The contract fixtures carry timestamps from June 2024 — roughly two years before the current date. When Loki ingests a record whose timestamp falls that far in the past, it immediately cuts the head chunk (the timestamp is outside the active window) and schedules a flush. The data does not stay in ingester memory.

This affects querying: the querier has two paths — **ingester** (in-memory chunks) and **store** (TSDB on disk). For historical timestamps, the ingester path returns nothing (`totalChunksMatched: 0`). The store path returns results, but only after the flush completes.

`POST /flush` forces an immediate flush of all pending chunks. `backend/verify.sh` calls it after ingestion and waits 3 seconds before querying. Without the flush, a query issued within a few seconds of ingest may return no results even though the ingest succeeded (returned 204).

### Settings required for historical data

```yaml
limits_config:
  reject_old_samples: false    # Loki rejects samples older than ~1 week by default
  max_query_length: 0          # removes the default 30-day query range limit
```

`reject_old_samples: false` allows ingesting the 2024 fixtures without rejection errors. `max_query_length: 0` removes the default 30-day cap — a query spanning from 2024 to now would otherwise fail.

### `query_ingesters_within`

This setting tells the querier to skip the ingester for timestamps older than the specified duration. The default is 3 hours, meaning the querier never contacts the ingester for records older than 3 hours. Setting it to `0` means the ingester is always queried regardless of timestamp age.

This setting is silently ignored when placed in the `querier:` YAML block — Loki does not apply it from that location despite accepting the config without error. It only takes effect as the CLI flag:

```
loki -querier.query-ingesters-within=0
```

The `Makefile` passes this flag explicitly when starting Loki.

## OTLP response code

Loki's OTLP endpoint returns **HTTP 204** (no body) on successful ingestion. The OTLP specification defines 200 with a JSON response body as the success code. Both are valid; verification scripts and SDK clients must accept either.

## Verification

`make backend-verify` runs `backend/verify.sh` against the frozen contract fixtures (`observe-contract/`). The script:

1. Polls `/ready` for up to 30 seconds — fails fast if Loki is not running.
2. Posts `golden-record.json` to `/otlp/v1/logs` — asserts 200 or 204.
3. Posts `fixtures/service-start.json` to `/otlp/v1/logs` — asserts 200 or 204.
4. Calls `POST /flush` and waits 3 seconds for the TSDB store to update.
5. Queries `{project="example-project"}` over the range from November 2023 to now — asserts records are returned.
6. Queries `/loki/api/v1/labels` — asserts `project`, `service_name`, `level` are present; asserts `trace_id`, `span_id`, `order_id`, `instance_id` are absent.
7. Queries for `service.start` in the log body — confirms the restart marker fixture is retrievable.
8. Checks Grafana `/api/health`.

The script exits 0 only when all checks pass. It uses the contract fixtures as the test oracle: if the fixtures ingest and query correctly, the label policy is correct and the OTLP contract is honored end-to-end.
