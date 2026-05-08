#!/usr/bin/env bash
# Benchmark: config9 — unified llama-bench (throughput) + llama-perplexity (quality) harness
# Covers Qwopus3.6-27B-v1-preview-MTP-Q6_K + Q4_K_M (native MTP speculative decoding via PR #22673).
#
# Uses llama-cpp-beta:latest (Dockerfile.llama-cpp-beta with PR #22673).
# MTP speculative decoding is NOT tested by llama-bench (no --spec-type flag).
# MTP acceptance rate is measured via live server on port 8014.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"            # llama-swap
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"             # repo root
MODELS_DIR="${REPO_ROOT}/llama-models/models/"    # trailing slash included
export MODELS_MOUNT_PATH="$MODELS_DIR"

# Config-9 model (from configs/config-9.yaml)
CONFIG9_MODELS=(
  "Qwopus3.6-27B-v1-preview-MTP-Q6_K.gguf:Qwopus3.6-27B-v1-preview-MTP-Q6_K (qwopus36-27b)"
  "Qwopus3.6-27B-v1-preview-MTP-Q4_K_M.gguf:Qwopus3.6-27B-v1-preview-MTP-Q4_K_M (qwopus36-27b-q4)"
)

# ===== INTERACTIVE MODEL SELECTION =====
echo "====== Config-9 Model Selection ======"
echo ""
for i in "${!CONFIG9_MODELS[@]}"; do
  idx=$((i + 1))
  model_file="${CONFIG9_MODELS[i]%%:*}"
  model_name="${CONFIG9_MODELS[i]##*:}"
  exists="✓"
  if [[ ! -f "${MODELS_DIR}${model_file}" ]]; then
    exists="✗ MISSING"
  fi
  echo "  ${idx}. ${model_name} [${exists}]"
done
echo ""
echo "  0. Run ALL models"
echo ""
read -r -p "Select model number (0-${#CONFIG9_MODELS[@]}): " choice

if [[ "${choice}" == "0" ]]; then
  SELECTED_MODELS=("${CONFIG9_MODELS[@]}")
else
  if [[ "${choice}" -lt 1 || "${choice}" -gt "${#CONFIG9_MODELS[@]}" ]] 2>/dev/null; then
    echo "[ERROR] Invalid selection ${choice}. Run all models." >&2
    SELECTED_MODELS=("${CONFIG9_MODELS[@]}")
  else
    idx=$((choice - 1))
    SELECTED_MODELS=("${CONFIG9_MODELS[$idx]}")
  fi
fi
echo ""

# ===== THROUGHPUT BENCHMARKS (llama-bench) =====
echo "====== Config-9 Throughput Benchmarks ======"
echo "(tokens/second — higher is better)"
echo "(NOTE: llama-bench does NOT test MTP speculative decoding — baseline only)"
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
      llama-cpp-beta:latest /usr/local/bin/llama-bench \
          "-m" "/data/models/${model_path}" \
          "-ngl" "99" \
          "-p" "2048" \
          "-n" "128" \
          "-r" "3" || true

  echo ""
done

# ===== PERPLEXITY BENCHMARKS (llama-perplexity) =====
WIKI_ZIP="${REPO_ROOT}/llama-models/wikitext2.zip"
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
echo "====== Config-9 Perplexity Benchmarks ======"
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
      llama-cpp-beta:latest /usr/local/bin/llama-perplexity \
          "-m" "/data/models/${model_path}" \
          "-ngl" "99" \
          "-t" "8" \
          "-p" "2048" \
          "-n" "128" \
          "-f" "/data/models/wiki.test.raw" \
          || true

  echo ""
done

# ===== MTP SPECULATIVE DECODING BENCHMARK (live server) =====
LLAMA_SWAP_URL="${LLAMA_SWAP_URL:-http://localhost:8014}"
CURL_CONNECT="${CURL_CONNECT:-15}"
CURL_MAX_TIME="${CURL_MAX_TIME:-300}"
MTP_BENCH_MAX_TOKENS="${MTP_BENCH_MAX_TOKENS:-4096}"
MTP_BENCH_PROMPT="${MTP_BENCH_PROMPT:-Write a detailed explanation of how speculative decoding works in large language models, including the trade-offs between acceptance rate and throughput.}"

