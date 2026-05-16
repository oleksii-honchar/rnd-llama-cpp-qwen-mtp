#!/usr/bin/env bash
# Download Qwen3.6-35B-A3B-MTP-TQ3_4S GGUF with native MTP decoding heads
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"

HF_BASE="https://huggingface.co/YTan2000/Qwen3.6-35B-A3B-MTP-TQ3_4S/resolve/main"

MODEL_FILE="Qwen3.6-35B-A3B-MTP-TQ3_4S.gguf"
MM_PROJ_FILE="Qwen3.6-35B-A3B-mmproj-BF16.gguf"
HF_MMPROJ="mmproj-BF16.gguf"

MODEL_OUT="${MODELS_DIR}/${MODEL_FILE}"
MMPROJ_OUT="${MODELS_DIR}/${MM_PROJ_FILE}"

download_file() {
    local out="$1"
    local hf_path="$2"
    local url="${HF_BASE}/${hf_path}"
    
    if [ -f "$out" ]; then
        echo "✓ ${out} already exists"
        return 0
    fi
    
    echo "Downloading $hf_path from HuggingFace..."
    # Using wget with progress display (-p) and continue on interruption (-c)
    wget -q --show-progress --continue -O "$out" "$url" || {
        echo "Error: Failed to download $hf_path" >&2
        return 1
    }
    echo "✓ Downloaded: ${out}"
}

main() {
    mkdir -p "${MODELS_DIR}"
    
    echo "=== Downloading Qwen3.6-35B-A3B-MTP-TQ3_4S ==="
    download_file "$MODEL_OUT" "Qwen3.6-35B-A3B-MTP-TQ3_4S.gguf"
    download_file "$MMPROJ_OUT" "$HF_MMPROJ"
    
    echo "Done! GGUFs are in: ${MODELS_DIR}"
}

main "$@"
