#!/usr/bin/env bash
# Ensure artifacts for config-10 (Qwen3.6-27B Q6_K + DFlash drafter Q4_K_M + Qwopus3.6-27B-v1-preview Q6_K + better-qwen3.6 chat template).
# Layout: repo root/llama-swap next to repo root/llama-models. Exports MODELS_MOUNT_PATH for docker compose (= llama-models/models).
#
# IMPORTANT: Target model MUST be unsloth/Qwen3.6-27B-GGUF (NOT Jackrong/Qwopus3.6-27B).
# DFlash drafter was trained on Qwen3.6-27B hidden states. Using Qwopus3.6-27B as target
# causes out-of-range crashes during spec cycles (drafter cross-attention produces
# incompatible indices with Qwopus's different hidden states).
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
MODELS_DIR="${REPO_ROOT}/llama-models/models"
LM_DL_SCRIPTS="${REPO_ROOT}/llama-models/scripts"
export MODELS_MOUNT_PATH="$MODELS_DIR"

# file_relative_to_models:script_basename (canonical: mammoth-lan/llama-models/scripts)
REQUIRED_MODELS=(
  "Qwen3.6-27B-Q6_K.gguf:download-qwen36-27b-q6_k.sh"
  "dflash-draft-3.6-q4_k_m.gguf:download-dflash-draft-3.6-q4_k_m.sh"
  "Qwopus3.6-27B-v1-preview-Q6_K.gguf:download-qwopus36-27b-v1-preview-q6_k.sh"
  "better-qwen3.6-chat-template.jinja:download-better-qwen3.6-chat-template.sh"
)

_gguf_header_ok() {
  local f=$1
  [[ -f "$f" ]] || return 1
  # Use xxd to safely read binary bytes — head -c 4 can fail with null bytes in bash comparison
  local magic
  magic=$(xxd -p -l 4 "$f" 2>/dev/null) || return 1
  [[ "$magic" == "47475546" ]]  # GGUF in hex
}

for entry in "${REQUIRED_MODELS[@]}"; do
  file="${entry%%:*}"
  script="${entry##*:}"
  path="${LM_DL_SCRIPTS}/${script}"
  full="${MODELS_DIR}/${file}"
  need_fetch=0
  if [[ ! -f "$full" ]]; then
    need_fetch=1
  elif [[ "$file" == *.gguf ]] && ! _gguf_header_ok "$full"; then
    echo "[ensure-models-config10] Invalid GGUF (expected magic GGUF at offset 0, not HTML/truncation/wrong file): $full"
    rm -f "$full"
    need_fetch=1
  elif [[ "$file" == *.jinja ]]; then
    # Always delegate to the download script — it has its own freshness check (24h)
    need_fetch=1
  fi
  if [[ "$need_fetch" -eq 1 ]]; then
    echo "Model missing or re-fetching: ${full}"
    # Always run the download script automatically — don't require -x, just bash it
    echo "Downloading: $path ${FORCE:+--force}"
    bash "$path" ${FORCE:+'--force'}
  fi
  if [[ "$file" == *.gguf ]] && ! _gguf_header_ok "$full"; then
    echo "[ensure-models-config10] ERROR: Still not a valid GGUF after download: $full" >&2
    exit 1
  fi
done

echo "[ensure-models-config10] Required config-10 model files present under ${MODELS_DIR}"
