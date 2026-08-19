#!/usr/bin/env bash
# Executable BDD step implementations for features/*.feature.
# Requires: RUNPOD_API_KEY exported, opencode + sqlite3 + python3 on PATH.
set -u

ENDPOINT_ID="h8ins1a7nls350"
BASE="https://api.runpod.ai/v2/${ENDPOINT_ID}"
OPENCODE_DB="$HOME/.local/share/opencode/opencode.db"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

require_key() {
  if [ -z "${RUNPOD_API_KEY:-}" ]; then
    echo "RUNPOD_API_KEY is not set in this shell. Export it first." >&2
    exit 1
  fi
}

# ---------- Feature: endpoint_availability ----------
feature_endpoint_availability() {
  echo "Feature: endpoint availability"

  health=$(curl -sS "${BASE}/health" -H "Authorization: Bearer $RUNPOD_API_KEY")
  echo "  (current health: $health)"

  start=$(date +%s)
  resp=$(curl -sS "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    -d '{"model":"qwen3-coder-30b","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":20}')
  elapsed=$(( $(date +%s) - start ))

  content=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message'].get('content') or '')" 2>/dev/null)

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
  echo "Feature: OpenAI API contract / thinking-mode override"

  resp=$(curl -sS "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    -d '{"model":"qwen3-coder-30b","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":20}')
  content=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin)['choices'][0]['message']; print((d.get('content') or '').strip())" 2>/dev/null)
  reasoning=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message'].get('reasoning'))" 2>/dev/null)
  ctoks=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['usage']['completion_tokens'])" 2>/dev/null)

  [ "$content" = "pong" ] && pass "Scenario: plain request returns content=pong" || fail "Scenario: plain request returns content=pong (got content='$content')"
  [ "$reasoning" = "None" ] && pass "Scenario: reasoning field is null" || fail "Scenario: reasoning field is null (got '$reasoning')"
  [ -n "$ctoks" ] && [ "$ctoks" -lt 10 ] && pass "Scenario: completion tokens < 10 (got $ctoks)" || fail "Scenario: completion tokens < 10 (got $ctoks)"

  # explicit re-enable attempt
  resp2=$(curl -sS "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    -d '{"model":"qwen3-coder-30b","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":50,"chat_template_kwargs":{"enable_thinking":true}}')
  content2=$(echo "$resp2" | python3 -c "import json,sys; d=json.load(sys.stdin)['choices'][0]['message']; print((d.get('content') or '').strip())" 2>/dev/null)
  has_think=$(echo "$resp2" | grep -c '<think>' || true)

  [ "$content2" = "pong" ] && pass "Scenario: explicit enable_thinking=true is ignored (content still pong)" || fail "Scenario: explicit enable_thinking=true is ignored (got content='$content2')"
  [ "$has_think" -eq 0 ] && pass "Scenario: no <think> leakage even when explicitly requested" || fail "Scenario: no <think> leakage even when explicitly requested (found $has_think occurrence(s))"
}

# ---------- Feature: opencode_integration ----------
feature_opencode_integration() {
  echo "Feature: opencode integration"

  models_out=$(opencode models runpod 2>&1)
  echo "$models_out" | grep -q "runpod/qwen3-coder-30b" \
    && pass "Scenario: opencode lists runpod/qwen3-coder-30b" \
    || fail "Scenario: opencode lists runpod/qwen3-coder-30b (got: $models_out)"

  run_out=$(opencode run --model runpod/qwen3-coder-30b "Write a one-line python function that adds two numbers. Just the code, no explanation." 2>&1)
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

  out=$(cd "$tmpdir" && opencode run --model runpod/qwen3-coder-30b "Read the file at exactly this path: $tmpdir/marker.py -- then quote its marker comment exactly." 2>&1)
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
  cd "$tmpdir" && opencode run --model runpod/qwen3-coder-30b \
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
echo "=== BDD regression suite: RunPod + opencode (Qwen3-Coder-30B) ==="
echo
feature_endpoint_availability; echo
feature_openai_api_contract; echo
feature_opencode_integration; echo
feature_repo_awareness; echo
feature_agentic_stability; echo

echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
