# runpod-llm-fleet

Configuration and regression tests for LLMs self-hosted on [RunPod](https://runpod.io)
serverless, one per purpose. Each model lives in its own directory under `models/` with
its own README, its own RunPod endpoint/template, and its own test suite — models can be
swapped out independently without affecting other purposes.

## Fleet

| Purpose | Directory | Current model | Consumer | Scaling |
|---|---|---|---|---|
| Coding assistant backend | [`models/coding-agent`](models/coding-agent) | Qwen3-Coder-30B-A3B-Instruct (AWQ) | [opencode](https://opencode.ai) | Scale-to-zero |
| Home Assistant conversation agent | [`models/home-assistant`](models/home-assistant) | Qwen3-8B (AWQ) | [Home Assistant](https://www.home-assistant.io/) via `extended_openai_conversation` | Always-on (low-latency voice) |

## Adding a new purpose

1. `mkdir -p models/<purpose-name>` and copy the structure of an existing model
   directory (`README.md`, `run_tests.sh`, `features/*.feature`) as a starting point.
2. Create the RunPod template + serverless endpoint for it (see an existing model's
   README for the REST API calls used) — keep it as its own template/endpoint, don't
   reuse another purpose's.
3. Wire up whatever client consumes it (a new provider block in `opencode.jsonc`, or
   whatever else), and add that model's row to the fleet table above.
4. See the root `CLAUDE.md` for infra-level gotchas that apply across the whole fleet
   (RunPod REST API patterns, cold-start/context-window tradeoffs, debugging technique
   for agent tool-calling issues via opencode's local session db, etc.) before deploying
   a new one — several were expensive to discover the first time.

## Requirements

`curl`, `python3`, `sqlite3` on `PATH` for the test suites; a `RUNPOD_API_KEY` exported
in your shell (also expected in `~/.zshrc` for opencode itself to read).
