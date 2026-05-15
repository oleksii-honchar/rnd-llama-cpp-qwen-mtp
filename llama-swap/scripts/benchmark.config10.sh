#!/usr/bin/env bash
# Benchmark: config10 — unified llama-bench (throughput) + llama-perplexity (quality) harness
# Covers Qwen3.6-27B Q6_K (DFlash speculative decoding, BeeLlama fork, turbo4/turbo3_tcq KV).
#
# Uses llama-cpp-beellama:latest (Dockerfile.llama-cpp-beellama with Anbeeld/beellama.cpp v0.1.2).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"            # mammoth-lan/llama-swap
MAMMOTH_LAN="$(cd "${ROOT}/.." && pwd)"           # mammoth-lan
MODELS_DIR="${MAMMOTH_LAN}/llama-models/models/"  # trailing slash included
export MODELS_MOUNT_PATH="$MODELS_DIR"

# Config-10 model (from configs/config-10.yaml)
CONFIG10_MODELS=(
  "Qwen3.6-27B-Q6_K.gguf:Qwen3.6-27B Q6_K (qwen36-27b)"
)

# ===== INTERACTIVE MODEL SELECTION =====
echo "====== Config-10 Model Selection ======"
echo ""
for i in "${!CONFIG10_MODELS[@]}"; do
  idx=$((i + 1))
  model_file="${CONFIG10_MODELS[i]%%:*}"
  model_name="${CONFIG10_MODELS[i]##*:}"
  exists="✓"
  if [[ ! -f "${MODELS_DIR}${model_file}" ]]; then
    exists="✗ MISSING"
  fi
  echo "  ${idx}. ${model_name} [${exists}]"
done
echo ""
echo "  0. Run ALL models"
echo ""
read -r -p "Select model number (0-${#CONFIG10_MODELS[@]}): " choice

if [[ "${choice}" == "0" ]]; then
  SELECTED_MODELS=("${CONFIG10_MODELS[@]}")
else
  if [[ "${choice}" -lt 1 || "${choice}" -gt "${#CONFIG10_MODELS[@]}" ]] 2>/dev/null; then
    echo "[ERROR] Invalid selection ${choice}. Run all models." >&2
    SELECTED_MODELS=("${CONFIG10_MODELS[@]}")
  else
    idx=$((choice - 1))
    SELECTED_MODELS=("${CONFIG10_MODELS[$idx]}")
  fi
fi
echo ""

# ===== THROUGHPUT BENCHMARKS (llama-bench) =====
echo "====== Config-10 Throughput Benchmarks ======"
echo "(tokens/second — higher is better)"
echo ""

for entry in "${SELECTED_MODELS[@]}"; do
  model_file="${entry%%:*}"
  model_name="${entry##*:}"
  model_path="${model_file}"

  echo "=============================================="
  echo "Throughput: ${model_name}"
  echo "=============================================="

  if [[ ! -f "${MODELS_DIR}${model_path}" ]]; then
    echo "[WARNING] ${MODELS_DIR}${model_path} not found. Skipping." >&2
    continue
  fi

  docker run --rm --network host --entrypoint "" \
      --gpus all \
      -v "${MODELS_DIR}:/data/models:ro" \
      llama-cpp-beellama:latest /usr/local/bin/llama-bench \
          "-m" "/data/models/${model_path}" \
          "-ngl" "99" \
          "-p" "2048" \
          "-n" "128" \
          "-r" "3" || true

  echo ""
done

# ===== PERPLEXITY BENCHMARKS (llama-perplexity) =====
WIKI_ZIP="${MAMMOTH_LAN}/llama-models/wikitext2.zip"
WIKI_RAW="${MODELS_DIR}wiki.test.raw"

if [[ ! -f "${WIKI_RAW}" ]]; then
  if [[ ! -f "${WIKI_ZIP}" ]]; then
    echo "[ERROR] ${WIKI_ZIP} not found. Please place wikitext2.zip in llama-models/." >&2
    exit 1
  fi
  echo "[extracting] wikitext2.zip ..."
  mkdir -p "${MODELS_DIR}__wiki_extract_tmp"
  unzip -o -q "${WIKI_ZIP}" -d "${MODELS_DIR}__wiki_extract_tmp"
  # Flatten: the zip contains files like wikitext-103-raw/wiki.test.raw
  # Find and copy wiki.test.raw to the models root
  found=0
  while IFS= read -r f; do
    if [[ -f "$f" ]]; then
      cp -- "$f" "${WIKI_RAW}"
      found=1
      echo "[extracted] ${f} → ${WIKI_RAW} ($(du -h "${WIKI_RAW}" | cut -f1))"
      break
    fi
  done < <(find "${MODELS_DIR}__wiki_extract_tmp" -name "wiki.test.raw" -type f)
  rm -rf "${MODELS_DIR}__wiki_extract_tmp"
  if [[ "${found}" -eq 0 ]]; then
    echo "[ERROR] wiki.test.raw not found inside wikitext2.zip." >&2
    exit 1
  fi
fi

echo ""
echo "====== Config-10 Perplexity Benchmarks ======"
echo "(perplexity score — lower is better)"
echo ""

for entry in "${SELECTED_MODELS[@]}"; do
  model_file="${entry%%:*}"
  model_name="${entry##*:}"
  model_path="${model_file}"

  echo "=============================================="
  echo "Perplexity: ${model_name}"
  echo "=============================================="

  if [[ ! -f "${MODELS_DIR}${model_path}" ]]; then
    echo "[WARNING] ${MODELS_DIR}${model_path} not found. Skipping." >&2
    continue
  fi

  docker run --rm --network host --entrypoint "" \
      --gpus all \
      -v "${MODELS_DIR}:/data/models:ro" \
      llama-cpp-beellama:latest /usr/local/bin/llama-perplexity \
          "-m" "/data/models/${model_path}" \
          "-ngl" "99" \
          "-t" "8" \
          "-p" "2048" \
          "-n" "128" \
          "-f" "/data/models/wiki.test.raw" \
          || true

  echo ""
done

echo "====== All config10 benchmarks complete ======"
