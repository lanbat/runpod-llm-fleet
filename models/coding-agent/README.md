# coding-agent

**Purpose**: LLM backend for [opencode](https://opencode.ai), used as a coding assistant
in local repos.

## Current model

`Qwen/Qwen3.8-27B-FP8` — Alibaba's official FP8 build of Qwen3.8-27B (dense 27B, hybrid
Gated-DeltaNet + full attention, thinks before answering). Selected Sep 2026 as the best
bang-for-buck coding model for this fleet's single 48 GB GPU tier:

- **Much stronger than Qwen3-Coder-Next on the same GPU** — SWE-bench Pro 61.7 vs 44.3,
  Terminal-Bench 2.1 73.0, Artificial Analysis Coding Index 68.1 (Coder-Next isn't in its
  top 45). Sep 2026 self-hosting guides rank it the best single-GPU coding model.
- **Smaller download** — 31 GB of weights vs 42 GB for the Coder-Next AWQ quant.
- **Cheap KV cache** — only 16 of 64 layers are full attention (64 KiB/token in BF16), so
  ~120K context fits next to the weights on 48 GB.
- **Tradeoffs** — a dense 27B decodes slower than a 3B-active MoE (MTP speculative decoding
  recovers much of that), and at its default `reasoning_effort=xhigh` it over-thinks badly
  (widely reported); the endpoint defaults to `low` instead.

**Architecture note (see root `CLAUDE.md`):** the checkpoint uses the
`Qwen3_5ForConditionalGeneration` wrapper that sank the Qwen3.5-9B deploy on `v2.25.1`
(vLLM 0.27.1). On `v2.27.0` (vLLM 0.29.0) with `--language-model-only` the weights load
and profile fine — the first attempt here failed only on memory (see below).

Previous models: `qtum/Qwen3-Coder-Next-AWQ` (to Sep 14 2026), before that
`QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ`.

## Live RunPod resources

- Endpoint id: `h8ins1a7nls350` (its RunPod display name is still `opencode-qwen3-32b`)
- Template id: `l9koa55i6j`
- **Serverless settings** (source of truth: `endpoint-scaling.json` in this directory;
  apply with `./scripts/deploy-fleet.sh scaling`):

  | Field | Value | Effect |
  |-------|-------|--------|
  | `workersMin` | `0` | Scale-to-zero — no GPU cost while idle |
  | `workersMax` | `1` | At most one worker |
  | `idleTimeout` | `600` | Worker shuts down 10 min after last request |
  | `scalerType` | `QUEUE_DELAY` | Scale up when queue delay exceeds threshold |
  | `scalerValue` | `4` | Queue-delay threshold (seconds) |
  | `flashboot` | `true` | Faster cold starts (no extra charge) |
  | `executionTimeoutMs` | `1800000` | 30 min per request — a 32K-token response from a dense 27B can exceed the old 10 min |

  First opencode request after idle triggers RunPod cold start automatically.
  No local wake scripts — scaling is configured in RunPod serverless endpoint settings.

  **What controls cost:** `workersMin=0` means no GPU billing while fully idle (no running
  workers). You are billed only during cold start, request execution, and the
  `idleTimeout` window after the last request. The REST API may also return
  `workersStandby` (often `1`); that field is not writable via REST PATCH and does not
  override `workersMin` — `workersMin` is the authoritative always-on setting.

- Managed via RunPod REST API (`https://rest.runpod.io/v1/...`); `deploy_coding_agent` in
  `scripts/deploy-fleet.sh` is the source of truth for the template. Env vars:
  - `MODEL_NAME=Qwen/Qwen3.8-27B-FP8` (no `QUANTIZATION` — FP8 is auto-detected)
  - `MAX_MODEL_LEN=122880`, `GPU_MEMORY_UTILIZATION=0.9`, `MAX_NUM_SEQS=8`
  - `ENABLE_AUTO_TOOL_CHOICE=true`, `TOOL_CALL_PARSER=qwen3_coder`, `REASONING_PARSER=qwen3`
  - `SPECULATIVE_CONFIG={"method": "mtp", "num_speculative_tokens": 3}` (MTP weights ship
    in the checkpoint)
  - `VLLM_EXTRA_ARGS=--language-model-only --default-chat-template-kwargs '{"reasoning_effort": "low"}'`
    — neither flag is in the worker's env-var allowlist, so they go through the raw
    passthrough (shlex-split by the worker)
  - `OPENAI_SERVED_MODEL_NAME_OVERRIDE=qwen3.8-27b`
  - No `ENFORCE_EAGER` — CUDA graphs stay on for decode speed.

  Image: `runpod/worker-v1-vllm:v2.27.0`, container disk 80 GB. GPU tier: 48 GB
  (`NVIDIA L40`/`L40S`/`RTX A6000`). Recover wedged queues with `./scripts/runpod-recover.sh`.

