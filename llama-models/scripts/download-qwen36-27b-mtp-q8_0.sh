#!/usr/bin/env bash
# Download am17an Qwen3.6-27B-MTP Q8_0 GGUF (source for MTP transplant).
# Source: https://huggingface.co/am17an/Qwen3.6-27B-MTP-GGUF
# This GGUF provides the MTP block tensors transplanted into the Qwopus Q6_K target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"
HF_BASE="https://huggingface.co/am17an/Qwen3.6-27B-MTP-GGUF/resolve/main"

MODEL_FILE="Qwen3.6-27B-MTP-Q8_0.gguf"
MODEL_OUT="${MODELS_DIR}/${MODEL_FILE}"

mkdir -p "$MODELS_DIR"

if ! touch "${MODELS_DIR}/.write-test" 2>/dev/null; then
  echo "[download-qwen36-27b-mtp-q8_0] ERROR: Cannot write to $MODELS_DIR." >&2
  echo "Fix with: sudo chown -R \$(whoami) $MODELS_DIR" >&2
  exit 1
fi
rm -f "${MODELS_DIR}/.write-test"

if [[ -f "$MODEL_OUT" ]]; then
  echo "[download-qwen36-27b-mtp-q8_0] Model already present: $MODEL_OUT"
else
  echo "[download-qwen36-27b-mtp-q8_0] Downloading $MODEL_FILE (~30 GB) to $MODELS_DIR ..."
  curl -# -L -o "$MODEL_OUT" "${HF_BASE}/Qwen3.6-27B-MTP-Q8_0.gguf"
  echo "[download-qwen36-27b-mtp-q8_0] Done: $MODEL_OUT"
fi

# Verify GGUF magic
if [[ -f "$MODEL_OUT" ]] && [[ "$(head -c 4 "$MODEL_OUT")" != "GGUF" ]]; then
  echo "[download-qwen36-27b-mtp-q8_0] ERROR: Invalid GGUF magic at offset 0 (not GGUF)." >&2
  rm -f "$MODEL_OUT"
  exit 1
fi

echo "[download-qwen36-27b-mtp-q8_0] MTP source GGUF ready: $MODEL_OUT"
