#!/usr/bin/env bash
# Download Qwen3.6-35B-A3B-TQ3_4S GGUF (TurboQuant, 3.07 BPW, ~12.4 GiB) for llama-swap config-5.
# Source: https://huggingface.co/YTan2000/Qwen3.6-35B-A3B-TQ3_4S
#
# Env: LLAMACPP_FORCE_REDOWNLOAD=1 — remove existing weights/mmproj and re-fetch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"
HF_BASE="https://huggingface.co/YTan2000/Qwen3.6-35B-A3B-TQ3_4S/resolve/main"

MODEL_FILE="Qwen3.6-35B-A3B-TQ3_4S.gguf"
HF_MMPROJ="mmproj-BF16.gguf"
MMPROJ_FILE="Qwen3.6-35B-A3B-mmproj-BF16.gguf"

MODEL_OUT="${MODELS_DIR}/${MODEL_FILE}"
MMPROJ_OUT="${MODELS_DIR}/${MMPROJ_FILE}"

mkdir -p "$MODELS_DIR"
if ! touch "${MODELS_DIR}/.write-test" 2>/dev/null; then
  echo "[download-qwen36-35b-a3b-tq3_4s] ERROR: Cannot write to $MODELS_DIR." >&2
  exit 1
fi
rm -f "${MODELS_DIR}/.write-test"

if [[ "${LLAMACPP_FORCE_REDOWNLOAD:-0}" == "1" ]]; then
  for f in "$MODEL_OUT" "$MMPROJ_OUT"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
fi

if [[ -f "$MODEL_OUT" ]]; then
  echo "[download-qwen36-35b-a3b-tq3_4s] Model already present: $MODEL_OUT"
else
  echo "[download-qwen36-35b-a3b-tq3_4s] Downloading ${MODEL_FILE} (~12.4 GiB) to $MODELS_DIR ..."
  curl -fL --retry 3 --retry-delay 2 -# -o "$MODEL_OUT" "${HF_BASE}/${MODEL_FILE}"
  echo "[download-qwen36-35b-a3b-tq3_4s] Done: $MODEL_OUT"
fi

if [[ -f "$MMPROJ_OUT" ]]; then
  echo "[download-qwen36-35b-a3b-tq3_4s] mmproj already present: $MMPROJ_OUT"
else
  echo "[download-qwen36-35b-a3b-tq3_4s] Downloading ${HF_MMPROJ} as ${MMPROJ_FILE} ..."
  curl -fL --retry 3 --retry-delay 2 -# -o "$MMPROJ_OUT" "${HF_BASE}/${HF_MMPROJ}"
  echo "[download-qwen36-35b-a3b-tq3_4s] Done: $MMPROJ_OUT"
fi
