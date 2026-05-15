#!/usr/bin/env bash
# Stream or print logs from the llama-swap container (default name: llama-swap).
# With config **logToStdout: "both"**, this includes **llama-server** lines for whichever model is loaded,
# interleaved with llama-swap proxy lines (swap/load/errors).
#
# Usage:
#   ./logs.sh              # last 200 lines (default when no args)
#   ./logs.sh -f --tail 200
#   ./logs.sh --since 30m
#   ./logs.sh --tail 5000  # full docker logs API (no follow)
#
# Override container name:
#   LLAMA_SWAP_CONTAINER_NAME=my-swap ./logs.sh -f
set -euo pipefail

CONTAINER="${LLAMA_SWAP_CONTAINER_NAME:-llama-swap}"

if [[ $# -eq 0 ]]; then
  exec docker logs --tail 200 "$CONTAINER"
fi
exec docker logs "$@" "$CONTAINER"
