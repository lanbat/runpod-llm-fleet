# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A fleet of RunPod-hosted LLMs, one per purpose — see the root `README.md` for the
current fleet table. Each `models/<purpose>/` directory is *not* an application — it's
the regression test suite for that purpose's RunPod-hosted LLM. The actual
infrastructure (RunPod serverless endpoint + template) and any client config (e.g.
opencode's provider block) live outside this repo (see "Where the real config lives"
below); each model directory only contains the BDD specs and the script that exercises
them end-to-end against its live endpoint.

Right now there is exactly one purpose deployed — `models/coding-agent` (a coding-agent
backend for [opencode](https://opencode.ai)) — so the model-specific content below lives
in this root file rather than split out. If a second purpose is added, consider moving
purpose-specific bugs/gotchas into that model's own directory and keeping only
cross-cutting guidance (RunPod REST API patterns, the debugging technique, general
tradeoffs) here.

## Commands

Run a model's regression suite from inside its directory (hits the live RunPod endpoint
and invokes the real `opencode` CLI — this costs a small amount of RunPod GPU time):

```bash
export RUNPOD_API_KEY=<key>
cd models/coding-agent
./run_tests.sh
```

Requires `curl`, `python3`, `sqlite3`, and `opencode` on `PATH`. There is no per-scenario
runner — `run_tests.sh` runs every `feature_*` function in sequence and prints a
PASS/FAIL summary; to check a single feature, comment out the other `feature_*` calls
at the bottom of the script or copy the relevant function's body into a shell.

Each model's `features/*.feature` files are documentation (Gherkin specs) describing the
same scenarios its `run_tests.sh` implements — there is no Cucumber/behave runner wired
up to them; `run_tests.sh` is the executable source of truth. The model id referenced in
both (`qwen3-coder-30b`) must match whatever's currently deployed — update both together
if the model changes again.

## Where the real config lives (not in this repo)

- **RunPod serverless endpoint**: id `h8ins1a7nls350`, built from template id
  `fr82sy7xka` (image `runpod/worker-v1-vllm:v2.25.1`, model
  `QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` — a 4-bit AWQ quant of Alibaba's
  Qwen3-Coder MoE, 30B total/3B active params). Both only exist as live RunPod
  resources managed via `https://rest.runpod.io/v1/{templates,endpoints}` — there is no
  Terraform/IaC file for them anywhere. If the endpoint needs to be rebuilt, the required
  env vars are: `MODEL_NAME=QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ`,
  `QUANTIZATION=awq`, `MAX_MODEL_LEN=262144` (full native context — see cold-start
  tradeoff below), `GPU_MEMORY_UTILIZATION=0.9`, `ENFORCE_EAGER=true`,
  `ENABLE_AUTO_TOOL_CHOICE=true`, `TOOL_CALL_PARSER=qwen3_coder`,
  `OPENAI_SERVED_MODEL_NAME_OVERRIDE=qwen3-coder-30b`. No `CUSTOM_CHAT_TEMPLATE` and no
  `REASONING_PARSER` — this model only supports non-thinking mode natively, so none of
  the thinking/reasoning-parser workarounds that an earlier Qwen3-32B (dense) deployment
  needed apply here. GPU tier is 48GB (`NVIDIA L40`/`L40S`/`RTX A6000`); `idleTimeout` is
  600s so the worker stays warm between messages in an active session but scales to zero
  (no cost) after 10 min idle.

- **opencode provider config**: `~/.config/opencode/opencode.jsonc`, a `runpod`
  provider (`@ai-sdk/openai-compatible`) pointing at
  `https://api.runpod.ai/v2/h8ins1a7nls350/openai/v1`, model id `qwen3-coder-30b`. API
  key via `{env:RUNPOD_API_KEY}`. `timeout`/`chunkTimeout` are set generously
  (10min/3min) to tolerate a cold start without opencode aborting the request.
  `limit.context` (262144) and `limit.output` (32768) must stay in sync with the
  endpoint's `MAX_MODEL_LEN` — see the truncated-tool-call bug below for why both matter.

- **`RUNPOD_API_KEY`**: expected to be exported in the user's `~/.zshrc` (used by both
  opencode and `run_tests.sh`).

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
`step-finish` part right before the failure in opencode's session db (see below) — if
`tokens.output` exactly equals the configured limit, that's the signature. Fixed here by
raising both the endpoint's `MAX_MODEL_LEN` and opencode's `limit.output` well above what
a large single write plausibly needs (see `MAX_MODEL_LEN=262144` /
`limit.output=32768` above); don't shrink either without re-testing an actual multi-KB
file write end-to-end (not just `run_tests.sh`'s short-prompt scenarios, which won't
catch this).

## Debugging technique worth knowing

opencode stores every session/message/tool-call locally in
`~/.local/share/opencode/opencode.db` (SQLite; `session`, `message`, and `part` tables,
with `part.data` holding JSON for each tool call/text/reasoning/step-finish chunk). This
is the reliable way to diagnose agent misbehavior — querying `part.data` for a session
reveals exactly what tool was called with what arguments, what errored, and the token
counts of each step, which is far more informative than inferring it from CLI output.
`feature_agentic_stability` in `run_tests.sh` automates the tool-call-repetition check;
the output-token-ceiling bug above was diagnosed the same way (by hand).

## Fixed but worth knowing: Qwen3-32B (dense) thinking-mode bug

An earlier deployment used dense `Qwen3-32B-AWQ` instead of the current Coder model.
That model defaults its "thinking" mode to **on**, which caused reasoning+tool-call
parser interaction bugs (tool calls landing as raw text instead of structured
`tool_calls`, leaked `<think>...</think>` text making the model restart its reasoning
from scratch every turn) — this produced an infinite ping-pong between the same two
files in one real agentic session. The fix at the time was a `CUSTOM_CHAT_TEMPLATE` that
force-inserted a closed `<think></think>` block unconditionally. This no longer applies
to the current Qwen3-Coder deployment (non-thinking by design), but if a future model
swap reintroduces a hybrid-thinking model, expect to need the same class of fix — check
git/conversation history for the exact template patch before reinventing it.

## Known test-environment gotchas (not product bugs)

- `mktemp -d` on macOS returns a symlinked path (`/var/folders/...`) that doesn't match
  opencode's internally-resolved canonical session directory
  (`/private/var/folders/...`), which makes opencode's `external_directory` permission
  check auto-reject file reads even inside the temp dir. Always canonicalize with
  `tmpdir=$(cd "$(mktemp -d)" && pwd -P)` before using a temp dir with opencode.
- macOS's BSD `date` does not support `%N` (milliseconds); use
  `python3 -c "import time; print(int(time.time()*1000))"` for millisecond timestamps
  instead of `date +%s%3N`.
- The model occasionally guesses a wrong absolute path (e.g. `/marker.py` instead of
  the real path) when given only a relative file reference — this is model behavior,
  not an opencode/RunPod bug. Test prompts give the full absolute path explicitly to
  keep the suite deterministic.
- The RunPod sync route (`/openai/v1/chat/completions`) can spuriously hang/timeout on
  the very first request right after a worker reports "ready" (observed twice, both
  resolved within a minute). If a request seems stuck immediately after a cold start,
  retry via the async route (`/run` + poll `/status/{id}`) before assuming something's
  actually broken.
