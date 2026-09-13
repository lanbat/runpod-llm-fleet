#!/usr/bin/env bash
# Validate opencode + RunPod provider wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="${HOME}/.config/envman/RUNPOD.key"
GLOBAL_CONFIG="${HOME}/.config/opencode/opencode.jsonc"
failures=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

echo "=== opencode validation ==="

if command -v opencode >/dev/null 2>&1; then
  pass "opencode CLI installed ($(opencode --version))"
else
  fail "opencode CLI not installed (npm install -g @opencode/cli)"
fi

if [ -f "$GLOBAL_CONFIG" ]; then
  pass "provider config exists ($GLOBAL_CONFIG)"
  if grep -q '{file:~/.config/envman/RUNPOD.key}' "$GLOBAL_CONFIG"; then
    pass "provider config uses file-based API key"
  else
    fail "provider config should use {file:~/.config/envman/RUNPOD.key} (not {env:...})"
  fi
else
  fail "provider config missing ($GLOBAL_CONFIG) — run scripts/setup-opencode.sh"
fi

GLOBAL_RUNTIME="${HOME}/.config/opencode/opencode.json"
if [ -f "$GLOBAL_RUNTIME" ]; then
  pass "global runtime config exists ($GLOBAL_RUNTIME)"
  if grep -q '"default_agent": "build"' "$GLOBAL_RUNTIME"; then
    pass "default agent is build (not plan)"
  else
    fail "default_agent should be build in $GLOBAL_RUNTIME"
  fi
  if grep -q '"disable": true' "$GLOBAL_RUNTIME" && grep -q '"plan"' "$GLOBAL_RUNTIME"; then
    pass "plan agent is disabled globally"
  else
    fail "plan agent should be disabled in $GLOBAL_RUNTIME"
  fi
  if opencode debug agent plan 2>&1 | grep -q "not found"; then
    pass "plan agent not loadable"
  else
    fail "plan agent is still enabled — prompts may hang in plan mode"
  fi
else
  fail "global runtime config missing ($GLOBAL_RUNTIME)"
fi

MONOREPO_CONFIG="/home/traph/projects/lanbat/.opencode/opencode.json"
if [ -f "$MONOREPO_CONFIG" ]; then
  pass "lanbat monorepo config exists ($MONOREPO_CONFIG)"
else
  fail "lanbat monorepo config missing ($MONOREPO_CONFIG)"
fi

if [ -f "$ROOT/.opencode/opencode.json" ]; then
  pass "project config exists ($ROOT/.opencode/opencode.json)"
  if grep -q '"mode": "subagent"' "$ROOT/.opencode/opencode.json"; then
    fail "default agent must not be a subagent — remove mode: subagent from build agent"
  else
    pass "project default agent is not a subagent"
  fi
else
  fail "project config missing ($ROOT/.opencode/opencode.json)"
fi

if [ -f "$KEY_FILE" ]; then
  perms=$(stat -c '%a' "$KEY_FILE" 2>/dev/null || stat -f '%OLp' "$KEY_FILE")
  if [ "$perms" = "600" ]; then
    pass "API key file exists with mode 600 ($KEY_FILE)"
  else
    fail "API key file should be mode 600 (got $perms): chmod 600 $KEY_FILE"
  fi
else
  fail "API key file missing ($KEY_FILE) — run scripts/sync-runpod-key.sh"
fi

if [ -f "$KEY_FILE" ]; then
  http_code=$(curl -sS -o /tmp/runpod-health.json -w '%{http_code}' --max-time 30 \
    "https://api.runpod.ai/v2/h8ins1a7nls350/health" \
    -H "Authorization: Bearer $(cat "$KEY_FILE")" || echo "000")
  if [ "$http_code" = "200" ]; then
    pass "RunPod health endpoint returns 200"
  elif [ "$http_code" = "401" ]; then
    fail "RunPod returned 401 Unauthorized — key file is empty or invalid"
  else
    fail "RunPod health check returned HTTP $http_code"
  fi
fi

if command -v opencode >/dev/null 2>&1; then
  if opencode models runpod 2>&1 | grep -q 'runpod/qwen3-coder-next'; then
    pass "opencode lists runpod/qwen3-coder-next"
  else
    fail "opencode does not list runpod/qwen3-coder-next"
  fi
fi

echo ""
if [ "$failures" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "$failures check(s) failed."
  exit 1
fi
