# runpod-llm-fleet

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![IRC: #lanbat on Libera.Chat](https://img.shields.io/badge/IRC-%23lanbat%20on%20Libera.Chat-2f4bff.svg)](https://web.libera.chat/#lanbat)

**Run your own open-weight LLMs on serverless GPUs, one endpoint per job, and pay only while they answer.**

This repository holds a small fleet of language models on [RunPod](https://www.runpod.io/) serverless
endpoints (the vLLM worker, behind an OpenAI-compatible API). Each purpose gets a model sized
for its task, its own scaling policy and a behaviour test suite, so you can swap models with evidence
instead of vibes.

Part of [LAN BAT](https://lanbat.github.io/), open home infrastructure. The Home Assistant
endpoint is the voice and conversation agent for [lanbat/nixconf](https://github.com/lanbat/nixconf).

## The fleet

| Purpose | Directory | Model | Consumer | Scaling |
|---------|-----------|-------|----------|---------|
| Coding assistant backend | [`models/coding-agent`](models/coding-agent/README.md) | Qwen3.8-27B (FP8) | [opencode](https://opencode.ai/) | Scale-to-zero |
| Home Assistant conversation agent | [`models/home-assistant`](models/home-assistant/README.md) | Qwen3-8B (AWQ) | Home Assistant | Scale-to-zero |

## Why this setup

- **Your model, your endpoint.** Code and home-automation requests go to an open-weight model you chose
  and deployed, not a closed chat API that can change under you.
- **Scale-to-zero.** Workers stop after a few idle minutes. Each model README shows the real
  numbers: always-on for the Home Assistant model would have cost about $790 a month.
- **Tested like software.** Every model has `.feature` specs and a `run_tests.sh` that runs against the
  live endpoint: the OpenAI API contract and availability for both, tool calling for Home Assistant,
  and context budget and agent stability for the coding model.
- **Decisions written down.** The model READMEs explain why the Home Assistant agent stays on Qwen3-8B
  rather than Qwen3.5, and how context length trades against cold-start time.
- **One command to rebuild.** `deploy-fleet.sh` deploys or refreshes the endpoints, installs the
  opencode config and smoke-tests the result.

## Quick start

You need `curl`, `python3`, `sqlite3`, `npm` and a RunPod API key.

```bash
git clone https://github.com/lanbat/runpod-llm-fleet
cd runpod-llm-fleet

# API key for the scripts (opencode reads it from a file, see docs/opencode-setup.md)
mkdir -p ~/.config/envman
echo 'export RUNPOD_API_KEY="rpa_..."' > ~/.config/envman/RUNPOD.env

# Deploy or refresh the endpoints, install the opencode config, run the smoke tests
./scripts/deploy-fleet.sh all      # both endpoints
./scripts/deploy-fleet.sh coding   # coding endpoint only
./scripts/deploy-fleet.sh verify   # smoke-test without redeploying
```

To use the coding endpoint from opencode:

```bash
npm install -g @opencode/cli
./scripts/setup-opencode.sh
./scripts/validate-opencode.sh
```

Full guide: [`docs/opencode-setup.md`](docs/opencode-setup.md).

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

## Important Notes

- The RunPod endpoints are specific to this setup and may require different API keys
- All model test suites cost small amounts of RunPod GPU time
- **OpenCode** reads the API key from `~/.config/envman/RUNPOD.key` (not shell env) —
  see [`docs/opencode-setup.md`](docs/opencode-setup.md#api-key-why-a-file-not-an-env-var)
- Shell scripts (`deploy-fleet.sh`, `run_tests.sh`) use `RUNPOD_API_KEY` from the
  environment or `~/.config/envman/RUNPOD.env`
- For debugging agent behavior, check `~/.local/share/opencode/opencode.db`