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

## Local vs cloud endpoint selection

A project that ships to more than one environment (local dev, staging, prod) resolves the OTLP endpoint to one of two backends: the local one (native, no-Docker) or a deployed cloud one. The selection is a build/deploy-time concern, not a runtime toggle — it is resolved once, the same place `LOG_DESTINATION` is resolved, and it follows the *shape* the platform already uses for this kind of value:

| Resolution mechanism | Where the value lives |
|---|---|
| A compiled config object read at startup (e.g. a gitignored config class with a real copy and a tracked example/placeholder copy) | The real, gitignored copy — alongside whatever other per-environment values the project already keeps there |
| A plain environment file loaded by the runtime (e.g. `.env`-style, one file per environment) | The per-environment file, if it is already gitignored; never inside a tracked example file |
| A value baked into a built artifact by a bundler (e.g. a browser bundle) | The bundler's own local-override file for that build mode, **and** whatever mechanism the deploy pipeline already uses to pass build-time values into the build step (a build argument, a build-time secret, etc.) |

**Before adding a new file or mechanism to hold this value, check whether the project already has one.** Every one of these archetypes usually already exists for some other per-environment value (an API base URL, a database host) — reuse that exact place and shape rather than inventing a parallel one. A second, purpose-built file for "just the observability values" is a sign the existing convention was not checked first.

**A bundler's local-override file is scoped to a build mode, not to "the local environment."** A name like `.local` without a mode segment (e.g. a bare local-override file with no mode in its name) commonly loads in **every** build mode, not only the development one — a habit of calling "the dev environment" *local* can end up naming the wrong file, one that also loads during a production-mode build on the same machine and silently shadows that mode's own values. The mode-scoped name (local-override-for-mode-X) is the one that actually stays confined to that mode; verify which behavior the bundler documents before trusting a name that merely sounds dev-scoped.

**A project may not have a distinct build mode per deploy target.** "Staging" and "production" are often the same build mode (commonly the bundler's default production-like mode) pointed at different domains by the web server — there is no separate staging-mode file pair unless the project explicitly defines a third mode. In that case the single production-mode file pair is correct for both, and the actual per-deploy-target values (a staging cloud endpoint vs. a future prod one) are supplied at build time by the deploy pipeline (a build argument sourced from a per-target file one level up, outside the bundler's own env-file system), not by inventing a same-named `-staging`/`-prod` pair of bundler env files that the bundler would never load.

### Auth alongside the endpoint

A cloud endpoint reachable through a write-auth proxy (see `docs/backend.md`) requires a bearer token on every write, in addition to the endpoint URL — a local endpoint that writes directly to the backend typically does not. Wiring only the endpoint and forgetting the token produces a silent failure, not a crash (the SDK degrades on a failed export by design) — so it is easy to miss. Treat "endpoint + token" as one unit to wire, not two separate steps, whenever the target is proxy-fronted.

### Secrets never land in committed text

Real endpoint URLs and, especially, real tokens never belong in a committed spec, roadmap, or doc page — only in the gitignored config file/class that actually holds them. A spec or roadmap entry describes the mechanism ("reads X from gitignored file Y") and never repeats the live value. This holds even for the endpoint URL alone, which is not usually secret by itself — keeping the rule uniform (mechanism in docs, values in gitignored config, no exceptions) is simpler than judging case by case which value is sensitive enough to hide.

### Browser consumers: CORS is not just a dev-server problem

A browser-based consumer posting OTLP to a different origin than the one it is served from is a cross-origin request, and the shared backend is not meant to grow CORS headers to accommodate it (see `docs/playbooks/sdk-integration.md`'s CORS gotcha). The fix — a same-origin relative path proxied to the real backend — applies **at every stage the app is reachable from**, not only the local dev server: a deployed build needs the identical relative-path treatment at whatever web server actually fronts it in that environment, proxying the same relative path to the write-auth proxy. Wiring the dev-server proxy alone and assuming the deployed build inherits it is the recurring mistake.

## Default

`file` is the safe default — a project's behavior is unchanged until it opts into Grafana. For active local debugging, `both` is the typical choice.

This convention is uniform across every consuming project — same variable name, same three values, same mapping — so the workspace behaves the same everywhere. It is applied in each project's logger at integration time.
