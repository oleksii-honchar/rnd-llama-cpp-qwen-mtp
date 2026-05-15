#!/usr/bin/env bash
# llama-swap healthcheck: verify API is up and (optionally) that /v1/models lists models from a config.
# When a config is given, by default sends one request per model (embedding or chat) to wake/warm and verify.
# Usage:
#   ./healthcheck.sh              # check BASE_URL/v1/models returns 200 only
#   ./healthcheck.sh config-4     # check listing + call each model (warmup)
#   ./healthcheck.sh config-4 --no-warmup   # check listing only, no model calls
#   ./healthcheck.sh --all       # run check for each config (with warmup per config)
#   ./healthcheck.sh -v [config] # verbose (default)
#   ./healthcheck.sh -q [config] # quiet
# Exit 0 if all pass, 1 otherwise.
set -euo pipefail

SWAP_ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIGS_DIR="${SWAP_ROOT}/configs"
LLAMA_SWAP_URL="${LLAMA_SWAP_URL:-http://localhost:8014}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"
WARMUP_TIMEOUT="${WARMUP_TIMEOUT:-120}"

VERBOSE=1
# When a config is specified, warmup (call each model) by default; use --no-warmup to skip
WARMUP=-1
RUN_ALL=0
CONFIG_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)     VERBOSE=1; shift ;;
    -q|--quiet)       VERBOSE=0; shift ;;
    -w|--warmup)      WARMUP=1; shift ;;
    -n|--no-warmup)   WARMUP=0; shift ;;
    --all)            RUN_ALL=1; shift ;;
    -*)               shift ;;  # ignore unknown flags
    *)                CONFIG_ARG="$1"; shift ;;
  esac
done

# Default: warmup when a config or --all is used, no warmup when only checking /v1/models
if [[ $WARMUP -eq -1 ]]; then
  if [[ $RUN_ALL -eq 1 || -n "${CONFIG_ARG:-}" ]]; then
    WARMUP=1
  else
    WARMUP=0
  fi
fi

[[ -n "${HEALTHCHECK_VERBOSE:-}" ]] && VERBOSE=1

# Extract model keys from a llama-swap config YAML (top-level keys under "models:")
# Only lines that look like "  model-id:" (2-space indent, id contains digit or dot to skip "name", "cmd", etc.)
get_expected_models() {
  local config_path="$1"
  if [[ ! -f "$config_path" ]]; then
    echo "Config not found: $config_path" >&2
    return 1
  fi
  awk '/^models:/{p=1;next} /^[a-zA-Z]/ && p{exit} p && /^  [a-z0-9.-]+:/{k=$0; gsub(/^  |:.*/,"",k); if(k~/[0-9.]/) print k}' "$config_path"
}

# Fetch /v1/models and return list of model ids (one per line)
fetch_model_ids() {
  curl -sf --connect-timeout "$CURL_TIMEOUT" "${LLAMA_SWAP_URL}/v1/models" -o - 2>/dev/null | \
    (command -v jq >/dev/null 2>&1 && jq -r '.data[]?.id // empty' || cat)
}

