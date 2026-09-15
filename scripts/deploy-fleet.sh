#!/usr/bin/env bash
# Deploy or refresh the RunPod LLM fleet templates/endpoints.
# Requires: RUNPOD_API_KEY, curl, jq
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="https://rest.runpod.io/v1"

CODING_ENDPOINT_ID="h8ins1a7nls350"
HA_ENDPOINT_ID="0y3ptl2r9oachs"

CODING_VLLM_IMAGE="runpod/worker-v1-vllm:v2.27.0"
HA_VLLM_IMAGE="runpod/worker-v1-vllm:v2.27.0"
GPU_TYPES='["NVIDIA L40", "NVIDIA L40S", "NVIDIA RTX A6000"]'

require_key() {
  if [ -z "${RUNPOD_API_KEY:-}" ]; then
    echo "RUNPOD_API_KEY is not set. Export it and re-run:" >&2
    echo '  export RUNPOD_API_KEY="..."' >&2
    exit 1
  fi
}

auth() {
  curl -sS -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" "$@"
}

create_template() {
  local name="$1"
  local env_json="$2"
  local image="${3:-$CODING_VLLM_IMAGE}"
  local disk_gb="${4:-50}"
  local resp
  resp=$(auth -X POST "$API/templates" -d "{
    \"name\": \"$name\",
    \"imageName\": \"$image\",
    \"isServerless\": true,
    \"containerDiskInGb\": $disk_gb,
    \"env\": $env_json
  }")
  if ! echo "$resp" | jq -e '.id' >/dev/null 2>&1; then
    echo "Template creation failed: $resp" >&2
    return 1
  fi
  echo "$resp" | jq -r '.id'
}

apply_endpoint_scaling() {
  local endpoint_id="$1"
  local scaling_file="$2"
  local patch
  patch=$(jq -c --arg id "$endpoint_id" '.' "$scaling_file")
  echo "Applying serverless scaling from $scaling_file:"
  echo "$patch" | jq .
  auth -X PATCH "$API/endpoints/$endpoint_id" -d "$patch" | jq .
}

update_endpoint() {
  local endpoint_id="$1"
  local template_id="$2"
  local scaling_file="$3"
  local patch
  patch=$(jq -c --arg tid "$template_id" '. + {templateId: $tid}' "$scaling_file")
  echo "Updating endpoint $endpoint_id (template + serverless scaling):"
  echo "$patch" | jq .
  auth -X PATCH "$API/endpoints/$endpoint_id" -d "$patch" | jq .
}

wait_for_worker() {
  # Scale-to-zero endpoints have no workers until a request arrives.
  # Trigger cold start via smoke test instead of polling idle endpoint state.
  local endpoint_id="$1"
  local model="$2"
  local timeout="${3:-900}"
  echo "Waking endpoint $endpoint_id (cold start via smoke request, timeout ${timeout}s)..."
  smoke_chat "$endpoint_id" "$model" "$timeout"
}

endpoint_health() {
  curl -sS --max-time 15 "https://api.runpod.ai/v2/${1}/health" \
    -H "Authorization: Bearer $RUNPOD_API_KEY"
}

