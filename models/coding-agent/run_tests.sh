#!/usr/bin/env bash
# Executable BDD step implementations for features/*.feature.
# Requires: RUNPOD_API_KEY (env or ~/.config/envman/RUNPOD.env), opencode key file,
# opencode + sqlite3 + python3 on PATH.
set -u

ENDPOINT_ID="h8ins1a7nls350"
BASE="https://api.runpod.ai/v2/${ENDPOINT_ID}"
MODEL="qwen3.8-27b"
OC_MODEL="runpod/${MODEL}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPENCODE_DB="$HOME/.local/share/opencode/opencode.db"
# Qwen3.8 thinks by default; exact-output probes turn it off so max_tokens isn't spent reasoning.
NO_THINK='"chat_template_kwargs":{"enable_thinking":false}'

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# chat <json body | @file> -> response body
chat() {
  curl -sS --max-time 900 "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    --data-binary "$1"
}

# jget <python expr over d (response) / m (first message)> -> value, empty on parse errors
jget() {
  python3 -c "import json,sys; d=json.load(sys.stdin); m=d['choices'][0]['message']; print($1)" 2>/dev/null
}

require_key() {
  if [ -z "${RUNPOD_API_KEY:-}" ] && [ -f "$HOME/.config/envman/RUNPOD.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/envman/RUNPOD.env"
  fi
  if [ -z "${RUNPOD_API_KEY:-}" ] && [ -f "$HOME/.config/envman/RUNPOD.key" ]; then
    RUNPOD_API_KEY="$(cat "$HOME/.config/envman/RUNPOD.key")"
  fi
  if [ -z "${RUNPOD_API_KEY:-}" ]; then
    echo "RUNPOD_API_KEY is not set. Export it or run ./scripts/sync-runpod-key.sh" >&2
    exit 1
  fi
}

require_opencode_key_file() {
  local key_file="$HOME/.config/envman/RUNPOD.key"
  if [ ! -f "$key_file" ]; then
    fail "Scenario: ~/.config/envman/RUNPOD.key missing (run ./scripts/sync-runpod-key.sh)"
    return 1
  fi
  local http_code
  http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
    "${BASE}/health" -H "Authorization: Bearer $(cat "$key_file")" || echo "000")
  if [ "$http_code" = "401" ]; then
    fail "Scenario: opencode key file returns 401 Unauthorized"
    return 1
  fi
  if [ "$http_code" != "200" ]; then
    fail "Scenario: RunPod health check returned HTTP $http_code"
    return 1
  fi
  pass "Scenario: opencode key file authenticates to RunPod (HTTP $http_code)"
}

# ---------- Feature: endpoint_availability ----------
feature_endpoint_availability() {
  echo "Feature: endpoint availability"

  health=$(curl -sS "${BASE}/health" -H "Authorization: Bearer $RUNPOD_API_KEY")
  echo "  (current health: $health)"

  start=$(date +%s)
  resp=$(chat "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":20,$NO_THINK}")
  elapsed=$(( $(date +%s) - start ))

  content=$(echo "$resp" | jget "m.get('content') or ''")

  if [ -n "$content" ]; then
    pass "Scenario: endpoint responds with content (took ${elapsed}s)"
  else
    fail "Scenario: endpoint responds with content (got: $resp)"
  fi

  if [ "$elapsed" -le 300 ]; then
    pass "Scenario: request (warm or cold) completed within 5 minutes (${elapsed}s)"
  else
    fail "Scenario: request completed within 5 minutes (took ${elapsed}s)"
  fi
}

