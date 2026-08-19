#!/usr/bin/env bash
# Executable BDD step implementations for features/*.feature.
# Requires: RUNPOD_API_KEY exported, python3 on PATH.
set -u

ENDPOINT_ID="0y3ptl2r9oachs"
BASE="https://api.runpod.ai/v2/${ENDPOINT_ID}"

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

# ---------- Feature: always_on_availability ----------
feature_always_on_availability() {
  echo "Feature: always-on availability"

  all_fast=true
  for i in 1 2 3; do
    start=$(date +%s)
    resp=$(curl -sS "${BASE}/openai/v1/chat/completions" \
      -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
      -d '{"model":"qwen3-8b-ha","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":20}')
    elapsed=$(( $(date +%s) - start ))
    content=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message'].get('content') or '')" 2>/dev/null)
    echo "  request $i: ${elapsed}s, content='$content'"
    if [ "$elapsed" -gt 5 ] || [ -z "$content" ]; then all_fast=false; fi
  done

  $all_fast && pass "Scenario: all 3 sequential requests completed under 5s (no cold start)" \
    || fail "Scenario: all 3 sequential requests completed under 5s (no cold start)"
}

# ---------- Feature: openai_api_contract ----------
feature_openai_api_contract() {
  echo "Feature: OpenAI API contract / thinking-mode override"

  resp=$(curl -sS "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    -d '{"model":"qwen3-8b-ha","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":20}')
  content=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin)['choices'][0]['message']; print((d.get('content') or '').strip())" 2>/dev/null)
  reasoning=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message'].get('reasoning'))" 2>/dev/null)
  ctoks=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['usage']['completion_tokens'])" 2>/dev/null)

  [ "$content" = "pong" ] && pass "Scenario: plain request returns content=pong" || fail "Scenario: plain request returns content=pong (got content='$content')"
  [ "$reasoning" = "None" ] && pass "Scenario: reasoning field is null" || fail "Scenario: reasoning field is null (got '$reasoning')"
  [ -n "$ctoks" ] && [ "$ctoks" -lt 10 ] && pass "Scenario: completion tokens < 10 (got $ctoks)" || fail "Scenario: completion tokens < 10 (got $ctoks)"

  resp2=$(curl -sS "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    -d '{"model":"qwen3-8b-ha","messages":[{"role":"user","content":"Reply with exactly: pong"}],"max_tokens":50,"chat_template_kwargs":{"enable_thinking":true}}')
  content2=$(echo "$resp2" | python3 -c "import json,sys; d=json.load(sys.stdin)['choices'][0]['message']; print((d.get('content') or '').strip())" 2>/dev/null)
  has_think=$(echo "$resp2" | grep -c '<think>' || true)

  [ "$content2" = "pong" ] && pass "Scenario: explicit enable_thinking=true is ignored (content still pong)" || fail "Scenario: explicit enable_thinking=true is ignored (got content='$content2')"
  [ "$has_think" -eq 0 ] && pass "Scenario: no <think> leakage even when explicitly requested" || fail "Scenario: no <think> leakage even when explicitly requested"
}

# ---------- Feature: tool_calling ----------
feature_tool_calling() {
  echo "Feature: Home Assistant style tool calling"

  req=$(python3 -c "
import json
tools = [{'type':'function','function':{'name':'HassTurnOn','description':'Turns on/opens a device or entity','parameters':{'type':'object','properties':{'name':{'type':'string'},'area':{'type':'string'}},'required':['name']}}}]
print(json.dumps({'model':'qwen3-8b-ha','messages':[{'role':'user','content':'Turn on the kitchen lights'}],'tools':tools,'tool_choice':'auto','max_tokens':200}))
")
  resp=$(curl -sS "${BASE}/openai/v1/chat/completions" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
    -d "$req")

  result=$(echo "$resp" | python3 -c "
import json,sys
d = json.load(sys.stdin)['choices'][0]['message']
tc = d.get('tool_calls') or []
if not tc:
    print('NO_TOOL_CALL')
else:
    fn = tc[0]['function']
    args = fn.get('arguments','').lower()
    ok = fn.get('name') == 'HassTurnOn' and ('kitchen' in args or 'light' in args)
    print('OK' if ok else 'WRONG:' + fn.get('name','') + ':' + args)
" 2>/dev/null)

  [ "$result" = "OK" ] && pass "Scenario: HassTurnOn called with correct arguments" \
    || fail "Scenario: HassTurnOn called with correct arguments (got: $result, raw: $resp)"
}

# ---------- run ----------
require_key
echo "=== BDD regression suite: RunPod + Home Assistant (Qwen3-8B) ==="
echo
feature_always_on_availability; echo
feature_openai_api_contract; echo
feature_tool_calling; echo

echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
