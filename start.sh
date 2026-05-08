#!/usr/bin/env bash
# One-command start: download models, transplant MTP, and launch the server.
# Usage: ./start.sh [--re-build] [--force]
#   --re-build    Force a full Docker image rebuild with --no-cache
#   --force       Force re-download of all models (including transplant)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLAMA_SWAP="${SCRIPT_DIR}/llama-swap"

# Forward flags to the underlying start script
FLAGS=""
for arg in "$@"; do
  case "$arg" in
    --re-build|--force) FLAGS="${FLAGS} ${arg}" ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

bash "${LLAMA_SWAP}/scripts/swap.start.config9.sh" $FLAGS
