#!/usr/bin/env bash
# Quick start: install and configure opencode for the RunPod LLM fleet.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "=== RunPod LLM Fleet Quick Start ==="

# 1. Install opencode CLI if not present
if ! command -v opencode >/dev/null 2>&1; then
  echo "Installing opencode CLI..."
  npm install -g @opencode/cli
fi

# 2. Ensure API key exists
if [ ! -f "${HOME}/.config/envman/RUNPOD.key" ]; then
  echo ""
  echo "API key not found at ~/.config/envman/RUNPOD.key"
  read -r -p "Enter your RunPod API key (rpa_...): " RUNPOD_KEY
  mkdir -p "${HOME}/.config/envman"
  echo "$RUNPOD_KEY" > "${HOME}/.config/envman/RUNPOD.key"
  chmod 600 "${HOME}/.config/envman/RUNPOD.key"
  echo "Key saved."
fi

# 3. Install global configs
echo ""
echo "Installing opencode global config..."
mkdir -p "${HOME}/.config/opencode"
cp "$ROOT/opencode-config.jsonc" "${HOME}/.config/opencode/opencode.jsonc"
cp "$ROOT/opencode-runtime.json" "${HOME}/.config/opencode/opencode.json"
echo "Global config installed."

# 4. Link project config into repo root if missing
if [ ! -f "$ROOT/.opencode/opencode.json" ]; then
  echo "Creating project config at $ROOT/.opencode/opencode.json..."
  mkdir -p "$ROOT/.opencode"
  cat > "$ROOT/.opencode/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "runpod/qwen3-coder-next",
  "default_agent": "build",
  "instructions": [".opencode/instructions.md"],
  "agent": {
    "plan": {
      "disable": false
    }
  },
  "permission": {
    "plan_enter": "allow",
    "plan_exit": "allow",
    "external_directory": {
      "/home/traph/projects/lanbat/**": "allow",
      "/tmp/*": "allow",
      "/home/traph/.local/share/opencode/**": "allow",
      "*": "ask"
    }
  },
  "compaction": {
    "auto": true,
    "prune": true,
    "tail_turns": 12,
    "reserved": 24000
  }
}
EOF
  echo "Project config created."
fi

# 5. Validate
echo ""
echo "Validating setup..."
"$ROOT/scripts/validate-opencode.sh"

echo ""
echo "=== Setup complete! ==="
echo "Run: cd $ROOT && opencode"
