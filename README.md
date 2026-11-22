# **`dsh`**, self-hosted; local-only 
A single-user deployment of [DeepSeek Harness (`dsh`)](https://github.com/deepseek-ai/deepseek-harness).
Fully containerized.
Local AI; no external APIs, no external services.

See: [Remote API surface](#remote-api-surface-what-touches-the-network) below.

## Layout

| Path                        | Role                                                            |
| ---                         | ---                                                             |
| `docker-compose.yml`        | The deployment: one service, `ai-backend` network, localhost port |
| `Dockerfile`                | `node:24-bookworm-slim` + pinned `@deepseek-ai/dsh` + `pnpm`     |
| `entrypoint.sh`             | Seeds profile; binds the listener to the container IP; forwards public-URL/trusted-host flags |
| `profile/web/package.json`  | The `web` profile manifest (base + web-app bundles)             |
| `profile/web/cordis.patch.yml` | The local-only configuration (model route, privacy, tools, sandbox) |
| `.env.example`              | Non-secret settings; copy to `.env`    |
| `data/dsh`                  | `$DSH_HOME`: sessions, credentials, profile patch, logs, storages |
| `data/agents`               | `$DSH_AGENTS_HOME`: `AGENTS.md`, `skills/` (shared agent config root) |
| `workspace`                 | The mounted workspace; agent writes are fenced here by default  |

## Running

```sh
docker network inspect ai-backend >/dev/null  # if missing
cp .env.example .env
docker compose up -d --build
docker compose logs dsh      # "dsh web:" line = login URL
```

First use in the browser:

1. Open the login URL printed in the logs (which carries a **per-start launch
   token**; a restart mints a new one, so grab fresh line after restarts).
   The token is exchanged for a signed session cookie (30 days).
2. **Choose workspace**: pick `/workspace` (or any directory visible in the
   container; mount more project directories into the container in
   `docker-compose.yml`).
3. Send a task. Model is already configured: LiteLLM `swol-doge` via
   `http://litellm:4000/v1` (override with `DSH_MODEL` / `LITELLM_BASE_URL`).
   Leave the DeepSeek card on **Settings → Models** empty to stay local.

### Tailscale (tailnet access)

```sh
# .env
DSH_PUBLIC_URL=https://<device>.<tailnet>.ts.net:8445/
DSH_TRUSTED_HOSTS=<device>.<tailnet>.ts.net

tailscale serve --bg --https=8445 http://127.0.0.1:49175
```

The entrypoint turns `DSH_PUBLIC_URL` into `--public-url` (so the printed URL
is the tailnet URL) and each `DSH_TRUSTED_HOSTS` entry into `--trusted-host`
(the Host/Origin fence that lets a remote browser through).

### Headless one-shot (optional)

```sh
docker compose run --rm --entrypoint dsh dsh \
  --profile headless "Summarize the repository in /workspace."
```

The `headless` profile auto-initializes from the shipped template on first
use (no network needed).

## How it stays local

`profile/web/cordis.patch.yml` is the single source of local-only policy.
The Web UI's model/settings edits write to the live copy at
`data/dsh/profiles/web/cordis.patch.yml` (seeded from `profile/web/` on first
start, never clobbered afterwards) and hot-reload via dsh's HMR.

## Remote API surface — what touches the network

dsh's upstream design assumes the official DeepSeek API. 
Every remote capability and its fate in this deployment:

| # | Feature (upstream) | Remote endpoint | Here |
|---|---|---|---|
| 1 | Model inference, built-in `deepseek-official` route (default model `deepseek-flash`); the Models page also polls DeepSeek's published model list once a DeepSeek key is saved | DeepSeek API | **Replaced.** The default model and the only provider route are the local LiteLLM gateway (custom OpenAI-compatible provider `litellm`). No DeepSeek key or account exists anywhere, so the official route is never usable. |
| 2 | OTel session telemetry (`dsh-session-telemetry-otel`), default `FEEDBACK_ONLY` | `https://dsh-otel-collector.deepseeksvc.com/v1/logs` | **Disabled.** Patch sets `mode: DISABLED`: "no coordinator, provider, processor, or exporter is constructed; no telemetry record leaves the process." (Env levers exist too: `DSH_TELEMETRY_MODE` / `DSH_TELEMETRY_DISABLED`.) |
| 3 | DeepSeek session-log upload (`dsh-session-log-deepseek`, default on) — appends a `dsh_session_log` field to official DeepSeek requests | DeepSeek API (piggybacks on #1) | **Disabled.** Patch sets `enabled: false`. Only effective on official-API requests anyway, which this deployment never makes. |
| 4 | `web_search` — the only shipped providers are the DeepSeek Search API and the legacy DeepSeek Messages search | DeepSeek Search / Messages API | **Neutralized.** Both provider rows pin their credential reference to `DSH_DISABLED_SEARCH_KEY`, a variable this deployment never sets, so no search request can be authenticated or sent. In the Web UI each agent preset still registers `web_search` (it can't be unregistered per-preset); a call fails locally with `WEB_PROVIDER_UNAVAILABLE`. **Local OSS replacement:** the entry's `mcp-search-gateway` client connects your Search Gateway's MCP endpoint (`http://search-gateway:8080/mcp`, SearXNG + Crawl4AI) as a streamable-HTTP MCP server; its tools show up as `mcp__search-gateway__*`. Disable with `DSH_MCP_SEARCH_GATEWAY=0`. To restore the original instead: set `DEEPSEEK_API_KEY` and remove the two credential pins. |
| 5 | `web_fetch` — anonymous local HTTP(S) fetcher | none (direct fetch to public sites) | **Kept.** No vendor API involved; same posture as your own gateway's crawler. |
| 6 | DeepSeek account sign-in (`dsh-deepseek-account-platform`) | DeepSeek account service | **Unused.** The OAuth callback listener opens only during an explicit login attempt; no sign-in is configured. |
| 7 | Optional subagent bundles (`dsh-subagent-codex`, `dsh-subagent-claude-code`) | OpenAI / Anthropic APIs | **Not installed.** They are opt-in `dsh plugin add` packages; neither is present, so no such calls exist. |

Everything else — sessions, storages, LLM calls (via LiteLLM), shell/sandbox,
skills, MCP clients, session titles, compaction — is local to this machine or
your `ai-backend` network.

## Notes

- **Ports.** The container listener binds the container's own bridge IP
  (dsh's webserver accepts one concrete local address and refuses wildcard
  binds); the compose mapping publishes it to `127.0.0.1:49175` only. The
  healthcheck treats a responding server (entry page answers 401 without the
  launch token) as healthy.
- **Sandbox.** Default preset `workspace-write`: the agent may write under
  the session workspace (fenced by the sandbox policy, whose fallback root is
  `/workspace`) and is asked before risky actions. Switch with
  `DSH_PERMISSION_MODE` (`read-only` / `workspace-write` / `danger-full-access`).
- **Updating.** Bump `DSH_VERSION` in `.env` and `docker compose up -d --build`.
  dsh is in rapid developer preview and ships breaking changes: after an
  upgrade, verify the composed configuration still resolves:

  ```sh
  docker compose run --rm --entrypoint dsh dsh --profile web --dump-config
  ```

  (exit 0, no stderr warnings = your patch rows all matched).
- **Data.** `data/dsh` is the durable root (sessions survive restarts);
  `data/agents` holds the shared `AGENTS.md`/`skills` the agent reads;
  credentials, if ever added, live in `data/dsh/.credentials.yaml`.
