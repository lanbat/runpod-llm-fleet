# coding-agent

**Purpose**: LLM backend for [opencode](https://opencode.ai), used as a coding assistant
in local repos.

## Current model

`qtum/Qwen3-Coder-Next-AWQ` — 4-bit AWQ (compressed-tensors) quant of Alibaba's
Qwen3-Coder-Next MoE (80B total / ~3B active params). Selected Sep 2026 as the best
bang-for-buck coding model for this fleet:

- **Better quality than Qwen3-Coder-30B** — tops open SWE-bench Verified (~70%+) while
  keeping the same ~3B active-parameter cost profile (MoE).
- **Fits a single 48 GB GPU** (~40 GiB weights) — same L40/L40S/A6000 tier as before.
- **Non-thinking by design** — no reasoning/tool-call parser conflicts (unlike dense Qwen3).
- **Plain `Qwen3NextForCausalLM` architecture** — not the problematic
  `ForConditionalGeneration` wrapper that blocked Qwen3.5 deploys.

Previous model was `QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` (endpoint
`h8ins1a7nls350`).

## Live RunPod resources

- Endpoint id: `h8ins1a7nls350`
- Template id: `chssw8o8li`
- **Serverless scaling** (source of truth: `endpoint-scaling.json` in this directory;
  apply with `./scripts/deploy-fleet.sh scaling`):

  | Field | Value | Effect |
  |-------|-------|--------|
  | `workersMin` | `0` | Scale-to-zero — no GPU cost while idle |
  | `workersMax` | `1` | At most one worker |
  | `idleTimeout` | `600` | Worker shuts down 10 min after last request |
  | `scalerType` | `QUEUE_DELAY` | Scale up when queue delay exceeds threshold |
  | `scalerValue` | `4` | Queue-delay threshold (seconds) |

  First opencode request after idle triggers RunPod cold start automatically (1–5+ min).
  No local wake scripts — scaling is configured in RunPod serverless endpoint settings.

  **What controls cost:** `workersMin=0` means no GPU billing while fully idle (no running
  workers). You are billed only during cold start, request execution, and the
  `idleTimeout` window after the last request. The REST API may also return
  `workersStandby` (often `1`); that field is not writable via REST PATCH and does not
  override `workersMin` — `workersMin` is the authoritative always-on setting.

- Managed via RunPod REST API (`https://rest.runpod.io/v1/...`). Rebuild env vars:
  `MODEL_NAME=qtum/Qwen3-Coder-Next-AWQ`, no `QUANTIZATION` (auto-detects
  compressed-tensors), `MAX_MODEL_LEN=65536`, `GPU_MEMORY_UTILIZATION=0.9`,
  `ENFORCE_EAGER=true`, `ENABLE_AUTO_TOOL_CHOICE=true`,
  `TOOL_CALL_PARSER=qwen3_coder`, `OPENAI_SERVED_MODEL_NAME_OVERRIDE=qwen3-coder-next`.
  Image: `runpod/worker-v1-vllm:v2.27.0` (vLLM ≥0.15 required for `qwen3_next`).
  GPU tier: 48 GB (`NVIDIA L40`/`L40S`/`RTX A6000`). Recover wedged queues with
  `./scripts/runpod-recover.sh`.

## opencode wiring

Configured as the `runpod` provider in `~/.config/opencode/opencode.jsonc` (model id
`qwen3-coder-next`). Project defaults in `.opencode/opencode.json`.

Install/update (syncs API key file + validates health):

```bash
./scripts/setup-opencode.sh
```

**API key:** OpenCode uses `{file:~/.config/envman/RUNPOD.key}` — not `{env:RUNPOD_API_KEY}`.
GUI launches do not inherit shell env; without the key file you get `401 no token provided`.
See [`docs/opencode-setup.md`](../docs/opencode-setup.md).

`timeout`/`chunkTimeout` are 10min/3min to tolerate cold starts.
`limit.context` (65536) and `limit.output` (32768) must stay in sync with the
endpoint's `MAX_MODEL_LEN` — see the truncated-tool-call bug below.

## Cold-start-time vs context-window tradeoff

Raising `MAX_MODEL_LEN` slows cold starts (KV cache profiling at startup). Coder-Next
is ~40 GiB vs ~15 GiB for the old 30B quant, so expect longer cold starts than before.
`131072` is the compromise (half native 256K). If cold starts are painful, raise
`idleTimeout` (keeps the worker warm longer after last use) — don't shrink `limit.output`
without re-testing large file writes. Only use `workersMin=1` (always-on, ~$1–1.75/hr) if
you genuinely need sub-second first-token latency.

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

Or deploy + test everything:

```bash
export RUNPOD_API_KEY=<key>
./scripts/deploy-fleet.sh all
```
