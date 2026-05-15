#!/usr/bin/env bash
# Download DFlash drafter model Q4_K_M (~0.9 GB) for speculative decoding with llama-swap config-10.
# Source: https://huggingface.co/spiritbuun/Qwen3.6-27B-DFlash-GGUF
#
# Q4_K_M is the recommended drafter quant — Q8_0 is larger and slower with no quality benefit for drafting.
#
# Env: LLAMACPP_FORCE_REDOWNLOAD=1 — remove existing weights and re-fetch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"
HF_BASE="https://huggingface.co/spiritbuun/Qwen3.6-27B-DFlash-GGUF/resolve/main"

MODEL_FILE="dflash-draft-3.6-q4_k_m.gguf"
MODEL_OUT="${MODELS_DIR}/${MODEL_FILE}"

mkdir -p "$MODELS_DIR"
if ! touch "${MODELS_DIR}/.write-test" 2>/dev/null; then
  echo "[download-dflash-draft-3.6-q4_k_m] ERROR: Cannot write to $MODELS_DIR." >&2
  exit 1
fi
rm -f "${MODELS_DIR}/.write-test"

if [[ "${LLAMACPP_FORCE_REDOWNLOAD:-0}" == "1" ]]; then
  [[ -f "$MODEL_OUT" ]] && rm -f "$MODEL_OUT"
fi

if [[ -f "$MODEL_OUT" ]]; then
  echo "[download-dflash-draft-3.6-q4_k_m] Model already present: $MODEL_OUT"
else
  echo "[download-dflash-draft-3.6-q4_k_m] Downloading ${MODEL_FILE} (~0.9 GB) to $MODELS_DIR ..."
  curl -fL --retry 3 --retry-delay 2 -# -o "$MODEL_OUT" "${HF_BASE}/${MODEL_FILE}"
  echo "[download-dflash-draft-3.6-q4_k_m] Done: $MODEL_OUT"
fi
