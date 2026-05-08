#!/usr/bin/env bash
# Restart the llama-swap container: stop, then start.
# Usage: ./restart.sh [--re-build] [--force]
#   --re-build    Force a full Docker image rebuild with --no-cache
#   --force       Force re-download of all models (including transplant)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[restart] Stopping..."
bash "${SCRIPT_DIR}/stop.sh"

echo "[restart] Starting..."
bash "${SCRIPT_DIR}/start.sh" "$@"

echo "[restart] Done."
