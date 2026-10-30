# uncensored-coder

**Purpose**: Uncensored (abliterated) coding model — no refusals on security/pentest/grey-area
coding work. Smoke-tested only; there is no `run_tests.sh` suite yet.

## Current model

`huihui-ai/Huihui-Qwen3-Coder-30B-A3B-Instruct-abliterated` — abliterated Qwen3-Coder-30B-A3B
(`Qwen3MoeForCausalLM`, plain CausalLM, so none of the `*ForConditionalGeneration` risk in the
root `CLAUDE.md`). 3B active params = fast and cheap per token. No prebuilt AWQ/FP8 exists, so
vLLM quantizes bf16 -> FP8 on load (`QUANTIZATION=fp8`); fits a 48 GB card.

## Live RunPod resources

- Endpoint id: `1xk5onedx8j2fh` (`uncensored-coder-qwen3-30b-a3b`)
- Template id: `a9mhubs7pl` (`runpod/worker-v1-vllm:v2.27.0`, 100 GB container disk)
- Env: `MODEL_NAME` above, `QUANTIZATION=fp8`, `MAX_MODEL_LEN=65536`,
  `GPU_MEMORY_UTILIZATION=0.9`, `MAX_NUM_SEQS=8`, `ENABLE_AUTO_TOOL_CHOICE=true`,
  `TOOL_CALL_PARSER=qwen3_coder`, `OPENAI_SERVED_MODEL_NAME_OVERRIDE=qwen3-coder-30b-uncensored`
- GPUs: L40S / L40 / RTX A6000. Scale-to-zero (`endpoint-scaling.json`).

## Verified (Oct 2026)

- Cold start ~9.7 min including first-time 61 GB weight download; later cold starts are faster.
- `pong` smoke test passes; structured `tool_calls` returned; no refusal on a port-scanner prompt.
- Not yet verified: long-context behavior at 65536, agentic loops via opencode.

## Gotchas

- Abliteration removes refusals; add your own guardrails where needed.
- `~/.config/envman/RUNPOD.env` held a stale key (401) — `RUNPOD.key` was valid.
