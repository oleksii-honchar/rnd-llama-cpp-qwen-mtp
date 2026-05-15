#!/usr/bin/env bash
# Smoke: config-10 — Qwen3.6-27B Q6_K with DFlash speculative decoding (BeeLlama, turbo4/turbo3_tcq KV).
#
# Chat prompt: smoke-samples/chat-prompt.txt when present (default dir: llama-swap/smoke-samples). Override: SMOKE_SAMPLES_DIR=...
# Logs full user prompt and full assistant text (content, or reasoning_content if content is empty). Override cap: SMOKE_CHAT_MAX_TOKENS=...
#
# Usage (from mammoth-lan/llama-swap):
#   ./scripts/smoke-config10.sh
# Optional: LLAMA_SWAP_URL=http://host:8014 ./scripts/smoke-config10.sh
#
# Prereq: stack running (e.g. ./start.sh config-10).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${SWAP_ROOT}"

SMOKE_SAMPLES_DIR="${SMOKE_SAMPLES_DIR:-${SWAP_ROOT}/smoke-samples}"

LLAMA_SWAP_URL="${LLAMA_SWAP_URL:-http://localhost:8014}"
CURL_CONNECT="${CURL_CONNECT:-15}"
# First load of Q6_K + DFlash drafter can exceed 120s on cold GPU
CURL_MAX_TIME="${CURL_MAX_TIME:-300}"
SMOKE_CHAT_MAX_TOKENS="${SMOKE_CHAT_MAX_TOKENS:-8192}"
CHAT_PROMPT="${SMOKE_CHAT_PROMPT:-Reply with exactly the word ok and nothing else.}"
if [[ -f "${SMOKE_SAMPLES_DIR}/chat-prompt.txt" ]]; then
  CHAT_PROMPT=$(<"${SMOKE_SAMPLES_DIR}/chat-prompt.txt" tr -d '\r')
fi

# Must match configs/config-10.yaml: keys under `models:` (GET /v1/models lists primaries; aliases optional).
MODEL_IDS_IN_CATALOG=(
  qwen36-27b
)

# Primaries + every `aliases:` entry from config-10.
MODEL_IDS_CHAT=(
  qwen36-27b
  qwen36-27b-precise
  qwen36-27b-instruct
)

command -v jq >/dev/null 2>&1 || { echo "smoke-config10.sh: jq required" >&2; exit 1; }

# Exact string sent as messages[0].content (matches json_chat_body).
smoke_chat_prompt_text() {
  if [[ -f "${SMOKE_SAMPLES_DIR}/chat-prompt.txt" ]]; then
    jq -n --rawfile p "${SMOKE_SAMPLES_DIR}/chat-prompt.txt" -r '$p | rtrimstr("\n")'
  else
    printf '%s' "$CHAT_PROMPT"
  fi
}

json_chat_body() {
  local model=$1
  if [[ -f "${SMOKE_SAMPLES_DIR}/chat-prompt.txt" ]]; then
    jq -n --rawfile p "${SMOKE_SAMPLES_DIR}/chat-prompt.txt" --arg model "$model" --argjson max "$SMOKE_CHAT_MAX_TOKENS" \
      '{
        model: $model,
        messages: [{role: "user", content: ($p | rtrimstr("\n"))}],
        max_tokens: $max,
        stream: false
      }'
  else
    jq -n \
      --arg model "$model" \
      --arg prompt "$CHAT_PROMPT" \
      --argjson max "$SMOKE_CHAT_MAX_TOKENS" \
      '{
        model: $model,
        messages: [{role: "user", content: $prompt}],
        max_tokens: $max,
        stream: false
      }'
  fi
}

call_chat() {
  local model=$1
  local resp http body _c
  local prompt_text
  prompt_text="$(smoke_chat_prompt_text)"
  echo "========== model_under_test: ${model} =========="
  echo "--- POST /v1/chat/completions (max_tokens=${SMOKE_CHAT_MAX_TOKENS}) ---"
  echo "user:"
  printf '%s\n' "$prompt_text"
  echo "--"
  resp=$(curl -sS --connect-timeout "$CURL_CONNECT" --max-time "$CURL_MAX_TIME" \
    -X POST "${LLAMA_SWAP_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$(json_chat_body "$model")" \
    -w '\n%{http_code}')
  http=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
  [[ "$http" == "200" ]] || {
    echo "FAIL chat model=${model} HTTP ${http} ${body}" >&2
    return 1
  }
  echo "OK chat model=${model} HTTP ${http}"
  _c=$(echo "$body" | jq -r '.choices[0].message.content // ""')
  if [[ -n "${_c//[[:space:]]/}" ]]; then
    echo "assistant [${model}]:"
    printf '%s\n' "$_c"
  elif echo "$body" | jq -e '(.choices[0].message.reasoning_content // "") | length > 0' >/dev/null 2>&1; then
    echo "(note: model=${model} message.content empty; printing full reasoning_content)" >&2
    echo "assistant (reasoning_content) [${model}]:"
    echo "$body" | jq -r '.choices[0].message.reasoning_content // empty'
  else
    echo "assistant [${model}]: (empty content and reasoning_content)" >&2
    echo "$body" | jq -c '.choices[0].message? // empty' >&2
  fi
  echo "$body" | jq -r --arg m "$model" 'if .usage then "usage [model=\($m)]: prompt_tokens=\(.usage.prompt_tokens // 0) completion_tokens=\(.usage.completion_tokens // 0) total_tokens=\(.usage.total_tokens // 0)" else "usage [model=\($m)]: (missing)" end'
  echo ""
}

echo "=== smoke mammoth config-10 (${LLAMA_SWAP_URL}) ==="
echo "samples: ${SMOKE_SAMPLES_DIR}"

MODELS_JSON=$(curl -sf --connect-timeout "$CURL_CONNECT" --max-time 60 "${LLAMA_SWAP_URL}/v1/models") || {
  echo "FAIL /v1/models" >&2
  exit 1
}

for id in "${MODEL_IDS_IN_CATALOG[@]}"; do
  echo "$MODELS_JSON" | jq -e --arg id "$id" '.data[] | select(.id == $id)' >/dev/null 2>&1 || {
    echo "FAIL model not listed: $id" >&2
    exit 1
  }
done

for id in "${MODEL_IDS_CHAT[@]}"; do
  call_chat "$id"
done

echo "=== smoke passed ==="
