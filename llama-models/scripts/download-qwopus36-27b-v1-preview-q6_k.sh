#!/usr/bin/env bash
# Download Qwopus3.6-27B-v1-preview Q6_K GGUF (and mmproj) into ./models for llama.cpp.
# Source: https://huggingface.co/Jackrong/Qwopus3.6-27B-v1-preview-GGUF
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"
HF_BASE="https://huggingface.co/Jackrong/Qwopus3.6-27B-v1-preview-GGUF/resolve/main"

MODEL_FILE="Qwopus3.6-27B-v1-preview-Q6_K.gguf"
MMPROJ_FILE="Qwopus3.6-27B-v1-preview-mmproj.gguf"

MODEL_OUT="${MODELS_DIR}/${MODEL_FILE}"
MMPROJ_OUT="${MODELS_DIR}/${MMPROJ_FILE}"

mkdir -p "$MODELS_DIR"

if ! touch "${MODELS_DIR}/.write-test" 2>/dev/null; then
  echo "[download-qwopus36-27b-v1-preview-q6_k] ERROR: Cannot write to $MODELS_DIR." >&2
  echo "Fix with: sudo chown -R \$(whoami) $MODELS_DIR" >&2
  exit 1
fi
rm -f "${MODELS_DIR}/.write-test"

if [[ -f "$MODEL_OUT" ]]; then
  echo "[download-qwopus36-27b-v1-preview-q6_k] Model already present: $MODEL_OUT"
else
  echo "[download-qwopus36-27b-v1-preview-q6_k] Downloading $MODEL_FILE (~22.1 GB) to $MODELS_DIR ..."
  curl -# -L -o "$MODEL_OUT" "${HF_BASE}/Qwopus3.6-27B-v1-preview-Q6_K.gguf"
  echo "[download-qwopus36-27b-v1-preview-q6_k] Done: $MODEL_OUT"
fi

if [[ -f "$MMPROJ_OUT" ]]; then
  echo "[download-qwopus36-27b-v1-preview-q6_k] mmproj already present: $MMPROJ_OUT"
else
  echo "[download-qwopus36-27b-v1-preview-q6_k] Downloading $MMPROJ_FILE to $MODELS_DIR ..."
  curl -# -L -o "$MMPROJ_OUT" "${HF_BASE}/mmproj.gguf"
  echo "[download-qwopus36-27b-v1-preview-q6_k] Done: $MMPROJ_OUT"
fi
