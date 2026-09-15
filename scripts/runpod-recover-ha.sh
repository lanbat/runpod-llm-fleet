#!/usr/bin/env bash
# Recover the Home Assistant RunPod endpoint when voice replies hang or time out.
# Symptom: health shows inProgress jobs stuck, or chat/completions never returns.
set -euo pipefail

ENDPOINT_ID="0y3ptl2r9oachs"
MODEL="qwen3-8b-ha"
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
  local h running ready initializing in_progress
  h=$(health)
  running=$(echo "$h" | jq -r '.workers.running // 0')
  ready=$(echo "$h" | jq -r '.workers.ready // 0')
  initializing=$(echo "$h" | jq -r '.workers.initializing // 0')
  in_progress=$(echo "$h" | jq -r '.jobs.inProgress // 0')
  # running/initializing without ready, or many stuck inProgress jobs — sync route hangs
  { [ "$ready" = "0" ] && { [ "$running" != "0" ] || [ "$initializing" != "0" ]; }; } \
    || [ "$in_progress" -gt 3 ]
}

wait_workers_cleared() {
  local attempt h running initializing
  for attempt in $(seq 1 12); do
    h=$(health)
    running=$(echo "$h" | jq -r '.workers.running // 0')
    initializing=$(echo "$h" | jq -r '.workers.initializing // 0')
    if [ "$running" = "0" ] && [ "$initializing" = "0" ]; then
      return 0
    fi
    echo "  waiting for workers to drain (running=$running initializing=$initializing)..."
    sleep 10
  done
  echo "  workers still present after drain wait" >&2
  return 1
}

cycle_workers() {
  local api="https://rest.runpod.io/v1/endpoints/${ENDPOINT_ID}"
  local scaling_file="$ROOT/models/home-assistant/endpoint-scaling.json"
  echo "Cycling workers (workersMax 0 → configured max)..."
  curl -sS -X PATCH "$api" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"workersMax":0}' >/dev/null
  wait_workers_cleared || true
  curl -sS -X PATCH "$api" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -c '.' "$scaling_file")" >/dev/null
}

warmup_sync() {
  local base="https://api.runpod.ai/v2/${ENDPOINT_ID}/openai/v1/chat/completions"
  local attempt resp content
  for attempt in $(seq 1 8); do
    echo "  warmup attempt $attempt..."
    resp=$(curl -sS --max-time 180 "$base" \
      -H "Authorization: Bearer $RUNPOD_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":10,\"chat_template_kwargs\":{\"enable_thinking\":false}}" 2>&1) || true
    content=$(echo "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
    if [ "$content" = "pong" ]; then
      echo "  warmup OK"
      return 0
    fi
    sleep 10
  done
  echo "  warmup FAILED (sync route still not responding)" >&2
  return 1
}

echo "=== RunPod recover (${ENDPOINT_ID}, Home Assistant LLM) ==="
require_key

echo "Before:"
health | jq -c '{ready:.workers.ready,running:.workers.running,inQueue:.jobs.inQueue,inProgress:.jobs.inProgress}'

echo "Purging pending jobs..."
purge=$(curl -sS -X POST "https://api.runpod.ai/v2/${ENDPOINT_ID}/purge-queue" \
  -H "Authorization: Bearer $RUNPOD_API_KEY")
echo "  $purge"

if is_wedged; then
  echo "Endpoint wedged — cycling capacity..."
  cycle_workers
fi

echo "Warming up..."
warmup_sync

echo "After:"
health | jq -c '{ready:.workers.ready,running:.workers.running,inQueue:.jobs.inQueue,inProgress:.jobs.inProgress}'
echo "Done. Restart Home Assistant if a satellite is stuck in processing:"
echo "  ssh admin@<server> sudo systemctl restart home-assistant"
