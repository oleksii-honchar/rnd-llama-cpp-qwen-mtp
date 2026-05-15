#!/usr/bin/env bash
# Stop any running llama-swap container (any config).
set -euo pipefail

CONTAINER_NAME="llama-swap"

echo "------ Stopping llama-swap"

docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "------ Done."
