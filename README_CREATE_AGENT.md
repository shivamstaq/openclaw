# Creating Agent Environments + Channel Config (CLI + Docker Compose)

This repo runs the OpenClaw Gateway + CLI via Docker Compose.
This guide shows how to:

- create a new isolated agent environment (workspace + agentDir + sessions)
- attach a dedicated channel account (example: Telegram bot) to that agent
- ensure the channel does NOT route to `main`
- do everything from the CLI (`docker compose run --rm openclaw-cli ...`)

## Mental model (what is an "agent"?)

An OpenClaw _agent_ is an isolated "brain" with its own:

- workspace (persona files like `AGENTS.md`, `SOUL.md`, optional `USER.md`)
- agentDir (auth profiles, model registry, per-agent state)
- session store under `~/.openclaw/agents/<agentId>/sessions`

Routing is deterministic: inbound messages map to exactly one agent via `bindings`.
If nothing matches, OpenClaw falls back to the default agent (usually `main`).

## Where config lives (Docker Compose)

OpenClaw reads config from (default):

- `~/.openclaw/openclaw.json`

In this repo's `docker-compose.yml`, the container sees that at:

- `/home/node/.openclaw/openclaw.json` (mounted from your host)

All commands below use:

```bash
docker compose run --rm openclaw-cli <openclaw-subcommand...>
```

### Compose environment variables

This repo's `docker-compose.yml` expects a couple of host paths so it can persist state:

- `OPENCLAW_CONFIG_DIR` (mounted to `/home/node/.openclaw`)
- `OPENCLAW_WORKSPACE_DIR` (mounted to `/home/node/.openclaw/workspace`)

Typical local setup:

```bash
export OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
export OPENCLAW_WORKSPACE_DIR="$HOME/.openclaw/workspace"
```

## Quick reference: inspect current state

```bash
docker compose run --rm openclaw-cli agents list --bindings
docker compose run --rm openclaw-cli config get agents.list --json
docker compose run --rm openclaw-cli config get bindings --json
docker compose run --rm openclaw-cli status --deep
```

## Step 1: Create a new agent environment

Preferred (wizard; interactive):

```bash
docker compose run --rm openclaw-cli agents add <agentId>
```

Non-interactive pattern (explicit workspace):

```bash
docker compose run --rm openclaw-cli agents add <agentId> \
  --workspace ~/.openclaw/workspace-<agentId> \
  --non-interactive
```

You can also pre-wire a routing rule at creation time using `--bind` (repeatable):

```bash
docker compose run --rm openclaw-cli agents add <agentId> \
  --workspace ~/.openclaw/workspace-<agentId> \
  --bind telegram:<accountId> \
  --non-interactive
```

After creation, verify:

```bash
docker compose run --rm openclaw-cli agents list --bindings
```

Expected:

- New workspace at `~/.openclaw/workspace-<agentId>`
- New agentDir at `~/.openclaw/agents/<agentId>/agent`
- No routing rules yet (unless you added them)

## Step 2: Add a dedicated channel account for that agent (Telegram example)

### Why "accounts" matter

For channels that support multiple accounts (Telegram bots, multiple WhatsApps, etc.), you should:

- define the account under `channels.<channel>.accounts.<accountId>`
- bind `match.accountId` to route that account to the right agent

This is the cleanest way to guarantee the channel is not handled by `main`.

### Configure Telegram account

1. Enable Telegram (if not already enabled):

```bash
docker compose run --rm openclaw-cli config set channels.telegram.enabled true
```

2. Add the new bot token under an account id:

Note: once you create `channels.telegram.accounts`, OpenClaw treats Telegram as multi-account.
In that mode, the legacy single-account `channels.telegram.botToken` alone is not enough to start a Telegram account - you must have at least one entry under `channels.telegram.accounts` (commonly `default`).

IMPORTANT: the CLI has two variants across releases:

- some builds: `openclaw config set ... --json`
- some builds: `openclaw config set ... --strict-json`

Check your build:

```bash
docker compose run --rm openclaw-cli config set --help
```

Then set the token (example uses `--json`):

```bash
docker compose run --rm openclaw-cli config set \
  channels.telegram.accounts.<accountId>.botToken \
  '"<BOT_TOKEN>"' \
  --json
```

If you previously had a single Telegram bot configured via `channels.telegram.botToken`, migrate it like this:

```bash
docker compose run --rm openclaw-cli config set channels.telegram.accounts.default '{}' --json
```

Or (explicit token under default):

```bash
docker compose run --rm openclaw-cli config set \
  channels.telegram.accounts.default.botToken \
  '"<BOT_TOKEN>"' \
  --json
```

3. Lock down DMs (recommended: allowlist):

```bash
docker compose run --rm openclaw-cli config set \
  channels.telegram.accounts.<accountId>.dmPolicy \
  '"allowlist"' \
  --json

docker compose run --rm openclaw-cli config set \
  channels.telegram.accounts.<accountId>.allowFrom \
  '[<TELEGRAM_USER_ID>]' \
  --json
```

