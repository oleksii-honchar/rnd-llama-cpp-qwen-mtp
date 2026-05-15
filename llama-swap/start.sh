#!/usr/bin/env bash
# Start llama-swap (config-7).
# Usage:
#   ./start.sh                    # default config-7
#   ./start.sh config-4           # Qwopus 27B/9B + Gemma 4 31B + Qwen heretic + Qwen3.6 35B (matrix)
#   ./start.sh config-5           # Qwen3.6-35B-A3B-TQ3_4S TurboQuant
#   ./start.sh config-6           # Nepotism FLUX (sd-server image generation)
#   ./start.sh config-7           # Qwopus3.6-27B Q4_K_M + Qwen3.6-35B-A3B Claude-4.6-Opus-Reasoning-Distilled Q4_K_M
#   ./start.sh config-8           # Qwopus3.6-27B GGUF Q6_K via vLLM + MTP (builds & starts vLLM + llama-swap, experimental)
#   ./start.sh config-9           # Qwopus3.6-27B-v1-preview-MTP-Q6_K with native MTP speculative decoding (transplant)
#   ./start.sh config-10          # Qwen3.6-27B Q6_K with DFlash speculative decoding (BeeLlama fork, turbo4/turbo3_tcq KV)
#   ./start.sh --list|-l          # list supported configs
set -euo pipefail

SWAP_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="${SWAP_ROOT}/scripts"
DEFAULT_CONFIG="config-9"

list_configs() {
  echo "Available configs (scripts):" >&2
  echo "  - config-4  (configs/config-4.yaml) — Qwopus 27B/9B + Gemma 4 31B + Qwen heretic + Qwen3.6 35B (matrix)" >&2
  echo "  - config-5  (configs/config-5.yaml) — Qwen3.6-35B-A3B-TQ3_4S TurboQuant" >&2
  echo "  - config-6  (configs/config-6.yaml) — Nepotism FLUX (sd-server image generation)" >&2
  echo "  - config-7  (configs/config-7.yaml) - Qwopus3.6-27B Q4_K_M + Qwen3.6-35B-A3B Claude-4.6-Opus-Reasoning-Distilled Q4_K_M" >&2
  echo "  - config-8  (configs/config-8.yaml) — Qwopus3.6-27B GGUF Q6_K via vLLM + MTP (builds & starts vLLM + llama-swap, experimental)" >&2
  echo "  - config-9  (configs/config-9.yaml) — [default] Qwopus3.6-27B-v1-preview-MTP-Q6_K with native MTP speculative decoding (transplant)" >&2
  echo "  - config-10 (configs/config-10.yaml) — Qwen3.6-27B Q6_K with DFlash speculative decoding (BeeLlama fork, turbo4/turbo3_tcq KV)" >&2
}

FIRST_ARG="${1:-}"

if [[ "${FIRST_ARG}" == "--list" || "${FIRST_ARG}" == "-l" ]]; then
  list_configs
  exit 0
fi

if [[ -z "${FIRST_ARG}" ]]; then
  CONFIG="${DEFAULT_CONFIG}"
  echo "No config specified. Using default: ${CONFIG}" >&2
else
  CONFIG="${FIRST_ARG}"
fi

case "${CONFIG}" in
  config-4)
    RUNNER="${SCRIPTS_DIR}/swap.start.config4.sh"
    ;;
  config-5)
    RUNNER="${SCRIPTS_DIR}/swap.start.config5.sh"
    ;;
  config-6)
    RUNNER="${SCRIPTS_DIR}/swap.start.config6.sh"
    ;;
  config-7)
    RUNNER="${SCRIPTS_DIR}/swap.start.config7.sh"
    ;;
  config-8)
    RUNNER="${SCRIPTS_DIR}/swap.start.config8.sh"
    ;;
  config-9)
    RUNNER="${SCRIPTS_DIR}/swap.start.config9.sh"
    ;;
  config-10)
    RUNNER="${SCRIPTS_DIR}/swap.start.config10.sh"
    ;;
  *)
    echo "Invalid config name: ${CONFIG}." >&2
    list_configs
    exit 1
    ;;
esac

if [[ ! -f "${RUNNER}" ]]; then
  echo "No start script for config: ${CONFIG}." >&2
  echo "Expected: ${RUNNER}" >&2
  exit 1
fi

exec "${RUNNER}" "${@:2}"
