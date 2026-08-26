# Configuring a RunPod serverless LLM endpoint

Runbook for standing up a new RunPod-hosted LLM for this fleet: a serverless
**template** (the vLLM worker image + its config) plus a serverless **endpoint** (the
scaling policy that runs workers from that template). Everything here is done directly
against the RunPod REST API — there's no Terraform/IaC for this repo (see root
`CLAUDE.md`).

> **API version note**: this uses REST API **v1** (`https://rest.runpod.io/v1`), which
> is what every existing endpoint in this fleet was created with. RunPod has announced
> v1 is deprecated and will be retired **2026-11-15**; migrate to v2
> (`docs.runpod.io/api-reference-v2`) before then — check its docs for the current
> template/endpoint creation shape when you do, since the fields below are v1-specific.

## Prerequisites

- `RUNPOD_API_KEY` exported (same key used everywhere else in this repo).
- `curl` and `jq`.
- The Hugging Face model id you're deploying, and its `config.json` checked for the
  `architectures` field — see "Before deploying a very recently released model" in the
  root `CLAUDE.md` first. A `*ForConditionalGeneration` wrapper is a real risk signal
  even for a text-only model; two separate deploys in this fleet failed on that exact
  pattern.

```bash
export RUNPOD_API_KEY=<key>
AUTH=(-H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json")
```

## 1. Create the template

The image pinned across this fleet is `runpod/worker-v1-vllm:v2.25.1` — stick with it
unless you have a specific reason to move (see the version-compatibility gotchas in
`CLAUDE.md` before bumping it). Config is passed entirely via `env`; the vLLM-relevant
vars mirror what's documented in each model's README (`models/coding-agent/README.md`,
`models/home-assistant/README.md`) — set `MODEL_NAME`/`QUANTIZATION` for the model you're
deploying, adjust `MAX_MODEL_LEN` per the cold-start-vs-context tradeoff described there,
and only set `TOOL_CALL_PARSER`/`REASONING_PARSER`/`CUSTOM_CHAT_TEMPLATE` if the model
needs them (check its chat template's default "thinking" behavior first — see the
thinking-mode bug writeups in both model READMEs).

```bash
curl -s "${AUTH[@]}" https://rest.runpod.io/v1/templates \
  -d '{
    "name": "<purpose>-vllm",
    "imageName": "runpod/worker-v1-vllm:v2.25.1",
    "isServerless": true,
    "containerDiskInGb": 50,
    "env": {
      "MODEL_NAME": "<hf-org>/<hf-model>",
      "QUANTIZATION": "awq",
      "MAX_MODEL_LEN": "32768",
      "GPU_MEMORY_UTILIZATION": "0.9",
      "ENFORCE_EAGER": "true",
      "ENABLE_AUTO_TOOL_CHOICE": "true",
      "TOOL_CALL_PARSER": "hermes",
      "OPENAI_SERVED_MODEL_NAME_OVERRIDE": "<purpose>-model"
    }
  }' | jq .
```

Save the returned `id` — that's `templateId` for the next step.

## 2. Create the endpoint

```bash
curl -s "${AUTH[@]}" https://rest.runpod.io/v1/endpoints \
  -d '{
    "name": "<purpose>",
    "templateId": "<templateId from step 1>",
    "gpuTypeIds": ["NVIDIA L40", "NVIDIA L40S", "NVIDIA RTX A6000"],
    "workersMin": 0,
    "workersMax": 1,
    "idleTimeout": 300,
    "scalerType": "QUEUE_DELAY"
  }' | jq .
```

Notes on the fields most worth tuning:

- `workersMin: 0` is scale-to-zero (no cost while idle) — the fleet default. Only use
  `workersMin: 1` (always-on) for a genuinely latency-critical purpose, and go in aware
  of the cost: `models/home-assistant/README.md` measured ~$792/month always-on at the
  RTX 4090 tier before reverting to scale-to-zero.
- `idleTimeout` trades cold-start frequency against idle cost — see the
  cold-start-vs-context-window tradeoff in `models/coding-agent/README.md` for how this
  interacts with `MAX_MODEL_LEN`.
- List multiple `gpuTypeIds` as fallbacks for availability, not just one.
- Save the returned `id` — that's the endpoint id used in the base URL
  (`https://api.runpod.ai/v2/<endpoint id>/...`) everywhere else in this repo.

## 3. Verify it comes up healthy

Poll status and watch for `workers[].status` reaching `RUNNING` (not stuck cycling
`THROTTLED`/`INITIALIZING` — that cycle without ever reaching ready is the signature of
the architecture-compatibility failure mode in `CLAUDE.md`, not a capacity issue):

```bash
curl -s "${AUTH[@]}" https://rest.runpod.io/v1/endpoints/<endpoint id> | jq '.workers'
```

Then send a real request through the OpenAI-compatible route to confirm the model
actually answers (retry once if it hangs — see "RunPod sync route can spuriously
hang/timeout on the very first request" in `CLAUDE.md`):

```bash
curl -s https://api.runpod.ai/v2/<endpoint id>/openai/v1/chat/completions \
  -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
  -d '{"model": "<purpose>-model", "messages": [{"role": "user", "content": "ping"}], "max_tokens": 16}'
```

If this is a very recently released model, do this smoke test on a scale-to-zero
endpoint first even if the final deployment will be always-on — see "Cheap way to
de-risk this" in `CLAUDE.md`.

## 4. Wire it into this repo

Once the endpoint is healthy, follow "Adding a new purpose" in the root `README.md`:
create `models/<purpose>/`, write its README (record the template id, endpoint id, and
every env var from step 1 — that's the source of truth for rebuilding it), copy
`run_tests.sh`/`features/*.feature` from an existing model as a starting point, and wire
up whatever client consumes it.
