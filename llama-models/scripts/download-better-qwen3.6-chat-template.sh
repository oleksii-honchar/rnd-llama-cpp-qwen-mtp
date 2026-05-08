#!/usr/bin/env bash
# Download the improved Qwen3.6 chat template from the better-qwen3.6-chat-template.jinja repository.
# This version includes DCP (Dynamic Context Pruning) exception handling for multi-agent sessions.
# Source: https://github.com/oleksii-honchar/better-qwen3.6-chat-template.jinja
#
# Usage: bash download-better-qwen3.6-chat-template.sh
# Output: llama-models/models/better-qwen3.6-chat-template.jinja
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${ROOT}/models"
TEMPLATE_FILE="${MODELS_DIR}/better-qwen3.6-chat-template.jinja"

# Create models directory if it doesn't exist
mkdir -p "$MODELS_DIR"

# Better template URL (with DCP exception handling)
BETTER_TEMPLATE_URL="https://raw.githubusercontent.com/oleksii-honchar/better-qwen3.6-chat-template.jinja/main/better-qwen3.6-chat-template.jinja"

# Check if template already exists and is recent (within 24 hours)
if [[ -f "$TEMPLATE_FILE" ]] && [[ "$FORCE" -eq 0 ]]; then
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$TEMPLATE_FILE" 2>/dev/null || stat -c %Y "$TEMPLATE_FILE" 2>/dev/null) ))
    if (( FILE_AGE < 86400 )); then
        echo "[download-better-qwen3.6-chat-template] Template is recent (age: $((FILE_AGE / 3600))h), skipping download."
        echo "[download-better-qwen3.6-chat-template] Template: $TEMPLATE_FILE"
        exit 0
    fi
    echo "[download-better-qwen3.6-chat-template] Existing template is older than 24h, re-downloading."
fi

echo "[download-better-qwen3.6-chat-template] Downloading better template from GitHub..."
echo "[download-better-qwen3.6-chat-template] Source: $BETTER_TEMPLATE_URL"
echo "[download-better-qwen3.6-chat-template] Target: $TEMPLATE_FILE"

# Download with curl
if command -v curl &>/dev/null; then
    curl -fSL --retry 3 --retry-delay 5 -o "$TEMPLATE_FILE" "$BETTER_TEMPLATE_URL"
elif command -v wget &>/dev/null; then
    wget -qO "$TEMPLATE_FILE" "$BETTER_TEMPLATE_URL"
else
    echo "Error: Neither curl nor wget found." >&2
    exit 1
fi

# Verify download
if [[ ! -s "$TEMPLATE_FILE" ]]; then
    echo "[download-better-qwen3.6-chat-template] ERROR: Downloaded file is empty." >&2
    rm -f "$TEMPLATE_FILE"
    exit 1
fi

# Display file size and first few lines
echo "[download-better-qwen3.6-chat-template] Download complete."
echo "[download-better-qwen3.6-chat-template] File size: $(wc -c < "$TEMPLATE_FILE") bytes"
echo "[download-better-qwen3.6-chat-template] Template: $TEMPLATE_FILE"