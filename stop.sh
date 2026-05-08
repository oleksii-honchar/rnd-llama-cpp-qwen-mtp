#!/usr/bin/env bash
# Stop the llama-swap container.
# Usage: ./stop.sh
set -euo pipefail

echo "[stop] Stopping llama-swap container..."
docker stop llama-swap 2>/dev/null && echo "[stop] Container stopped."
docker rm -f llama-swap 2>/dev/null && echo "[stop] Container removed."
echo "[stop] Done."
