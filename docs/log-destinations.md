# Log destinations

Each consuming project chooses where its logs go through a single environment variable, **`LOG_DESTINATION`**, read once where the project configures its logger — the single swap point. It takes one of three values:

| `LOG_DESTINATION` | File (project-local) | Grafana (shared Loki) |
|---|---|---|
| `file` | on | off |
| `grafana` | off | on |
| `both` | on | on |

- **`file`** — the project's own file/console logging, in the project, exactly as before. The observability stack never sees it.
- **`grafana`** — logs ship over OTLP to the shared local Loki backend, browsable in Grafana and correlated across services by `trace_id`.
- **`both`** — both at once; the same line is written locally and shipped centrally, independently of each other.

## Where the switch lives

Host-side, in each project's logger configuration, at the single point where output sinks are set up. When the mode includes `grafana`, the project attaches the OTLP sink (the SDK); when it includes `file`, the project keeps its file transport. Turning Grafana off simply means not attaching the OTLP sink — there is no separate "disabled" mode in the SDK.

The file sink is owned by the project. The SDK and this repository never write or collect log files; centralization happens only over OTLP into Loki.

## Scope

`LOG_DESTINATION` is read per service (per process); each service decides independently. Setting the same value across every service makes the choice effectively workspace-wide — there is no separate global switch. "Collected globally" means centralized in Loki/Grafana (the `grafana` and `both` modes), not a toggle that flips every service at once.

## Relationship to the OTLP endpoint

`LOG_DESTINATION` decides *whether* the OTLP sink is wired. *Where* it ships is a separate setting — the SDK's OTLP endpoint URL, which defaults to the local backend. The two are independent: the endpoint is *where*, the destination is *whether*.

## Default

`file` is the safe default — a project's behavior is unchanged until it opts into Grafana. For active local debugging, `both` is the typical choice.

This convention is uniform across every consuming project — same variable name, same three values, same mapping — so the workspace behaves the same everywhere. It is applied in each project's logger at integration time.
