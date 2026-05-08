#!/usr/bin/env bash
# Transplant MTP block tensors from am17an Qwen3.6-27B-MTP Q8_0 into Jackrong Qwopus3.6-27B-v1-preview Q4_K_M.
# Produces: Qwopus3.6-27B-v1-preview-MTP-Q4_K_M.gguf
#
# Strategy:
#   1. Download both GGUFs (target Q4_K_M + source MTP Q8_0) if missing
#   2. Set up a Python venv with the `gguf` package
#   3. Run transplant_mtp.py to copy MTP tensors from source into target
#
# Usage: bash transplant-qwopus36-mtp-q4_k_m.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${MODELS_MOUNT_PATH:-${LLAMA_MODELS_ROOT}/models}"

# --- Model file names ---
TARGET_FILE="Qwopus3.6-27B-v1-preview-Q4_K_M.gguf"
SOURCE_FILE="Qwen3.6-27B-MTP-Q8_0.gguf"
OUTPUT_FILE="Qwopus3.6-27B-v1-preview-MTP-Q4_K_M.gguf"

TARGET_OUT="${MODELS_DIR}/${TARGET_FILE}"
SOURCE_OUT="${MODELS_DIR}/${SOURCE_FILE}"
OUTPUT_OUT="${MODELS_DIR}/${OUTPUT_FILE}"

# --- Download target GGUF (Qwopus Q4_K_M) if missing ---
echo "[transplant-qwopus36-mtp-q4_k_m] Ensuring target GGUF (Qwopus Q4_K_M)..."
TARGET_SCRIPT="${SCRIPT_DIR}/download-qwopus36-27b-v1-preview-q4_k_m.sh"
if [[ ! -f "$TARGET_OUT" ]]; then
  echo "[transplant-qwopus36-mtp-q4_k_m] Downloading target GGUF..."
  if [[ -x "$TARGET_SCRIPT" ]]; then
    bash "$TARGET_SCRIPT"
  else
    echo "[transplant-qwopus36-mtp-q4_k_m] ERROR: Target download script not found: $TARGET_SCRIPT" >&2
    exit 1
  fi
fi

# --- Download source GGUF (MTP Q8_0) if missing ---
echo "[transplant-qwopus36-mtp-q4_k_m] Ensuring source GGUF (MTP Q8_0)..."
SOURCE_SCRIPT="${SCRIPT_DIR}/download-qwen36-27b-mtp-q8_0.sh"
if [[ ! -f "$SOURCE_OUT" ]]; then
  echo "[transplant-qwopus36-mtp-q4_k_m] Downloading source GGUF..."
  if [[ -x "$SOURCE_SCRIPT" ]]; then
    bash "$SOURCE_SCRIPT"
  else
    echo "[transplant-qwopus36-mtp-q4_k_m] ERROR: Source download script not found: $SOURCE_SCRIPT" >&2
    exit 1
  fi
fi

# --- Validate GGUFs ---
for f in "$TARGET_OUT" "$SOURCE_OUT"; do
  if [[ "$(head -c 4 "$f")" != "GGUF" ]]; then
    echo "[transplant-qwopus36-mtp-q4_k_m] ERROR: Invalid GGUF magic at: $f" >&2
    exit 1
  fi
done

# --- Skip if output already exists and is valid ---
if [[ -f "$OUTPUT_OUT" ]] && [[ "$(head -c 4 "$OUTPUT_OUT")" == "GGUF" ]]; then
  echo "[transplant-qwopus36-mtp-q4_k_m] Transplanted GGUF already present: $OUTPUT_OUT"
  echo "[transplant-qwopus36-mtp-q4_k_m] To re-transplant, delete: $OUTPUT_OUT"
  exit 0
fi

# --- Set up Python venv with gguf package ---
VENV_DIR="${SCRIPT_DIR}/.venv-mtp-transplant"
if [[ ! -d "$VENV_DIR" ]] || ! "$VENV_DIR/bin/python" -c "import gguf" 2>/dev/null; then
  echo "[transplant-qwopus36-mtp-q4_k_m] Setting up Python venv with gguf package..."
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --upgrade pip
  "$VENV_DIR/bin/pip" install gguf
fi

# --- Run transplant ---
echo "[transplant-qwopus36-mtp-q4_k_m] Transplanting MTP tensors:"
echo "  Target (Q4_K_M):  $TARGET_OUT"
echo "  Source (Q8_0):  $SOURCE_OUT"
echo "  Output:         $OUTPUT_OUT"
echo ""

"$VENV_DIR/bin/python" "${SCRIPT_DIR}/transplant_mtp.py" \
  --target "$TARGET_OUT" \
  --source "$SOURCE_OUT" \
  --output "$OUTPUT_OUT"

# --- Validate output ---
if [[ ! -f "$OUTPUT_OUT" ]]; then
  echo "[transplant-qwopus36-mtp-q4_k_m] ERROR: Transplant did not produce output file." >&2
  exit 1
fi

if [[ "$(head -c 4 "$OUTPUT_OUT")" != "GGUF" ]]; then
  echo "[transplant-qwopus36-mtp-q4_k_m] ERROR: Output file is not a valid GGUF." >&2
  rm -f "$OUTPUT_OUT"
  exit 1
fi

OUTPUT_SIZE=$(du -h "$OUTPUT_OUT" | cut -f1)
echo "[transplant-qwopus36-mtp-q4_k_m] Transplant complete: $OUTPUT_OUT ($OUTPUT_SIZE)"
