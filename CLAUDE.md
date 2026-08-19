# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A fleet of RunPod-hosted LLMs, one per purpose — see the root `README.md` for the
current fleet table. Each `models/<purpose>/` directory is *not* an application — it's
the regression test suite for that purpose's RunPod-hosted LLM, plus a README covering
that model's specific config, endpoint/template IDs, and any bugs/gotchas specific to
it. The actual infrastructure (RunPod serverless endpoint + template) and any client
config (e.g. opencode's provider block, Home Assistant's `extended_openai_conversation`
settings) live outside this repo entirely — see each model's README for where.

This file only holds guidance that applies across the whole fleet. Purpose-specific
model choice, config, and bug history belongs in that model's own `README.md`, not
here.

## Commands

Run a model's regression suite from inside its directory (hits the live RunPod endpoint
— for `coding-agent` this also invokes the real `opencode` CLI. Either way it costs a
small amount of RunPod GPU time):

```bash
export RUNPOD_API_KEY=<key>
cd models/<purpose>
./run_tests.sh
```

Requires `curl`, `python3`, `sqlite3` on `PATH` (`coding-agent` additionally needs
`opencode`). There is no per-scenario runner — `run_tests.sh` runs every `feature_*`
function in sequence and prints a PASS/FAIL summary; to check a single feature, comment
out the other `feature_*` calls at the bottom of the script or copy the relevant
function's body into a shell.

Each model's `features/*.feature` files are documentation (Gherkin specs) describing the
same scenarios its `run_tests.sh` implements — there is no Cucumber/behave runner wired
up to them; `run_tests.sh` is the executable source of truth. The model id referenced in
both must match whatever's currently deployed — update both together if a model changes.

## `RUNPOD_API_KEY`

Expected to be exported in the user's `~/.zshrc` (used by opencode, any other client,
and every model's `run_tests.sh`).

## Before deploying a very recently released model (important, learned the hard way — twice)

Two separate attempts to deploy a bleeding-edge model with a `*ForConditionalGeneration`
wrapper architecture (a Gemma-4 model for `coding-agent`, then `Qwen3.5-9B` for
`home-assistant`) both failed to ever report healthy on our pinned
`runpod/worker-v1-vllm:v2.25.1` image — the Gemma one crash-looped outright; the
Qwen3.5 one cycled between `throttled` and a brief `initializing` without ever reaching
`ready`, even after broadening GPU type options (which ruled out plain capacity
shortage). Research turned up real, ongoing vLLM compatibility gaps for text-only
checkpoints loaded through these newer multimodal wrapper classes. Both times the fix
was the same: fall back to a same-size-class model using the plain, long-proven
`*ForCausalLM` architecture instead (Qwen3-Coder for coding-agent, Qwen3-8B for
home-assistant) — check a candidate model's `config.json` `architectures` field before
committing to a deploy; a `*ForConditionalGeneration` value is a real risk signal even
if the model is text-only.

**Cheap way to de-risk this going forward**: smoke-test any very-recently-released model
on a scale-to-zero endpoint first, even if the final deployment will be always-on
(`workersMin=1`) — `home-assistant`'s Qwen3.5 attempt burned real always-on GPU time
while stuck in this failure mode before the pivot.

## Debugging technique worth knowing

If a model is consumed via opencode, opencode stores every session/message/tool-call
locally in `~/.local/share/opencode/opencode.db` (SQLite; `session`, `message`, and
`part` tables, with `part.data` holding JSON for each tool call/text/reasoning/
step-finish chunk). This is the reliable way to diagnose agent misbehavior — querying
`part.data` for a session reveals exactly what tool was called with what arguments, what
errored, and the token counts of each step, which is far more informative than inferring
it from CLI output. See `models/coding-agent/README.md` for two real bugs (an
agentic tool-call loop, an output-token-ceiling truncation) diagnosed this way.

## Known test-environment gotchas (not product bugs)

- `mktemp -d` on macOS returns a symlinked path (`/var/folders/...`) that doesn't match
  opencode's internally-resolved canonical session directory
  (`/private/var/folders/...`), which makes opencode's `external_directory` permission
  check auto-reject file reads even inside the temp dir. Always canonicalize with
  `tmpdir=$(cd "$(mktemp -d)" && pwd -P)` before using a temp dir with opencode.
- macOS's BSD `date` does not support `%N` (milliseconds); use
  `python3 -c "import time; print(int(time.time()*1000))"` for millisecond timestamps
  instead of `date +%s%3N`.
- A model can occasionally guess a wrong absolute path (e.g. `/marker.py` instead of
  the real path) when given only a relative file reference — this is model behavior,
  not an opencode/RunPod bug. Test prompts give the full absolute path explicitly to
  keep suites deterministic.
- The RunPod sync route (`/openai/v1/chat/completions`) can spuriously hang/timeout on
  the very first request right after a worker reports "ready" — observed across
  multiple different endpoints/models now, so treat it as a general RunPod/vLLM
  behavior rather than something specific to one deployment. If a request seems stuck
  immediately after a cold start (or after an endpoint just came back from being
  paused), retry via the async route (`/run` + poll `/status/{id}`), or just retry the
  sync call once, before assuming something's actually broken.
