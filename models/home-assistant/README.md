# home-assistant

**Purpose**: Conversation-agent LLM backend for [Home Assistant](https://www.home-assistant.io/)
(smart home control via natural language — lights, thermostats, etc.).

## Current model

`Qwen/Qwen3-8B-AWQ` — official 4-bit AWQ quant of Qwen3-8B (original Qwen3 generation,
plain `Qwen3ForCausalLM` architecture). Deliberately **not** the newer Qwen3.5 line — see
"Why not Qwen3.5" below.

Chosen for this purpose because:
- Small and cheap to run — see "Scaling" below for why this ended up scale-to-zero
  rather than the always-on deployment originally planned.
- Reliable tool/function calling, verified against a simulated Home Assistant
  `HassTurnOn`-style tool call (correct entity name + area extracted, clean structured
  `tool_calls`, no reasoning leak).
- Warm latency measured at ~2s consistently once a worker is up.

## Scaling: reverted from always-on to scale-to-zero (cost)

Originally deployed with `workersMin=1` (always-on) specifically to eliminate
cold-start latency on voice commands. In practice, always-on at the GPU tier this
landed on (RTX 4090, ~$1.10/hr) works out to **~$792/month** if left running
continuously — checked via RunPod's actual live billing (`currentSpendPerHr`), not an
estimate. User decided that ongoing cost wasn't worth it and asked to stop it running
constantly, so this now matches `coding-agent`'s pattern: `workersMin=0`,
`idleTimeout=300` (5 min). Tradeoff accepted: the first voice command after 5+ min of
no use will hit a cold start (untested exactly how long for this model/GPU combo — likely
faster than `coding-agent`'s ~1-9min given the much smaller model and context window,
but confirm before relying on it). If cold starts turn out to be a real problem in
practice, the always-on config is simple to restore (`workersMin=1`) — just go in with
eyes open on the ~$800/mo cost this time.

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
- `workersMin=0`, `workersMax=1`, `idleTimeout=300` — scale-to-zero (see "Scaling"
  above for why this isn't always-on despite the original plan). gpuTypeIds includes
  RTX 4090/L40/L40S/RTX A6000 as fallbacks for availability.
- `MAX_MODEL_LEN=32768` — far more than HA needs (short turns + tool defs), but small
  enough that cold starts should stay reasonably fast for this model's size (confirm
  actual cold-start time — not yet measured post-revert).
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