Notes:

- `allowFrom` should be numeric Telegram user IDs.
- Alternative: set `dmPolicy` to `"pairing"` and then approve with:

  ```bash
  docker compose run --rm openclaw-cli pairing list telegram
  docker compose run --rm openclaw-cli pairing approve telegram <PAIR_CODE>
  ```

Security tip: `openclaw config get channels.telegram --json` may print tokens in plaintext.
Avoid pasting outputs into tickets or logs.

## Step 3: Route that channel account ONLY to the new agent

Add a binding that matches the channel + accountId.
This ensures that bot/account never falls back to `main`.

Example: route Telegram account `<accountId>` to agent `<agentId>`:

```bash
docker compose run --rm openclaw-cli config set bindings \
  '[{"agentId":"<agentId>","match":{"channel":"telegram","accountId":"<accountId>"}}]' \
  --json
```

If you already have bindings, do not overwrite them blindly.
Instead, edit `~/.openclaw/openclaw.json` and append a new binding entry, or use a JSON-aware patch workflow.

You can also make bindings more specific by matching a peer:

```json5
{
  agentId: "<agentId>",
  match: {
    channel: "telegram",
    accountId: "<accountId>",
    peer: { kind: "direct", id: "<TELEGRAM_USER_ID>" },
  },
}
```

Peer kinds:

- `direct` (DM)
- `group`
- `channel`

(`dm` is accepted as a legacy alias for `direct`.)

Verify routing:

```bash
docker compose run --rm openclaw-cli agents list --bindings
docker compose run --rm openclaw-cli config get bindings --json
```

## Step 4: Restart gateway + verify health

In Docker Compose, config changes often need a restart:

```bash
docker compose restart openclaw-gateway
```

Then verify:

```bash
docker compose run --rm openclaw-cli status --deep
```

Look for:

- Telegram: `OK` for your new account
- Agents: your agent listed
- Routing: your agent shows the routing rule(s)

## Step 5: Send a test message via the new account

```bash
docker compose run --rm openclaw-cli message send \
  --channel telegram \
  --account <accountId> \
  --target <TELEGRAM_USER_ID> \
  --message "Hello from <agentId>"
```

This tests:

- the bot token is valid
- the gateway can reach `api.telegram.org`
- the accountId is wired up

## Optional: enable web tools (web_fetch + web_search)

`web_fetch` is usually enabled by default. `web_search` requires an API key.

Enable search in config:

```bash
docker compose run --rm openclaw-cli config set tools.web.fetch.enabled true --json
docker compose run --rm openclaw-cli config set tools.web.search.enabled true --json
docker compose run --rm openclaw-cli config set tools.web.search.provider '"brave"' --json
docker compose run --rm openclaw-cli config set tools.web.search.maxResults 5 --json
```

Provide a Brave Search API key via one of these options:

1. Store in config (simplest):

```bash
docker compose run --rm openclaw-cli config set tools.web.search.apiKey '"<BRAVE_API_KEY>"' --json
```

2. Store in OpenClaw env file (keeps it out of JSON config):

- Put `BRAVE_API_KEY=...` into `~/.openclaw/.env` (host path; mounted into the container).
- Restart the gateway.

## Example: one Telegram bot per agent

`~/.openclaw/openclaw.json` (illustrative):

```json5
{
  agents: {
    list: [
      { id: "main", default: true, workspace: "~/.openclaw/workspace" },
      { id: "gym", workspace: "~/.openclaw/workspace-gym" },
    ],
  },

  bindings: [{ agentId: "gym", match: { channel: "telegram", accountId: "gymstaqbot" } }],

  channels: {
    telegram: {
      enabled: true,
      accounts: {
        gymstaqbot: {
          botToken: "<BOT_TOKEN>",
          dmPolicy: "allowlist",
          allowFrom: [123456789],
        },
      },
    },
  },
}
```

With this config, anything received by the Telegram account `gymstaqbot` routes to agent `gym`.

## Troubleshooting

- Verify config is valid:

  ```bash
  docker compose run --rm openclaw-cli doctor
  ```

- Follow logs while sending a Telegram DM:

  ```bash
  docker compose run --rm openclaw-cli logs --follow
  ```

- Confirm the CLI sees your account config:

  ```bash
  docker compose run --rm openclaw-cli config get channels.telegram.accounts.<accountId> --json
  ```

- If Telegram shows OK but you get no replies:
  - confirm your `dmPolicy` and `allowFrom`/pairing state
  - in groups, check Telegram privacy mode (`/setprivacy`) and mention gating

## Related docs

- https://docs.openclaw.ai/cli/agents
- https://docs.openclaw.ai/cli/config
- https://docs.openclaw.ai/concepts/multi-agent
- https://docs.openclaw.ai/channels/telegram
- https://docs.openclaw.ai/channels/channel-routing
- https://docs.openclaw.ai/cli/message
