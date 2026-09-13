# OpenCode extended permissions (reference)

**Primary setup guide:** [`docs/opencode-setup.md`](docs/opencode-setup.md)

This file documents an optional **extended-permissions** global config pattern. The
fleet's checked-in defaults live in `.opencode/opencode.json` (project-level) and use
OpenCode's native `permission` block rather than the older `tools` / `execution` schema
below.

## When to use this

Use the extended global config if you want tighter control over which bash commands and
paths are allowed at the **global** level. Most users should rely on the project config
in `.opencode/opencode.json` instead.

## API key

Always use a file reference (works from GUI launches):

```jsonc
"apiKey": "{file:~/.config/envman/RUNPOD.key}"
```

Sync the key file with `./scripts/sync-runpod-key.sh`. See
[`docs/opencode-setup.md`](docs/opencode-setup.md#api-key-why-a-file-not-an-env-var).

## Example global config with command restrictions

Replace `/path/to/your/projects` with your actual workspace roots.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "runpod": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "RunPod (Qwen3-Coder-Next)",
      "options": {
        "baseURL": "https://api.runpod.ai/v2/h8ins1a7nls350/openai/v1",
        "apiKey": "{file:~/.config/envman/RUNPOD.key}",
        "timeout": 600000,
        "chunkTimeout": 180000
      },
      "models": {
        "qwen3-coder-next": {
          "name": "Qwen3 Coder Next AWQ (RunPod)",
          "limit": { "context": 65536, "output": 32768 }
        }
      }
    }
  }
}
```

Project-level permissions (current fleet default) are in `.opencode/opencode.json`:

- `permission.edit`: `allow`
- `permission.bash`: `allow`
- `permission.external_directory`: `/tmp/*` allowed, everything else prompts

Install everything with `./scripts/setup-opencode.sh`.
