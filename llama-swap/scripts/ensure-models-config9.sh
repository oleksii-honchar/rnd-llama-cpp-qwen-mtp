#!/usr/bin/env bash
# Ensure artifacts for config-9 exist (Qwopus3.6-27B-v1-preview-MTP-Q6_K + MTP-Q4_K_M transplanted GGUFs + better-qwen3.6 chat template).
# The transplanted GGUFs are produced by transplant-qwopus36-mtp-q6_k.sh and transplant-qwopus36-mtp-q4_k_m.sh respectively.
# Layout: repo root/llama-swap next to repo root/llama-models. Exports MODELS_MOUNT_PATH for docker compose (= llama-models/models).
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

# file_relative_to_models:script_basename (canonical: llama-models/scripts)
# The transplant script handles both downloads + transplant internally.
REQUIRED_MODELS=(
  "Qwopus3.6-27B-v1-preview-MTP-Q6_K.gguf:transplant-qwopus36-mtp-q6_k.sh"
  "Qwopus3.6-27B-v1-preview-MTP-Q4_K_M.gguf:transplant-qwopus36-mtp-q4_k_m.sh"
  "Qwopus3.6-27B-v1-preview-mmproj.gguf:download-qwopus36-27b-v1-preview-q6_k.sh"
  "better-qwen3.6-chat-template.jinja:download-better-qwen3.6-chat-template.sh"
)

_gguf_header_ok() {
  local f=$1
  [[ -f "$f" ]] || return 1
  [[ "$(head -c 4 "$f")" == "GGUF" ]]
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
    echo "[ensure-models-config9] Invalid GGUF (expected magic GGUF at offset 0, not HTML/truncation/wrong file): $full"
    rm -f "$full"
    need_fetch=1
  elif [[ "$file" == *.jinja ]]; then
    # Always delegate to the download script — it has its own freshness check (24h)
    need_fetch=1
  fi
  if [[ "$need_fetch" -eq 1 ]]; then
    echo "Model missing or re-fetching: ${full}"
    if [[ -x "$path" ]]; then
      echo "Running: $path ${FORCE:+--force}"
      "$path" ${FORCE:+"--force"}
    else
      echo "Run manually: bash ${path}" >&2
      exit 1
    fi
  fi
  if [[ "$file" == *.gguf ]] && ! _gguf_header_ok "$full"; then
    echo "[ensure-models-config9] ERROR: Still not a valid GGUF after download: $full" >&2
    exit 1
  fi
done

echo "[ensure-models-config9] Required config-9 model files present under ${MODELS_DIR}"
