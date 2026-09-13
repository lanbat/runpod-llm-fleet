# OpenCode + RunPod setup

This guide covers installing and using [OpenCode](https://opencode.ai) with the
`coding-agent` RunPod endpoint (`qwen3-coder-next` on endpoint `h8ins1a7nls350`).

## Recommended setup (Cursor-like UX, RunPod Qwen model)

Global defaults live in `~/.config/opencode/opencode.json`:

| Setting | Value | Why |
|---------|-------|-----|
| `default_agent` | `build` | Direct implementation (not `plan`, which loops on large tasks) |
| `agent.plan.disable` | `true` | Plan mode disabled — it hangs/loops with RunPod Qwen |
| `model` | `runpod/qwen3-coder-next` | Self-hosted Qwen3 Coder Next on RunPod |
| `small_model` | `runpod/qwen3-coder-next` | Same endpoint for titles/summaries |
| `compaction.prune` | `true` | Drops old tool output to avoid 100k+ token blowups |
| `permission.external_directory` | `/home/traph/projects/**` allow | No prompts when reading across the monorepo |
| `watcher.ignore` | `node_modules`, `.git`, etc. | Faster indexing in large repos |

The `lanbat` monorepo has `.opencode/opencode.json` at its root so **any** subdirectory
inherits scoped instructions, permissions, and the RunPod model default.

## Quick start

```bash
# 1. Store your RunPod API key (pick one approach)
mkdir -p ~/.config/envman
echo 'export RUNPOD_API_KEY="rpa_..."' > ~/.config/envman/RUNPOD.env

# 2. Install opencode + fleet config
npm install -g @opencode/cli
cd runpod-llm-fleet
./scripts/setup-opencode.sh

# 3. Validate
./scripts/validate-opencode.sh

# 4. Use (first request after idle cold-starts the GPU — 1–5+ min wait)
cd runpod-llm-fleet
opencode                          # TUI — select runpod / qwen3-coder-next
opencode run --model runpod/qwen3-coder-next "explain this repo"
```

## Architecture

OpenCode loads config from several layers (later layers override earlier ones):

| Layer | Path | Purpose |
|-------|------|---------|
| Global provider | `~/.config/opencode/opencode.jsonc` | RunPod provider (`baseURL`, API key, model limits) |
| Project defaults | `.opencode/opencode.json` | Default model, agent, permissions, plugins |
| Credentials | `~/.local/share/opencode/auth.json` | OAuth/API keys for built-in providers (Anthropic, etc.) |

The RunPod provider is a **custom** OpenAI-compatible provider. It is **not** stored in
`auth.json` — the API key lives in config via a file reference.

```
┌─────────────┐     Bearer token      ┌──────────────────────────────────────┐
│  OpenCode   │ ────────────────────► │ RunPod serverless (h8ins1a7nls350)   │
│  TUI / CLI  │  /openai/v1/chat/...  │ vLLM + Qwen3-Coder-Next-AWQ         │
└─────────────┘                       └──────────────────────────────────────┘
       │
       │ reads
       ▼
 ~/.config/envman/RUNPOD.key   ← synced from RUNPOD_API_KEY / RUNPOD.env
 ~/.config/opencode/opencode.jsonc
 .opencode/opencode.json
```

## API key: why a file, not an env var

The provider config uses:

```jsonc
"apiKey": "{file:~/.config/envman/RUNPOD.key}"
```

**Do not use `{env:RUNPOD_API_KEY}`** for the OpenCode provider. OpenCode does not load
`.env` files automatically, and GUI/desktop launches (Cursor, a desktop shortcut, etc.)
do not inherit shell exports from `~/.zshrc`. When the env var is missing, OpenCode
substitutes an empty string and RunPod returns:

```json
{"status":401,"title":"Unauthorized","detail":"no token provided"}
```

The file-based key works regardless of how OpenCode is started.

### Key file layout

| File | Contents | Used by |
|------|----------|---------|
| `~/.config/envman/RUNPOD.env` | `export RUNPOD_API_KEY="rpa_..."` | Shell, `deploy-fleet.sh`, `run_tests.sh` |
| `~/.config/envman/RUNPOD.key` | Raw key only (no `export`) | OpenCode `{file:...}` substitution |

Keep both in sync when rotating keys:

```bash
./scripts/sync-runpod-key.sh    # reads RUNPOD_API_KEY or RUNPOD.env → writes RUNPOD.key
```

`RUNPOD.key` must be mode `600`.

## Scale-to-zero (no idle GPU cost)

Scaling is configured in **RunPod serverless endpoint settings**, not local scripts.
Source of truth: `models/coding-agent/endpoint-scaling.json`. Apply to the live endpoint:

```bash
source ~/.config/envman/RUNPOD.env
./scripts/deploy-fleet.sh scaling
```

| Setting | Value | Effect |
|---------|-------|--------|
| `workersMin` | `0` | Scale-to-zero — no GPU cost while idle |
| `workersMax` | `1` | At most one worker |
| `idleTimeout` | `600` | Worker shuts down 10 min after last request |
| `scalerType` | `QUEUE_DELAY` | Scale up when queue delay exceeds threshold |
| `scalerValue` | `4` | Queue-delay threshold (seconds) |

The first opencode request after idle triggers RunPod cold start automatically (1–5+ min).
OpenCode `timeout`/`chunkTimeout` are set high to tolerate this.

## Configuration reference

### Global provider (`opencode-config.jsonc`)

Installed to `~/.config/opencode/opencode.jsonc` by `setup-opencode.sh` or
`deploy-fleet.sh opencode`.

### Global runtime (`opencode-runtime.json`)

Installed to `~/.config/opencode/opencode.json` by `setup-opencode.sh`. Sets
`default_agent: build`, disables the `plan` agent (`agent.plan.disable: true`),
and configures compaction, permissions, and watcher ignores.

| Option | Value | Notes |
|--------|-------|-------|
| `baseURL` | `https://api.runpod.ai/v2/h8ins1a7nls350/openai/v1` | Coding-agent endpoint |
| `apiKey` | `{file:~/.config/envman/RUNPOD.key}` | See above |
| `timeout` | `600000` (10 min) | Tolerates cold starts |
| `chunkTimeout` | `180000` (3 min) | Per-chunk streaming timeout |
| `limit.context` | `65536` | Must match endpoint `MAX_MODEL_LEN` |
| `limit.output` | `32768` | Large enough for multi-KB `write` tool calls |

Model id in OpenCode: `runpod/qwen3-coder-next` (`provider/model` slash syntax).

### Project defaults (`.opencode/opencode.json`)

Checked into this repo. Applied when you run OpenCode inside `runpod-llm-fleet/`.

| Setting | Value | Purpose |
|---------|-------|---------|
| `model` | `runpod/qwen3-coder-next` | Default model |
| `default_agent` | `build` | Primary coding agent (must **not** be a subagent) |
| `enabled_providers` | `runpod`, `anthropic` | Limit provider picker |
| `plugin` | `opencode-claude-auth@latest` | Anthropic OAuth when needed |
| `permission.edit` | `allow` | Agent can edit files |
| `permission.bash` | `allow` | Agent can run shell commands |
| `permission.external_directory` | `/tmp/*` allow, `*` ask | Prompt before reading outside tmp |
| `compaction.auto` | `true` | Auto-summarize long sessions |
| `lsp` / `formatter` | `false` | Disabled for speed |

## Usage

### TUI (interactive)

```bash
cd runpod-llm-fleet
opencode
```

Select model **runpod / Qwen3 Coder Next** (or it will default from project config).
Type prompts at the bottom; the agent can edit files and run bash per permissions.

### One-shot CLI

```bash
opencode run --model runpod/qwen3-coder-next "Write a one-line Python add function"
```

### List models

```bash
opencode models runpod
# runpod/qwen3-coder-next
```

### Auth for built-in providers

```bash
opencode auth list
opencode auth login -p anthropic    # built-in providers only
```

Custom providers like `runpod` use the config file key — `opencode auth login -p runpod`
will fail with "Unknown provider".

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-opencode.sh` | Install global config, sync key file, smoke-test |
| `scripts/sync-runpod-key.sh` | Write `RUNPOD.key` from env or `RUNPOD.env` |
| `scripts/validate-opencode.sh` | Pre-flight checks (config, key, health, model list) |
| `scripts/deploy-fleet.sh opencode` | Install global config only (during fleet deploy) |
| `scripts/deploy-fleet.sh scaling` | Apply `endpoint-scaling.json` to RunPod (no redeploy) |

## Troubleshooting

### `401 Unauthorized: no token provided`

OpenCode is not sending a Bearer token.

1. Check key file exists: `ls -l ~/.config/envman/RUNPOD.key`
2. Re-sync: `./scripts/sync-runpod-key.sh`
3. Confirm config uses `{file:...}` not `{env:...}`:
   `grep apiKey ~/.config/opencode/opencode.jsonc`
4. Restart OpenCode after config changes

Test directly:

```bash
curl -s "https://api.runpod.ai/v2/h8ins1a7nls350/health" \
  -H "Authorization: Bearer $(cat ~/.config/envman/RUNPOD.key)"
```

### `Model not found: runpod:qwen3-coder-next/.`

OpenCode expects slash-separated model ids (`runpod/qwen3-coder-next`), not colon
(`runpod:qwen3-coder-next`). Update `.opencode/opencode.json` if you see this error.

### Prompt hangs / spinner never stops

This is usually **RunPod**, not OpenCode config:

1. **Run recovery** (stops opencode, purges queue, warms endpoint):
   ```bash
   ./scripts/runpod-recover.sh
   ```
2. **Only one opencode instance** — multiple TUI sessions multiply queued requests.
3. **Do not resume old sessions** — use `/new` or quit and restart `opencode`.
4. Check queue: `curl -s .../health | jq .jobs` — if `inQueue` > 0, run recover script.

**Root cause:** scale-to-zero + RunPod's sync `/openai/v1/chat/completions` route often
hangs on the first 1–2 requests after a worker becomes `ready`. Stuck opencode sessions
retry and refill the queue.

**Prevention:** scale-to-zero is configured in RunPod serverless settings (source of
truth: `models/coding-agent/endpoint-scaling.json`, applied via
`./scripts/deploy-fleet.sh scaling`). The first opencode request after idle triggers a
cold start automatically — expect 1–5+ minutes before the first token. No local wake
scripts are needed.

**Timeouts:** `chunkTimeout=180000` (3 min) tolerates cold starts; don't lower it
without accounting for cold-start latency.

### `default agent "build" is a subagent`

The project `default_agent` pointed at an agent with `"mode": "subagent"`. Subagents
cannot be the primary agent. The fleet config removes `mode: subagent` from `build`.
Pull latest `.opencode/opencode.json` or remove `"mode": "subagent"` yourself.

### Cold start / timeout

Scale-to-zero endpoints wake on first request (can take 1–5+ minutes). `timeout` and
`chunkTimeout` in the provider config are set high for this. Retry once if the first
request hangs right after a worker reports ready (known RunPod/vLLM quirk).

### `JSON parsing failed` on large file writes

The model hit `limit.output` mid-tool-call. Do not reduce `limit.output` below `32768`
without re-testing large `write` operations. See `models/coding-agent/README.md`.

### Debugging agent behavior

OpenCode stores sessions in SQLite:

```bash
sqlite3 ~/.local/share/opencode/opencode.db \
  "SELECT type, json_extract(data,'$.toolName') FROM part WHERE session_id='...' LIMIT 20;"
```

See `CLAUDE.md` and `models/coding-agent/README.md` for query examples.

### macOS temp-dir permission gotcha

On macOS, canonicalize temp dirs before opencode tests:

```bash
tmpdir=$(cd "$(mktemp -d)" && pwd -P)
```

`/var/folders/...` symlinks can fail `external_directory` checks against
`/private/var/folders/...`.

## Regression tests

```bash
export RUNPOD_API_KEY=$(cat ~/.config/envman/RUNPOD.key)   # or source RUNPOD.env
cd models/coding-agent
./run_tests.sh
```

Tests hit the live endpoint and invoke the real `opencode` CLI (costs a small amount of
GPU time). Scenarios are documented in `models/coding-agent/features/*.feature`.

## Related docs

- `models/coding-agent/README.md` — model choice, endpoint env vars, known bugs
- `docs/runpod-setup.md` — creating new RunPod endpoints
- `SETUP-GUIDE.md` — legacy pointer to this doc
- `OPENCODE-QWEN-CONFIG.md` — legacy extended-permissions example
