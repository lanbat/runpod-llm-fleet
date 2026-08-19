# coding-agent

**Purpose**: LLM backend for [opencode](https://opencode.ai), used as a coding assistant
in local repos.

## Current model

`QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` — a 4-bit AWQ quant of Alibaba's Qwen3-Coder
MoE (30B total / 3B active params). Chosen over a general-purpose model because it's
non-thinking by design (no reasoning/tool-call parser conflicts) and purpose-tuned for
agentic tool use. See the repo root `CLAUDE.md` for the full history of why this model
replaced an earlier dense Qwen3-32B, and the bugs that drove each config change.

## Live RunPod resources

- Endpoint id: `h8ins1a7nls350`
- Template id: `fr82sy7xka`
- Managed entirely via the RunPod REST API (`https://rest.runpod.io/v1/...`) — no
  Terraform/IaC. See `CLAUDE.md` for the full env var list needed to rebuild the template
  from scratch if it's ever deleted.

## opencode wiring

Configured as the `runpod` provider in `~/.config/opencode/opencode.jsonc` (model id
`qwen3-coder-30b`). That file lives outside this repo — see `CLAUDE.md`.

## Testing

```bash
export RUNPOD_API_KEY=<key>
./run_tests.sh
```

Runs the scenarios documented in `features/*.feature` end-to-end against the live
endpoint and the real `opencode` CLI (costs a small amount of RunPod GPU time). See the
repo root `CLAUDE.md` for command details and known gotchas.
