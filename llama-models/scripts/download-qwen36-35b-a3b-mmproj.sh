#!/usr/bin/env bash
# Download Qwen3.6-35B-A3B-mmproj-BF16.gguf for llama-swap config-5 (Qwen3.6-35B-A3B-TQ3_4S).
# Source: https://huggingface.co/YTan2000/Qwen3.6-35B-A3B-TQ3_4S
#
# Env: LLAMACPP_FORCE_REDOWNLOAD=1 — remove existing mmproj and re-fetch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"
HF_BASE="https://huggingface.co/YTan2000/Qwen3.6-35B-A3B-TQ3_4S/resolve/main"

MMPROJ_FILE="Qwen3.6-35B-A3B-mmproj-BF16.gguf"
HF_MMPROJ="mmproj-BF16.gguf"

MMPROJ_OUT="${MODELS_DIR}/${MMPROJ_FILE}"

mkdir -p "$MODELS_DIR"
if ! touch "${MODELS_DIR}/.write-test" 2>/dev/null; then
  echo "[download-qwen36-35b-a3b-mmproj] ERROR: Cannot write to $MODELS_DIR." >&2
  exit 1
fi
rm -f "${MODELS_DIR}/.write-test"

if [[ "${LLAMACPP_FORCE_REDOWNLOAD:-0}" == "1" ]]; then
  [[ -f "$MMPROJ_OUT" ]] && rm -f "$MMPROJ_OUT"
fi

if [[ -f "$MMPROJ_OUT" ]]; then
  echo "[download-qwen36-35b-a3b-mmproj] mmproj already present: $MMPROJ_OUT"
else
  echo "[download-qwen36-35b-a3b-mmproj] Downloading ${HF_MMPROJ} as ${MMPROJ_FILE} ..."
  curl -fL --retry 3 --retry-delay 2 -# -o "$MMPROJ_OUT" "${HF_BASE}/${HF_MMPROJ}"
  echo "[download-qwen36-35b-a3b-mmproj] Done: $MMPROJ_OUT"
fi