# Infer model type from config (rerank | embedding | chat | whisper). Whisper is not warmed up.
get_model_type() {
  local config_path="$1"
  local model_id="$2"
  local id_esc block
  id_esc=$(printf '%s' "$model_id" | sed 's/\./\\./g')
  block=$(awk -v id="$id_esc" '
    $0 ~ "^  " id ":" { p=1; next }
    p && $0 ~ /^  [a-z0-9.-]+:/ { exit }
    p { print }
  ' "$config_path" 2>/dev/null) || true
  if echo "$block" | grep -q '\-\-reranking'; then
    echo "rerank"
  elif echo "$block" | grep -q '\-\-embedding'; then
    echo "embedding"
  elif echo "$block" | grep -q 'whisper-server'; then
    echo "whisper"
  else
    echo "chat"
  fi
}

# Send one minimal request to the model; return 0 if OK, 1 on failure.
# On failure sets WARMUP_LAST_HTTP and WARMUP_LAST_ERR for caller to print.
warmup_model() {
  local model_id="$1"
  local type="$2"
  local out body
  local http_code
  WARMUP_LAST_HTTP=""
  WARMUP_LAST_ERR=""
  if [[ "$type" == "whisper" ]]; then
    if [[ $VERBOSE -eq 1 ]]; then
      echo ""
      echo "    ${model_id}: skip (whisper, no warmup)"
    fi
    return 0
  fi
  if [[ "$type" == "rerank" ]]; then
    out=$(curl -s -w "%{http_code}" --connect-timeout "$CURL_TIMEOUT" --max-time "$WARMUP_TIMEOUT" \
      -X POST "${LLAMA_SWAP_URL}/v1/rerank" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${model_id}\",\"query\":\"warmup\",\"top_n\":1,\"documents\":[\"warmup doc\"]}" 2>/dev/null) || { WARMUP_LAST_HTTP="curl failed"; return 1; }
    http_code="${out: -3}"
    body="${out%???}"
    if [[ "$http_code" != "200" ]]; then
      WARMUP_LAST_HTTP="$http_code"
      WARMUP_LAST_ERR=$(printf '%s' "$body" | jq -r '.error.message // .error.code // empty' 2>/dev/null | head -1)
      return 1
    fi
    if command -v jq >/dev/null 2>&1; then
      jq -e '((.results // .data // []) | length) >= 1' <<< "$body" >/dev/null 2>&1 || return 1
    fi
    return 0
  fi
  if [[ "$type" == "embedding" ]]; then
    out=$(curl -s -w "%{http_code}" --connect-timeout "$CURL_TIMEOUT" --max-time "$WARMUP_TIMEOUT" \
      -X POST "${LLAMA_SWAP_URL}/v1/embeddings" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${model_id}\",\"input\":\"warmup\"}" 2>/dev/null) || { WARMUP_LAST_HTTP="curl failed"; return 1; }
    http_code="${out: -3}"
    body="${out%???}"
    if [[ "$http_code" != "200" ]]; then
      WARMUP_LAST_HTTP="$http_code"
      WARMUP_LAST_ERR=$(printf '%s' "$body" | jq -r '.error.message // .error.code // empty' 2>/dev/null | head -1)
      return 1
    fi
    if command -v jq >/dev/null 2>&1; then
      jq -e '.data[0].embedding | length > 0' <<< "$body" >/dev/null 2>&1 || return 1
    fi
    return 0
  fi
  # chat
  out=$(curl -s -w "%{http_code}" --connect-timeout "$CURL_TIMEOUT" --max-time "$WARMUP_TIMEOUT" \
    -X POST "${LLAMA_SWAP_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"max_tokens\":2}" 2>/dev/null) || { WARMUP_LAST_HTTP="curl failed"; return 1; }
  http_code="${out: -3}"
  body="${out%???}"
  if [[ "$http_code" != "200" ]]; then
    WARMUP_LAST_HTTP="$http_code"
    WARMUP_LAST_ERR=$(printf '%s' "$body" | jq -r '.error.message // .error.code // empty' 2>/dev/null | head -1)
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -e '.choices[0].message' <<< "$body" >/dev/null 2>&1 || return 1
  fi
  return 0
}

FAIL=0
echo "--- llama-swap healthcheck (${LLAMA_SWAP_URL}) ---"

if [[ $RUN_ALL -eq 1 ]]; then
  for cfg in "${CONFIGS_DIR}"/*.yaml; do
    [[ -f "$cfg" ]] || continue
    name=$(basename "$cfg" .yaml)
    echo ""
    echo "Config: ${name}"
    expected=$(get_expected_models "$cfg" | sort -u)
    if [[ -z "$expected" ]]; then
      echo "  No models in config?  SKIP"
      continue
    fi
    actual=$(fetch_model_ids | sort -u)
    if [[ -z "$actual" ]]; then
      echo "  FAIL: /v1/models unreachable or empty"
      FAIL=1
      continue
    fi
    missing=""
    while read -r id; do
      [[ -z "$id" ]] && continue
      if ! echo "$actual" | grep -qFx "$id"; then
        missing="${missing} ${id}"
      fi
    done <<< "$expected"
    if [[ -n "$missing" ]]; then
      echo "  FAIL: missing from /v1/models:${missing}"
      FAIL=1
    else
      echo "  OK (all $(echo "$expected" | wc -l) models listed)"
      [[ $VERBOSE -eq 1 ]] && echo "  Models: $(echo "$expected" | tr '\n' ' ')"
    fi
    if [[ $WARMUP -eq 1 && -z "$missing" ]]; then
      while read -r model_id; do
        [[ -z "$model_id" ]] && continue
        type=$(get_model_type "$cfg" "$model_id")
        echo -n "  Warmup ${model_id} (${type}) ..."
        if warmup_model "$model_id" "$type"; then
          echo " OK"
        else
          echo " FAIL (HTTP ${WARMUP_LAST_HTTP:-?})"
          [[ -n "${WARMUP_LAST_ERR:-}" ]] && echo "      ${WARMUP_LAST_ERR}" >&2
          FAIL=1
        fi
      done <<< "$expected"
    fi
  done
else
  echo -n "1. /v1/models ..."
  actual=$(fetch_model_ids) || true
  if [[ -z "$actual" ]]; then
    echo "  FAIL (unreachable or empty)"
    FAIL=1
  else
    echo "  OK"
    if [[ $VERBOSE -eq 1 ]]; then
      echo "    Models:"
      echo "$actual" | while read -r id; do [[ -n "$id" ]] && echo "      - $id"; done
    fi
  fi

  if [[ -n "${CONFIG_ARG}" ]]; then
    cfg_path="${CONFIGS_DIR}/${CONFIG_ARG}.yaml"
    if [[ "${CONFIG_ARG}" == */* ]] || [[ "${CONFIG_ARG}" == *.* ]]; then
      cfg_path="${CONFIG_ARG}"
    fi
    if [[ -f "$cfg_path" ]]; then
      echo -n "2. Config ${CONFIG_ARG} (expected models) ..."
      expected=$(get_expected_models "$cfg_path" | sort -u)
      actual=$(echo "$actual" | sort -u)
      missing=""
      while read -r id; do
        [[ -z "$id" ]] && continue
        if ! echo "$actual" | grep -qFx "$id"; then
          missing="${missing} ${id}"
        fi
      done <<< "$expected"
      if [[ -n "$missing" ]]; then
        echo "  FAIL (missing:${missing})"
        FAIL=1
      else
        echo "  OK"
        [[ $VERBOSE -eq 1 ]] && echo "    Expected: $(echo "$expected" | tr '\n' ' ')"
      fi
    else
      echo "2. Config ${CONFIG_ARG} ...  SKIP (file not found: ${cfg_path})"
    fi
  fi

  if [[ $WARMUP -eq 1 && $FAIL -eq 0 && -n "${CONFIG_ARG:-}" ]]; then
    cfg_path="${CONFIGS_DIR}/${CONFIG_ARG}.yaml"
    [[ "${CONFIG_ARG}" == */* || "${CONFIG_ARG}" == *.* ]] && cfg_path="${CONFIG_ARG}"
    if [[ -f "${cfg_path}" ]]; then
      expected=$(get_expected_models "$cfg_path" | sort -u)
      echo ""
      echo "3. Warmup (one request per model)"
    while read -r model_id; do
      [[ -z "$model_id" ]] && continue
      type=$(get_model_type "$cfg_path" "$model_id")
      echo -n "   ${model_id} (${type}) ..."
      if warmup_model "$model_id" "$type"; then
        echo " OK"
      else
        echo " FAIL (HTTP ${WARMUP_LAST_HTTP:-?})"
        [[ -n "${WARMUP_LAST_ERR:-}" ]] && echo "      ${WARMUP_LAST_ERR}" >&2
        FAIL=1
      fi
    done <<< "$expected"
    fi
  fi
fi

echo "---"
if [[ $FAIL -eq 0 ]]; then
  echo "All checks passed."
  exit 0
else
  echo "One or more checks failed."
  exit 1
fi