## `MAX_MODEL_LEN` is 122880, not 131072

The first deploy at `131072` crash-looped: each worker downloaded and loaded the model, then
died with a `startup_error` — "ran out of GPU memory during startup. vLLM estimates this GPU
can serve a context of about 128000 tokens" (weights + MTP draft + CUDA graphs leave room
for ~128K of KV cache). `122880` leaves ~4% margin.

That error never reaches the sync OpenAI route (it just hangs or fails fast). To read it,
submit an async job and poll its status — the text is in the job's `error` field:

```bash
curl -s -H "Authorization: Bearer $RUNPOD_API_KEY" -H 'Content-Type: application/json' \
  https://api.runpod.ai/v2/h8ins1a7nls350/run \
  -d '{"input":{"openai_route":"/v1/chat/completions","openai_input":{"model":"qwen3.8-27b","messages":[{"role":"user","content":"hi"}],"max_tokens":8}}}'
curl -s -H "Authorization: Bearer $RUNPOD_API_KEY" https://api.runpod.ai/v2/h8ins1a7nls350/status/<id>
```

## opencode wiring

Configured as the `runpod` provider in `~/.config/opencode/opencode.jsonc` (model id
`qwen3.8-27b`). Project defaults in `.opencode/opencode.json`.

Install/update (syncs API key file + validates health):

```bash
./scripts/setup-opencode.sh
```

**API key:** OpenCode uses `{file:~/.config/envman/RUNPOD.key}` — not `{env:RUNPOD_API_KEY}`.
GUI launches do not inherit shell env; without the key file you get `401 no token provided`.
See [`docs/opencode-setup.md`](../docs/opencode-setup.md).

`timeout`/`chunkTimeout` are 10min/3min to tolerate cold starts.

**Context budget:** `limit.context` (106496) must stay ≤ `MAX_MODEL_LEN − 16384`, and
`limit.output` stays 32768. opencode only compacts *after* a step crosses
`limit.context − 32000`, so the next request can overshoot by one step's tool output. With
the old `limit.context = MAX_MODEL_LEN = 65536`, that overshoot pushed prompt + `max_tokens`
past the endpoint's window: the session looped on empty responses and died with
`SSE read timed out` at ~33.5K prompt tokens. Details in
[`docs/opencode-setup.md`](../docs/opencode-setup.md#context-budget-limitcontext-must-stay-below-max_model_len);
guarded by `feature_context_budget` in `run_tests.sh`.

## Thinking and reasoning effort

- The chat template accepts `reasoning_effort` of `low`, `medium` or `xhigh` only. vLLM
  itself accepts `high`, but the template then raises and the request 400s — the opencode
  `high` variant is mapped to `xhigh` for that reason.
- vLLM's `qwen3` reasoning parser puts reasoning in `message.reasoning`, never `content`.
  opencode reads it and (via `interleaved.field: reasoning_content`) sends it back on later
  turns, which Qwen's `preserve_thinking` template expects.
- Exact-output probes (deploy smoke test, `runpod-recover.sh` warmup, most of
  `run_tests.sh`) send `chat_template_kwargs.enable_thinking=false` so `max_tokens` isn't
  spent reasoning.
- opencode sends no `temperature`/`top_p` for this model, so vLLM uses the checkpoint's
  `generation_config.json` (temp 1.0, top_p 0.95, top_k 20 — Qwen's recommended thinking-mode
  sampling). Verified by capturing opencode's request bodies against a local fake server.

## Cold-start-time vs context-window tradeoff

Each fresh worker downloads the 31 GB checkpoint (no network volume), then profiles the KV
cache and captures CUDA graphs — measured ~4.5 min from worker start to first served
request on the Sep 14 2026 deploy. If they're painful,
raise `idleTimeout` (keeps the worker warm longer after last use) — don't shrink
`limit.output` without re-testing large file writes. Only use `workersMin=1` (always-on,
~$1–1.75/hr) if you genuinely need sub-second first-token latency.

## Output-token ceiling truncates large tool calls

A `write` tool call for a large file can need several thousand output tokens. If the
model hits `max_tokens`/`limit.output` mid-argument, JSON never closes and opencode
reports "JSON parsing failed". Fixed by `limit.output=32768`; don't shrink without
re-testing multi-KB file writes end-to-end.

## Testing

```bash
export RUNPOD_API_KEY=<key>
./run_tests.sh
```

Covers endpoint availability, the thinking-model API contract (reasoning kept out of
`content`, structured tool calls), the worst-case context budget, and opencode end-to-end
(one-shot, file reading, agentic loop stability).

Or deploy + test everything:

```bash
export RUNPOD_API_KEY=<key>
./scripts/deploy-fleet.sh all
```
