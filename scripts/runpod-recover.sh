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

is_wedged() {
  local h running ready
  h=$(health)
  running=$(echo "$h" | jq -r '.workers.running // 0')
  ready=$(echo "$h" | jq -r '.workers.ready // 0')
  # running:1 ready:0 with no idle worker — sync route hangs, jobs stay IN_QUEUE
  [ "$running" != "0" ] && [ "$ready" = "0" ]
}

cycle_workers() {
  local api="https://rest.runpod.io/v1/endpoints/${ENDPOINT_ID}"
  local scaling_file="$ROOT/models/coding-agent/endpoint-scaling.json"
  echo "Cycling workers (workersMax 0 → 1) to clear wedged pod..."
  curl -sS -X PATCH "$api" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"workersMax":0}' | jq -r '.workersMax // "patched"' | xargs -I{} echo "  workersMax={}"
  sleep 20
  curl -sS -X PATCH "$api" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -c '.' "$scaling_file")" | jq -r '.workersMax // "patched"' | xargs -I{} echo "  workersMax={}"
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

if is_wedged; then
  echo "Worker wedged (running>0, ready=0) — cycling capacity..."
  cycle_workers
fi

echo "Waiting for worker (cold start can take several minutes)..."
for i in $(seq 1 40); do
  h=$(health)
  ready=$(echo "$h" | jq -r '.workers.ready // 0')
  running=$(echo "$h" | jq -r '.workers.running // 0')
  idle=$(echo "$h" | jq -r '.workers.idle // 0')
  echo "  poll $i: ready=$ready running=$running idle=$idle"
  [ "$ready" != "0" ] || [ "$idle" != "0" ] && break
  if is_wedged && [ "$i" -eq 20 ]; then
    echo "  still wedged after 5 min — cycling workers again..."
    cycle_workers
  fi
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
