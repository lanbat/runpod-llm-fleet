#!/usr/bin/env bash
# Install global + project opencode config for the RunPod Qwen3-Coder-Next fleet.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GLOBAL_CONFIG="${HOME}/.config/opencode/opencode.jsonc"

echo "=== RunPod opencode setup ==="

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode CLI not found. Install with: npm install -g @opencode/cli" >&2
  exit 1
fi

echo "opencode $(opencode --version)"

mkdir -p "${HOME}/.config/opencode"
cp "$ROOT/opencode-config.jsonc" "$GLOBAL_CONFIG"
echo "Installed $GLOBAL_CONFIG"

"$ROOT/scripts/sync-runpod-key.sh"

echo ""
echo "Checking RunPod endpoint auth..."
if curl -sf --max-time 30 \
  "https://api.runpod.ai/v2/h8ins1a7nls350/health" \
  -H "Authorization: Bearer $(cat "${HOME}/.config/envman/RUNPOD.key")" >/dev/null; then
  echo "RunPod health check: OK"
else
  echo "RunPod health check failed (key may be invalid or endpoint cold-starting)." >&2
  exit 1
fi

echo ""
echo "Listing runpod models..."
opencode models runpod

echo ""
echo "Setup complete."
echo "  Global provider config: $GLOBAL_CONFIG"
echo "  Project defaults:       $ROOT/.opencode/opencode.json"
echo ""
echo "Usage (scale-to-zero — first request after idle cold-starts the GPU, 1–5+ min):"
echo "  cd $ROOT && opencode           # TUI with project defaults"
echo "  opencode run --model runpod/qwen3-coder-next \"your prompt\""
echo ""
echo "See docs/opencode-setup.md for full documentation."
