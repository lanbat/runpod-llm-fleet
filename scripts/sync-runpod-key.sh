#!/usr/bin/env bash
# Write ~/.config/envman/RUNPOD.key from RUNPOD_API_KEY (or ~/.config/envman/RUNPOD.env).
set -euo pipefail

KEY_FILE="${HOME}/.config/envman/RUNPOD.key"
ENV_FILE="${HOME}/.config/envman/RUNPOD.env"

mkdir -p "$(dirname "$KEY_FILE")"

if [ -n "${RUNPOD_API_KEY:-}" ]; then
  printf '%s' "$RUNPOD_API_KEY" > "$KEY_FILE"
elif [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [ -z "${RUNPOD_API_KEY:-}" ]; then
    echo "RUNPOD_API_KEY is empty in $ENV_FILE" >&2
    exit 1
  fi
  printf '%s' "$RUNPOD_API_KEY" > "$KEY_FILE"
else
  echo "No RUNPOD_API_KEY in environment and no $ENV_FILE found." >&2
  echo "Set the key in ~/.config/envman/RUNPOD.env or export RUNPOD_API_KEY, then re-run." >&2
  exit 1
fi

chmod 600 "$KEY_FILE"
echo "Wrote $KEY_FILE ($(wc -c < "$KEY_FILE") bytes)"
