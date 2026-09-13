#!/usr/bin/env bash
# Recover a wedged RunPod coding endpoint + local opencode state.
# Symptom: health shows running:1 but inQueue grows; opencode hangs with no response.
set -euo pipefail

ENDPOINT_ID="h8ins1a7nls350"
MODEL="qwen3-coder-next"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

require_key() {
  if [ -z "${RUNPOD_API_KEY:-}" ]; then
    if [ -f "$HOME/.config/envman/RUNPOD.env" ]; then
      # shellcheck disable=SC1091
      source "$HOME/.config/envman/RUNPOD.env"
    fi
  fi
  if [ -z "${RUNPOD_API_KEY:-}" ] && [ -f "$HOME/.config/envman/RUNPOD.key" ]; then
    RUNPOD_API_KEY="$(cat "$HOME/.config/envman/RUNPOD.key")"
  fi
  if [ -z "${RUNPOD_API_KEY:-}" ]; then
    echo "RUNPOD_API_KEY not set" >&2
    exit 1
  fi
}

health() {
  curl -sS --max-time 15 "https://api.runpod.ai/v2/${ENDPOINT_ID}/health" \
    -H "Authorization: Bearer $RUNPOD_API_KEY"
}

warmup_sync() {
  local base="https://api.runpod.ai/v2/${ENDPOINT_ID}/openai/v1/chat/completions"
  local attempt resp content
  for attempt in $(seq 1 8); do
    echo "  warmup attempt $attempt..."
    resp=$(curl -sS --max-time 90 "$base" \
      -H "Authorization: Bearer $RUNPOD_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":10}" 2>&1) || true
    content=$(echo "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
    if [ "$content" = "pong" ]; then
      echo "  warmup OK"
      return 0
    fi
    sleep 5
  done
  echo "  warmup FAILED (sync route still not responding)" >&2
  return 1
}

echo "=== RunPod recover (${ENDPOINT_ID}) ==="
require_key

echo "Stopping local opencode processes (prevents queue refill)..."
pkill -f '^opencode( |$)' 2>/dev/null || true
sleep 1

echo "Purging pending jobs..."
purge=$(curl -sS -X POST "https://api.runpod.ai/v2/${ENDPOINT_ID}/purge-queue" \
  -H "Authorization: Bearer $RUNPOD_API_KEY")
echo "  $purge"

echo "Waiting for ready worker..."
for i in $(seq 1 30); do
  ready=$(health | jq -r '.workers.ready // 0')
  echo "  poll $i: ready=$ready"
  [ "$ready" != "0" ] && break
  sleep 15
done

echo "Warming sync route (first requests after ready often hang)..."
if warmup_sync; then
  echo "Recovery complete."
  "$ROOT/scripts/validate-opencode.sh"
  echo "Start opencode: cd <project> && opencode"
  exit 0
fi

echo "Endpoint still broken — redeploying coding-agent template..."
"$ROOT/scripts/deploy-fleet.sh" coding
"$ROOT/scripts/validate-opencode.sh"
