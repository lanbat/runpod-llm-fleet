# RunPod LLM Fleet Setup

This repository contains configuration and test suites for LLMs hosted on RunPod serverless endpoints, organized by purpose.

## Architecture

Each LLM purpose has its own directory under `models/`:
- `models/coding-agent` - Qwen3-Coder-Next (AWQ, qtum quant)
- `models/home-assistant` - Qwen3-8B (AWQ)

## Installation Instructions

### Prerequisites

1. **Required Tools**
   - `curl`
   - `python3` 
   - `sqlite3`
   - `npm` (for opencode)

2. **RunPod API key** — stored in `~/.config/envman/` (see
   [`docs/opencode-setup.md`](docs/opencode-setup.md))

### Setup Steps

1. **Clone Repository**
   ```bash
   git clone <repository-url>
   cd runpod-llm-fleet
   ```

2. **Install OpenCode + fleet config**
   ```bash
   npm install -g @opencode/cli
   echo 'export RUNPOD_API_KEY="rpa_..."' > ~/.config/envman/RUNPOD.env
   ./scripts/setup-opencode.sh
   ./scripts/validate-opencode.sh
   ```

   Full documentation: [`docs/opencode-setup.md`](docs/opencode-setup.md)

## Configuring a new RunPod endpoint

See [`docs/runpod-setup.md`](docs/runpod-setup.md) for standing up a new RunPod
serverless endpoint from scratch (template + endpoint creation via the REST API) —
needed when adding a new purpose to the fleet or rebuilding an existing endpoint.

## Running Tests

Navigate to a specific model directory and run the test suite:

```bash
cd models/coding-agent
./run_tests.sh
```

## Fleet Overview

| Purpose | Directory | Current Model | Consumer | Scaling |
|---------|-----------|---------------|----------|---------|
| Coding assistant backend | `models/coding-agent` | Qwen3-Coder-Next (AWQ) | opencode | Scale-to-zero |
| Home Assistant conversation agent | `models/home-assistant` | Qwen3-8B (AWQ) | Home Assistant | Scale-to-zero |

### Deploy / refresh endpoints

```bash
export RUNPOD_API_KEY=<key>
./scripts/deploy-fleet.sh all      # deploy both + install opencode config + test
./scripts/deploy-fleet.sh coding   # coding endpoint only
./scripts/deploy-fleet.sh verify   # smoke-test without redeploying
```

## Important Notes

- The RunPod endpoints are specific to this setup and may require different API keys
- All model test suites cost small amounts of RunPod GPU time
- **OpenCode** reads the API key from `~/.config/envman/RUNPOD.key` (not shell env) —
  see [`docs/opencode-setup.md`](docs/opencode-setup.md#api-key-why-a-file-not-an-env-var)
- Shell scripts (`deploy-fleet.sh`, `run_tests.sh`) use `RUNPOD_API_KEY` from the
  environment or `~/.config/envman/RUNPOD.env`
- For debugging agent behavior, check `~/.local/share/opencode/opencode.db`