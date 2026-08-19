# coding-agent

**Purpose**: LLM backend for [opencode](https://opencode.ai), used as a coding assistant
in local repos.

## Current model

`QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` — a 4-bit AWQ quant of Alibaba's Qwen3-Coder
MoE (30B total / 3B active params). Chosen over a general-purpose model because it's
non-thinking by design (no reasoning/tool-call parser conflicts) and purpose-tuned for
agentic tool use.

## Live RunPod resources

- Endpoint id: `h8ins1a7nls350`
- Template id: `fr82sy7xka`
- Managed entirely via the RunPod REST API (`https://rest.runpod.io/v1/...`) — no
  Terraform/IaC. If the endpoint needs to be rebuilt, the required env vars are:
  `MODEL_NAME=QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ`, `QUANTIZATION=awq`,
  `MAX_MODEL_LEN=262144` (full native context — see cold-start tradeoff below),
  `GPU_MEMORY_UTILIZATION=0.9`, `ENFORCE_EAGER=true`, `ENABLE_AUTO_TOOL_CHOICE=true`,
  `TOOL_CALL_PARSER=qwen3_coder`, `OPENAI_SERVED_MODEL_NAME_OVERRIDE=qwen3-coder-30b`.
  No `CUSTOM_CHAT_TEMPLATE` and no `REASONING_PARSER` — this model only supports
  non-thinking mode natively, so none of the thinking/reasoning-parser workarounds that
  the earlier Qwen3-32B (dense) deployment needed apply here. GPU tier is 48GB
  (`NVIDIA L40`/`L40S`/`RTX A6000`); `idleTimeout` is 600s so the worker stays warm
  between messages in an active session but scales to zero (no cost) after 10 min idle
  (scale-to-zero was chosen here because usage is bursty/occasional — contrast with
  `models/home-assistant`, which is always-on because it's latency-critical).

## opencode wiring

Configured as the `runpod` provider in `~/.config/opencode/opencode.jsonc` (model id
`qwen3-coder-30b`, outside this repo). `timeout`/`chunkTimeout` are set generously
(10min/3min) to tolerate a cold start without opencode aborting the request.
`limit.context` (262144) and `limit.output` (32768) must stay in sync with the
endpoint's `MAX_MODEL_LEN` — see the truncated-tool-call bug below for why both matter.

## Cold-start-time vs context-window tradeoff (important, non-obvious)

Raising `MAX_MODEL_LEN` makes vLLM profile/allocate KV cache for the full window at
startup, which directly slows cold starts: 32768 → ~1-2min cold start, 131072 → similar,
262144 → **~8-9 minutes**. Combined with `idleTimeout=600` (10 min), a worker that goes
idle just past that mark pays the full ~9min cold start again on the next message. If
cold-start latency becomes annoying, the lever to pull is `idleTimeout` (raise it) or
`workersMin=1` (always-on, ~$1-1.75/hr continuously) — not shrinking `MAX_MODEL_LEN`,
since that reintroduces the truncation bug below.

## Output-token ceiling truncates large tool calls (important, non-obvious)

A `write` tool call for a genuinely large file (e.g. a few-hundred-line script) can need
several thousand output tokens for the `content` argument alone. If the model hits
`max_tokens`/`limit.output` mid-argument, the JSON never closes ("Unterminated string"),
opencode reports "JSON parsing failed", and the file is never actually written — but the
model, faced with repeated failures, will confidently claim success anyway rather than
admit it couldn't write the file. This is not a parser bug: confirm by checking the
`step-finish` part right before the failure in opencode's session db (see root
`CLAUDE.md` for the query technique) — if `tokens.output` exactly equals the configured
limit, that's the signature. Fixed here by raising both the endpoint's `MAX_MODEL_LEN`
and opencode's `limit.output` well above what a large single write plausibly needs (see
`MAX_MODEL_LEN=262144` / `limit.output=32768` above); don't shrink either without
re-testing an actual multi-KB file write end-to-end (not just `run_tests.sh`'s
short-prompt scenarios, which won't catch this).

## Fixed but worth knowing: Qwen3-32B (dense) thinking-mode bug

An earlier deployment used dense `Qwen3-32B-AWQ` instead of the current Coder model.
That model defaults its "thinking" mode to **on**, which caused reasoning+tool-call
parser interaction bugs (tool calls landing as raw text instead of structured
`tool_calls`, leaked `<think>...</think>` text making the model restart its reasoning
from scratch every turn) — this produced an infinite ping-pong between the same two
files in one real agentic session. The fix at the time was a `CUSTOM_CHAT_TEMPLATE` that
force-inserted a closed `<think></think>` block unconditionally. This no longer applies
to the current Qwen3-Coder deployment (non-thinking by design). `models/home-assistant`
hit the same bug class pre-emptively (fixed from day one instead of in production) —
see its README for the same fix applied to Qwen3-8B.

## Testing

```bash
export RUNPOD_API_KEY=<key>
./run_tests.sh
```

Runs the scenarios documented in `features/*.feature` end-to-end against the live
endpoint and the real `opencode` CLI (costs a small amount of RunPod GPU time). See the
repo root `CLAUDE.md` for cross-cutting command details, the SQLite debugging technique,
and known test-environment gotchas.