command -v jq >/dev/null 2>&1 || { echo "benchmark.config9.sh: jq required" >&2; exit 1; }

echo "====== Config-9 MTP Speculative Decoding Benchmark ======"
echo "(live server test — measures MTP acceptance rate + tokens/second)"
echo "URL: ${LLAMA_SWAP_URL}"
echo ""

# Check server health
echo "[health] Checking server at ${LLAMA_SWAP_URL}/health ..."
if ! curl -sf --connect-timeout "$CURL_CONNECT" --max-time 30 "${LLAMA_SWAP_URL}/health" >/dev/null 2>&1; then
  echo "[WARNING] Server not healthy at ${LLAMA_SWAP_URL}. Skipping MTP benchmark." >&2
  echo "Start server first: ./start.sh" >&2
else
  echo "[health] Server OK"
  echo ""

  # Verify model is loaded
  MODELS_JSON=$(curl -sf --connect-timeout "$CURL_CONNECT" --max-time 60 "${LLAMA_SWAP_URL}/v1/models") || {
    echo "[WARNING] Cannot fetch /v1/models. Skipping MTP benchmark." >&2
  } || {
    echo "$MODELS_JSON" | jq -e --arg id "qwopus36-27b" '.data[] | select(.id == $id)' >/dev/null 2>&1 || {
      echo "[WARNING] Model qwopus36-27b not found in catalog. Skipping MTP benchmark." >&2
    } || {
      echo "[model] Model qwopus36-27b confirmed in catalog"
      echo ""

      # Run 5 MTP samples and collect acceptance rates
      MTP_SAMPLES=5
      echo "[mtp] Running ${MTP_SAMPLES} samples (max_tokens=${MTP_BENCH_MAX_TOKENS}) ..."
      echo ""

      for i in $(seq 1 "${MTP_SAMPLES}"); do
        echo "--- Sample ${i}/${MTP_SAMPLES} ---"
        START_TIME=$(date +%s%N)

        resp=$(curl -sS --connect-timeout "$CURL_CONNECT" --max-time "$CURL_MAX_TIME" \
          -X POST "${LLAMA_SWAP_URL}/v1/chat/completions" \
          -H "Content-Type: application/json" \
          -d $(jq -n \
            --arg model "qwopus36-27b" \
            --arg prompt "$MTP_BENCH_PROMPT" \
            --argjson max "$MTP_BENCH_MAX_TOKENS" \
            '{
              model: $model,
              messages: [{role: "user", content: $prompt}],
              max_tokens: $max,
              stream: false
            }') \
          -w '\n%{http_code}')

        END_TIME=$(date +%s%N)
        http=$(printf '%s' "$resp" | tail -n1)
        body=$(printf '%s' "$resp" | sed '$d')

        if [[ "$http" == "200" ]]; then
          completion_tokens=$(echo "$body" | jq -r '.usage.completion_tokens // 0')
          prompt_tokens=$(echo "$body" | jq -r '.usage.prompt_tokens // 0')
          elapsed_ms=$(( (END_TIME - START_TIME) / 1000000 ))
          if [[ "$elapsed_ms" -gt 0 ]]; then
            tps=$(echo "scale=1; ${completion_tokens} * 1000 / ${elapsed_ms}" | bc)
          else
            tps="N/A"
          fi
          echo "OK sample=${i} HTTP=${http} prompt_tokens=${prompt_tokens} completion_tokens=${completion_tokens} elapsed=${elapsed_ms}ms tps=${tps}"
        else
          echo "FAIL sample=${i} HTTP=${http}"
        fi
        echo ""
      done

      # Show acceptance rate from server logs
      echo "[mtp] Acceptance rates from server logs (last 500 lines):"
      docker compose -f "${ROOT}/docker-compose/swap-local-config9.yaml" logs --tail=500 2>/dev/null | \
        grep -i "speculative decoding" | tail -5 || echo "  (no speculative decoding logs found — check --perf flag in config)"
      echo ""
    }
  }
fi

echo "====== All config9 benchmarks complete ======"