smoke_chat() {
  local endpoint_id="$1"
  local model="$2"
  local timeout="${3:-600}"
  local base="https://api.runpod.ai/v2/${endpoint_id}/openai/v1/chat/completions"
  local start attempt resp content elapsed ready
  start=$(date +%s)
  attempt=0
  while true; do
    attempt=$((attempt + 1))
    elapsed=$(( $(date +%s) - start ))
    ready=$(endpoint_health "$endpoint_id" | jq -r '.workers.ready // 0' 2>/dev/null || echo 0)
    echo "  smoke attempt $attempt (${elapsed}s elapsed, ready=$ready)..."
    local extra=""
    # Thinking models spend max_tokens on reasoning before "pong"; turn it off for the smoke test.
    if [ "$model" = "qwen3-8b-ha" ] || [ "$model" = "qwen3.8-27b" ]; then
      extra=',"chat_template_kwargs":{"enable_thinking":false}'
    fi
    # Cold starts (scale-to-zero) can take several minutes — allow long per-attempt waits.
    local curl_timeout=180
    if [ "$ready" != "0" ]; then
      curl_timeout=90
    fi
    resp=$(curl -sS --max-time "$curl_timeout" "$base" \
      -H "Authorization: Bearer $RUNPOD_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":20${extra}}") || true
    content=$(echo "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
    if [ "$content" = "pong" ]; then
      echo "  smoke OK (attempt $attempt): content=pong"
      return 0
    fi
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "  smoke FAILED after ${timeout}s: $resp" >&2
      return 1
    fi
    sleep 10
  done
}

purge_queue() {
  local endpoint_id="$1"
  curl -sS -X POST "https://api.runpod.ai/v2/${endpoint_id}/purge-queue" \
    -H "Authorization: Bearer $RUNPOD_API_KEY"
}

deploy_coding_agent() {
  echo "=== Deploy coding-agent: Qwen/Qwen3.8-27B-FP8 ==="
  local env_json
  # Built in python so the JSON-valued args keep their quoting. VLLM_EXTRA_ARGS is
  # shlex-split by the worker; these two flags aren't in its env-var allowlist.
  env_json=$(python3 - <<'EOF'
import json
print(json.dumps({
    "MODEL_NAME": "Qwen/Qwen3.8-27B-FP8",
    # 131072 OOMs at startup on 48 GB (vLLM: "can serve about 128000 tokens").
    "MAX_MODEL_LEN": "122880",
    "GPU_MEMORY_UTILIZATION": "0.9",
    "MAX_NUM_SEQS": "8",
    "ENABLE_AUTO_TOOL_CHOICE": "true",
    "TOOL_CALL_PARSER": "qwen3_coder",
    "REASONING_PARSER": "qwen3",
    "SPECULATIVE_CONFIG": json.dumps({"method": "mtp", "num_speculative_tokens": 3}),
    "VLLM_EXTRA_ARGS": "--language-model-only --default-chat-template-kwargs '"
        + json.dumps({"reasoning_effort": "low"}) + "'",
    "OPENAI_SERVED_MODEL_NAME_OVERRIDE": "qwen3.8-27b",
}))
EOF
)
  local template_id
  template_id=$(create_template "coding-agent-vllm-$(date +%Y%m%d-%H%M%S)" "$env_json" "$CODING_VLLM_IMAGE" 80)
  if [ -z "$template_id" ]; then
    echo "Failed to create coding-agent template" >&2
    exit 1
  fi
  echo "Created template: $template_id"
  update_endpoint "$CODING_ENDPOINT_ID" "$template_id" "$ROOT/models/coding-agent/endpoint-scaling.json"
  purge_queue "$CODING_ENDPOINT_ID" | jq -r '.removed // 0' | xargs -I{} echo "Purged {} queued jobs"
  wait_for_worker "$CODING_ENDPOINT_ID" "qwen3.8-27b" 1800
  echo "Coding endpoint ready. Update models/coding-agent/README.md template id to: $template_id"
}

refresh_home_assistant() {
  echo "=== Refresh home-assistant: Qwen/Qwen3-8B-AWQ (best bang-for-buck for HA) ==="
  local env_json
  env_json=$(python3 -c "
import json, pathlib
template = pathlib.Path('$ROOT/models/home-assistant/qwen3_nonthinking.jinja').read_text()
print(json.dumps({
    'MODEL_NAME': 'Qwen/Qwen3-8B-AWQ',
    'QUANTIZATION': 'awq',
    'MAX_MODEL_LEN': '8192',
    'GPU_MEMORY_UTILIZATION': '0.9',
    'ENFORCE_EAGER': 'true',
    'ENABLE_AUTO_TOOL_CHOICE': 'true',
    'TOOL_CALL_PARSER': 'hermes',
    'OPENAI_SERVED_MODEL_NAME_OVERRIDE': 'qwen3-8b-ha',
    'CUSTOM_CHAT_TEMPLATE': template,
}))
")
  local template_id
  template_id=$(create_template "home-assistant-vllm-$(date +%Y%m%d-%H%M%S)" "$env_json" "$HA_VLLM_IMAGE")
  if [ -z "$template_id" ]; then
    echo "Failed to create home-assistant template" >&2
    exit 1
  fi
  echo "Created template: $template_id"
  update_endpoint "$HA_ENDPOINT_ID" "$template_id" "$ROOT/models/home-assistant/endpoint-scaling.json"
  wait_for_worker "$HA_ENDPOINT_ID" "qwen3-8b-ha" 900
  echo "HA endpoint ready. Update models/home-assistant/README.md template id to: $template_id"
}

sync_scaling() {
  echo "=== Sync RunPod serverless scaling (no template redeploy) ==="
  apply_endpoint_scaling "$CODING_ENDPOINT_ID" "$ROOT/models/coding-agent/endpoint-scaling.json"
  apply_endpoint_scaling "$HA_ENDPOINT_ID" "$ROOT/models/home-assistant/endpoint-scaling.json"
}

verify_only() {
  echo "=== Verify existing endpoints (no redeploy) ==="
  smoke_chat "$CODING_ENDPOINT_ID" "qwen3.8-27b" 1800
  smoke_chat "$HA_ENDPOINT_ID" "qwen3-8b-ha"
}

install_opencode_config() {
  echo "=== Install opencode config ==="
  "$ROOT/scripts/setup-opencode.sh"
}

run_tests() {
  echo "=== Run regression suites ==="
  (cd "$ROOT/models/home-assistant" && ./run_tests.sh)
  (cd "$ROOT/models/coding-agent" && ./run_tests.sh)
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  all                 Deploy both endpoints + install opencode config + run tests
  coding              Deploy Qwen3.8-27B-FP8 to coding-agent endpoint
  home-assistant      Refresh Qwen3-8B-AWQ on home-assistant endpoint
  verify              Smoke-test existing endpoints only
  scaling             Apply endpoint-scaling.json to RunPod (no redeploy)
  opencode            Install opencode config + sync RUNPOD.key
  test                Run model regression suites

Requires RUNPOD_API_KEY in the environment.
EOF
}

main() {
  require_key
  local cmd="${1:-all}"
  case "$cmd" in
    all)
      deploy_coding_agent
      refresh_home_assistant
      install_opencode_config
      run_tests
      ;;
    coding) deploy_coding_agent ;;
    home-assistant) refresh_home_assistant ;;
    verify) verify_only ;;
    scaling) sync_scaling ;;
    opencode) install_opencode_config ;;
    test) run_tests ;;
    -h|--help|help) usage ;;
    *) echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
  esac
}

main "$@"
