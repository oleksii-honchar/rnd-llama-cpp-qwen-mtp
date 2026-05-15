#!/usr/bin/env bash
# Restart llama-swap (default: swap.config4 via ./start.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Restarting llama-swap (default: swap.config4)..."
"$SCRIPT_DIR/stop.sh"
"$SCRIPT_DIR/start.sh"
