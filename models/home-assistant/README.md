# home-assistant

**Purpose**: Conversation-agent LLM backend for [Home Assistant](https://www.home-assistant.io/)
(smart home control via natural language — lights, thermostats, etc.).

## Current model

`Qwen/Qwen3-8B-AWQ` — official 4-bit AWQ quant of Qwen3-8B (original Qwen3 generation,
plain `Qwen3ForCausalLM` architecture). Deliberately **not** the newer Qwen3.5 line — see
"Why not Qwen3.5" below.

Chosen for this purpose because:
- Small enough to be cheap to run **always-on** (no cold-start latency), which matters
  far more here than for `coding-agent`: HA is often driven by voice commands where a
  user is waiting for a spoken reply.
- Reliable tool/function calling, verified against a simulated Home Assistant
  `HassTurnOn`-style tool call (correct entity name + area extracted, clean structured
  `tool_calls`, no reasoning leak).
- Warm latency measured at ~2s consistently — see Verification below.

## Why not Qwen3.5 (the originally planned model)

The plan called for `Qwen3.5-9B` as the primary pick. That model uses a newer
`Qwen3_5ForConditionalGeneration` (multimodal wrapper) architecture, and deploying it
here hit the exact same failure class as an earlier abandoned attempt at a Gemma-4
model on `coding-agent`: the worker never reported healthy — stuck cycling between
`throttled` and a brief `initializing` before failing, even after broadening GPU type
options (which ruled out plain capacity shortage as the cause). Research turned up real,
ongoing reports of vLLM having gaps specifically for **text-only** Qwen3.5 checkpoints
loaded through the multimodal `ForConditionalGeneration` class. Rather than keep
debugging a bleeding-edge architecture on always-on (continuously billing) GPU time,
this deployment uses Qwen3-8B instead — same size class, same non-thinking-mode fix
pattern (see below), plain `CausalLM` architecture with no such compatibility risk.

**Lesson for next time**: before committing to an always-on deployment of a very
recently released model, do a cheap scale-to-zero smoke test first (like
`coding-agent`'s pattern) to catch architecture-compatibility issues without paying for
idle always-on GPU time while debugging.

## The thinking-mode fix (same bug class as coding-agent, pre-empted this time)

Qwen3-8B's chat template defaults "thinking" mode to **on** — the same issue
extensively diagnosed on `coding-agent`'s original Qwen3-32B deployment (see the root
`CLAUDE.md`). Applied the known fix from day one instead of waiting to hit it in
production: `CUSTOM_CHAT_TEMPLATE` patched so the closing `<think></think>` block is
inserted unconditionally, and `REASONING_PARSER` is intentionally not set. Verified: a
plain request returns `content: "pong"` / `reasoning: null` with only 2 completion
tokens (no thinking overhead).

## Live RunPod resources

- Endpoint id: `0y3ptl2r9oachs`
- Template id: `xacv4b30xt`
- `workersMin=1`, `workersMax=1` — **always-on**, unlike `coding-agent`'s scale-to-zero.
  Costs continuously (check current RunPod pricing for the GPU tier actually allocated —
  gpuTypeIds includes RTX 4090/L40/L40S/RTX A6000 as fallbacks for availability).
- `MAX_MODEL_LEN=32768` — far more than HA needs (short turns + tool defs), but avoids
  the long cold-start problem seen at very large context windows on `coding-agent`
  (moot here anyway since this never scales to zero).
- `TOOL_CALL_PARSER=hermes` (plain JSON tool calls — this model's native format, unlike
  `coding-agent`'s Qwen3-Coder which uses the `qwen3_coder` XML-style parser).

## Home Assistant side (not done by this repo — hand this to HA)

Home Assistant's *native* "OpenAI Conversation" integration now targets OpenAI's
Responses API, which self-hosted OpenAI-compatible servers (including this one) don't
implement. Use the **`extended_openai_conversation`** HACS custom component instead
(github.com/jekalmin/extended_openai_conversation) — it has an explicit Base URL field
for any `/v1/chat/completions`-compatible server:

- Base URL: `https://api.runpod.ai/v2/0y3ptl2r9oachs/openai/v1`
- API key: your `RUNPOD_API_KEY`
- Model: `qwen3-8b-ha`

If the component exposes a "thinking"/reasoning toggle, it doesn't matter which way
it's set — the server-side template patch forces thinking off unconditionally
regardless of what the client sends (verified: explicitly requesting
`chat_template_kwargs.enable_thinking: true` is still ignored, same as the coding-agent
model — reran that same check here before shipping).

## Testing

```bash
export RUNPOD_API_KEY=<key>
./run_tests.sh
```
