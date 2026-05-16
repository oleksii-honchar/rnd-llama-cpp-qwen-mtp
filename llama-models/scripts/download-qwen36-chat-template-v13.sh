#!/usr/bin/env bash
# Download the Qwen3.6 chat template from froggeric/Qwen-Fixed-Chat-Templates on HuggingFace.
# Source: https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates/tree/main/qwen3.6
#
# NOTE: The repo restructured — old v13+ templates moved to archive/, current template
# is at qwen3.6/chat_template.jinja (latest version, ~v16). We fetch the latest and
# save as chat_template-v13.jinja for backward compat with existing config references.
#
# Usage: bash download-qwen36-chat-template-v13.sh [--force]
# Output: llama-models/models/chat_template-v13.jinja
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${ROOT}/models"
TEMPLATE_FILE="${MODELS_DIR}/chat_template-v13.jinja"

# Create models directory if it doesn't exist
mkdir -p "$MODELS_DIR"

# Template URL (HuggingFace) — updated to latest template location
# Old: qwen3.6/chat_template-v13.jinja → moved to archive/
# New: qwen3.6/chat_template.jinja (latest, ~v16)
TEMPLATE_URL="https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates/resolve/main/qwen3.6/chat_template.jinja"

# Check if template already exists and is recent (within 24 hours)
if [[ -f "$TEMPLATE_FILE" ]] && [[ "$FORCE" -eq 0 ]]; then
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$TEMPLATE_FILE" >/dev/null 2>/dev/null || stat -c %Y "$TEMPLATE_FILE" 2>/dev/null) ))
    if (( FILE_AGE < 86400 )); then
        echo "[download-qwen36-chat-template-v13] Template is recent (age: $((FILE_AGE / 3600))h), skipping download."
        echo "[download-qwen36-chat-template-v13] Template: $TEMPLATE_FILE"
        exit 0
    fi
    echo "[download-qwen36-chat-template-v13] Existing template is older than 24h, re-downloading."
fi

echo "[download-qwen36-chat-template-v13] Downloading Qwen3.6 chat template (v13) from HuggingFace..."
echo "[download-qwen36-chat-template-v13] Source: $TEMPLATE_URL"
echo "[download-qwen36-chat-template-v13] Target: $TEMPLATE_FILE"

# Download with curl
if command -v curl &>/dev/null; then
    curl -fSL --retry 3 --retry-delay 5 -o "$TEMPLATE_FILE" "$TEMPLATE_URL"
elif command -v wget &>/dev/null; then
    wget -qO "$TEMPLATE_FILE" "$TEMPLATE_URL"
else
    echo "Error: Neither curl nor wget found." >&2
    exit 1
fi

# Verify download
if [[ ! -s "$TEMPLATE_FILE" ]]; then
    echo "[download-qwen36-chat-template-v13] ERROR: Downloaded file is empty." >&2
    rm -f "$TEMPLATE_FILE"
    exit 1
fi

# Display file size and first few lines
echo "[download-qwen36-chat-template-v13] Download complete."
echo "[download-qwen36-chat-template-v13] File size: $(wc -c < "$TEMPLATE_FILE") bytes"
echo "[download-qwen36-chat-template-v13] Template: $TEMPLATE_FILE"