# ---------- Feature: openai_api_contract ----------
feature_openai_api_contract() {
  echo "Feature: OpenAI API contract (thinking model)"

  resp=$(chat "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":20,$NO_THINK}")
  content=$(echo "$resp" | jget "(m.get('content') or '').strip()")
  reasoning=$(echo "$resp" | jget "m.get('reasoning') or m.get('reasoning_content')")
  ctoks=$(echo "$resp" | jget "d['usage']['completion_tokens']")

  [ "$content" = "pong" ] && pass "Scenario: thinking disabled -> content=pong" || fail "Scenario: thinking disabled -> content=pong (got content='$content')"
  [ "$reasoning" = "None" ] && pass "Scenario: thinking disabled -> reasoning field is null" || fail "Scenario: thinking disabled -> reasoning field is null (got '$reasoning')"
  [ -n "$ctoks" ] && [ "$ctoks" -lt 10 ] && pass "Scenario: thinking disabled -> completion tokens < 10 (got $ctoks)" || fail "Scenario: thinking disabled -> completion tokens < 10 (got $ctoks)"

  # Default request: the endpoint thinks (reasoning_effort defaults to low server-side).
  resp2=$(chat "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":4096}")
  content2=$(echo "$resp2" | jget "(m.get('content') or '').strip()")
  rlen=$(echo "$resp2" | jget "len(m.get('reasoning') or m.get('reasoning_content') or '')")
  ctoks2=$(echo "$resp2" | jget "d['usage']['completion_tokens']")

  echo "$content2" | grep -qi pong \
    && pass "Scenario: default request answers pong in content ($ctoks2 completion tokens)" \
    || fail "Scenario: default request answers pong in content (got: ${resp2:0:300})"
  [ -n "$rlen" ] && [ "$rlen" -gt 0 ] \
    && pass "Scenario: default request reasons in the separate reasoning field ($rlen chars)" \
    || fail "Scenario: default request reasons in the separate reasoning field (got '$rlen')"
  if [ -n "$content2" ] && ! echo "$content2" | grep -q '<think>'; then
    pass "Scenario: no <think> leakage into content"
  else
    fail "Scenario: no <think> leakage into content (content='${content2:0:200}')"
  fi

  tool_body=$(python3 -c '
import json, sys
print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": "What is the weather in Paris right now? Use the get_weather tool."}],
    "tools": [{"type": "function", "function": {
        "name": "get_weather", "description": "Get the current weather for a city",
        "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}],
    "tool_choice": "auto",
    "max_tokens": 4096,
}))' "$MODEL")
  resp3=$(chat "$tool_body")
  tool_ok=$(echo "$resp3" | python3 -c '
import json, sys
m = json.load(sys.stdin)["choices"][0]["message"]
calls = m.get("tool_calls") or []
ok = (bool(calls) and calls[0]["function"]["name"] == "get_weather"
      and "paris" in json.loads(calls[0]["function"]["arguments"]).get("city", "").lower()
      and "<tool_call>" not in (m.get("content") or ""))
print("yes" if ok else "no")' 2>/dev/null)
  [ "$tool_ok" = "yes" ] \
    && pass "Scenario: tool request returns structured get_weather(city=Paris) tool_calls" \
    || fail "Scenario: tool request returns structured get_weather(city=Paris) tool_calls (got: ${resp3:0:400})"
}

# ---------- Feature: context_budget ----------
feature_context_budget() {
  echo "Feature: context budget"

  limits=$(python3 -c '
import json, re, sys
cfg = json.loads(re.sub(r"^\s*//.*$", "", open(sys.argv[1]).read(), flags=re.M))
lim = cfg["provider"]["runpod"]["models"][sys.argv[2]]["limit"]
print(lim["context"], lim["output"])' "$ROOT/opencode-config.jsonc" "$MODEL" 2>/dev/null)
  read -r ctx out <<<"$limits"
  if [ -z "${out:-}" ]; then
    fail "Scenario: read limit.context/limit.output from opencode-config.jsonc"
    return
  fi

  # Mirrors opencode: max_tokens = min(limit.output, 32000), and compaction only kicks in
  # after the prompt passes limit.context - max_tokens, so the next request can overshoot by
  # one step's tool output (tool_output.max_bytes 32768 ~= 10K tokens).
  max_out=$(( out < 32000 ? out : 32000 ))
  prompt_tokens=$(( ctx - max_out + 10000 ))
  req=$(mktemp)
  python3 -c '
import json, sys
print(json.dumps({
    "model": sys.argv[1], "max_tokens": int(sys.argv[3]), "temperature": 0,
    "chat_template_kwargs": {"enable_thinking": False},
    "messages": [{"role": "user",
                  "content": " hello" * int(sys.argv[2]) + "\n\nIgnore the text above. Reply with exactly: ok"}],
}))' "$MODEL" "$prompt_tokens" "$max_out" > "$req"

  start=$(date +%s)
  resp=$(chat "@$req")
  elapsed=$(( $(date +%s) - start ))
  rm -f "$req"
  content=$(echo "$resp" | jget "(m.get('content') or '').strip()")
  ptoks=$(echo "$resp" | jget "d['usage']['prompt_tokens']")

  if [ -n "$content" ]; then
    pass "Scenario: worst-case opencode request ($ptoks prompt + $max_out max_tokens) is accepted (${elapsed}s)"
  else
    fail "Scenario: worst-case opencode request (~$prompt_tokens prompt + $max_out max_tokens) is accepted (got: ${resp:0:300})"
  fi
}

# ---------- Feature: opencode_integration ----------
feature_opencode_integration() {
  echo "Feature: opencode integration"

  require_opencode_key_file || return

  models_out=$(opencode models runpod 2>&1)
  echo "$models_out" | grep -q "$OC_MODEL" \
    && pass "Scenario: opencode lists $OC_MODEL" \
    || fail "Scenario: opencode lists $OC_MODEL (got: $models_out)"

  run_out=$(opencode run --model "$OC_MODEL" "Write a one-line python function that adds two numbers. Just the code, no explanation." 2>&1)
  rc=$?
  if [ $rc -eq 0 ] && echo "$run_out" | grep -Eq "def |lambda"; then
    pass "Scenario: opencode one-shot prompt succeeds and returns python code"
  else
    fail "Scenario: opencode one-shot prompt succeeds and returns python code (rc=$rc, out: $run_out)"
  fi
}

# ---------- Feature: repo_awareness ----------
feature_repo_awareness() {
  echo "Feature: repo awareness"

  tmpdir=$(cd "$(mktemp -d)" && pwd -P)
  marker="UNIQUE_MARKER_$(date +%s)_$$"
  printf '# %s\ndef compute_total(items):\n    return sum(item.price for item in items)\n' "$marker" > "$tmpdir/marker.py"

  out=$(cd "$tmpdir" && opencode run --model "$OC_MODEL" "Read the file at exactly this path: $tmpdir/marker.py -- then quote its marker comment exactly." 2>&1)
  rm -rf "$tmpdir"

  echo "$out" | grep -q "$marker" \
    && pass "Scenario: opencode reads the file and quotes the exact marker" \
    || fail "Scenario: opencode reads the file and quotes the exact marker (got: $out)"
}

# ---------- Feature: agentic_stability ----------
feature_agentic_stability() {
  echo "Feature: agentic loop stability"

  if [ ! -f "$OPENCODE_DB" ]; then
    fail "Scenario: opencode session db found at $OPENCODE_DB"
    return
  fi

  tmpdir=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$tmpdir/a" "$tmpdir/b"
  printf 'value_a = 1\n' > "$tmpdir/a/config.txt"
  printf 'value_b = 2\n' > "$tmpdir/b/config.txt"

  before_ts=$(python3 -c "import time; print(int(time.time()*1000))")
  cd "$tmpdir" && opencode run --model "$OC_MODEL" \
    "Read exactly these two files and tell me both values: $tmpdir/a/config.txt and $tmpdir/b/config.txt" > /tmp/agentic_stability_out.txt 2>&1
  cd - > /dev/null
  rm -rf "$tmpdir"

  session_id=$(sqlite3 -readonly "$OPENCODE_DB" \
    "SELECT id FROM session WHERE time_updated >= $before_ts ORDER BY time_updated ASC LIMIT 1;" 2>/dev/null)

  if [ -z "$session_id" ]; then
    fail "Scenario: located the test session in opencode's db"
    return
  fi

  sqlite3 -readonly "$OPENCODE_DB" "SELECT data FROM part WHERE session_id = '$session_id' ORDER BY time_created ASC;" \
    > /tmp/agentic_stability_parts.txt 2>/dev/null

  result=$(python3 -c "
import json
lines = open('/tmp/agentic_stability_parts.txt').readlines()
from collections import Counter
calls = Counter()
think_leaks = 0
for line in lines:
    if not line.strip(): continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get('type') == 'tool':
        state = d.get('state', {})
        key = (d.get('tool'), json.dumps(state.get('input'), sort_keys=True))
        calls[key] += 1
    elif d.get('type') == 'text':
        if '<think>' in (d.get('text') or ''):
            think_leaks += 1
max_repeat = max(calls.values()) if calls else 0
print(f'{max_repeat} {think_leaks}')
")
  max_repeat=$(echo "$result" | cut -d' ' -f1)
  think_leaks=$(echo "$result" | cut -d' ' -f2)

  [ "$max_repeat" -le 3 ] \
    && pass "Scenario: no (tool, input) pair repeated more than 3 times (max was $max_repeat)" \
    || fail "Scenario: no (tool, input) pair repeated more than 3 times (max was $max_repeat)"

  [ "$think_leaks" -eq 0 ] \
    && pass "Scenario: no raw <think> tags leaked into assistant text" \
    || fail "Scenario: no raw <think> tags leaked into assistant text ($think_leaks leaked part(s))"
}

# ---------- run ----------
require_key
echo "=== BDD regression suite: RunPod + opencode (Qwen3.8-27B) ==="
echo
feature_endpoint_availability; echo
feature_openai_api_contract; echo
feature_context_budget; echo
feature_opencode_integration; echo
feature_repo_awareness; echo
feature_agentic_stability; echo

echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
