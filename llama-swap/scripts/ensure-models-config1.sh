#!/usr/bin/env bash
# Ensure artifacts for config-1 (Qwen3.6-35B-A3B-TQ3_4S + MTP drafter + chat template v13);
# run download scripts if missing.
# Layout: llama-swap next to llama-models (sibling under same repo root). Exports MODELS_MOUNT_PATH for docker compose (= llama-models/models).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
MODELS_DIR="${REPO_ROOT}/llama-models/models"
LM_DL_SCRIPTS="${REPO_ROOT}/llama-models/scripts"
export MODELS_MOUNT_PATH="$MODELS_DIR"

# file_relative_to_models:download_script_basename (canonical: llama-models/scripts)
REQUIRED_MODELS=(
  "Qwen3.6-35B-A3B-MTP-TQ3_4S.gguf:download-qwen36-35b-a3b-mtp-tq3_4s.sh"
  "Qwen3.6-35B-A3B-TQ3_4S.gguf:download-qwen36-35b-a3b-tq3_4s.sh"
  "chat_template-v13.jinja:download-qwen36-chat-template-v13.sh"
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
    echo "[ensure-models-config1] Invalid GGUF (expected magic GGUF at offset 0, not HTML/truncation/wrong file): $full"
    rm -f "$full"
    need_fetch=1
  elif [[ "$file" == *.jinja ]]; then
    # Always delegate to the download script — it has its own freshness check (24h)
    need_fetch=1
  fi
  if [[ "$need_fetch" -eq 1 ]]; then
    echo "Model missing or re-fetching: ${full}"
    if [[ -x "$path" ]]; then
      echo "Running: $path"
      "$path"
    else
      echo "Run manually: bash ${path}" >&2
      exit 1
    fi
  fi
  if [[ "$file" == *.gguf ]] && ! _gguf_header_ok "$full"; then
    echo "[ensure-models-config1] ERROR: Still not a valid GGUF after download: $full" >&2
    exit 1
  fi
done

echo "[ensure-models-config1] Required config-1 model files present under ${MODELS_DIR}"
