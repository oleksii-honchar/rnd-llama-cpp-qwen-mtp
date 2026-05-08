#!/usr/bin/env bash
# Start llama-cpp image with swap-local-config9.yaml (config-9: Qwopus3.6-27B-v1-preview-MTP-Q6_K with native MTP speculative decoding).
# Usage: ./swap.start.config9.sh [--re-build]
#   --re-build    Force a full rebuild with --no-cache
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${ROOT}/docker-compose/swap-local-config9.yaml"

REBUILD_FLAG=""
if [[ "${1:-}" == "--re-build" ]]; then
  REBUILD_FLAG="--no-cache"
  echo "------ Re-build requested: will build with --no-cache"
fi

echo "------ Starting llama-swap (swap.config9: Qwopus3.6-27B-v1-preview-MTP Q6_K + Q4_K_M with native MTP speculative decoding)"

. "${ROOT}/scripts/ensure-models-config9.sh"

docker network inspect mammoth-net >/dev/null 2>&1 || docker network create mammoth-net

cd "$ROOT"

if [[ -n "$REBUILD_FLAG" ]]; then
  echo "------ Stopping and removing old container..."
  docker compose -f "$COMPOSE_FILE" --project-directory "$ROOT" down
  echo "------ Building image with --no-cache..."
  docker compose -f "$COMPOSE_FILE" --project-directory "$ROOT" build --no-cache
fi

echo "------ Starting container..."
docker compose -f "$COMPOSE_FILE" --project-directory "$ROOT" up -d --build

echo "------ Done. API: http://localhost:8014/v1"
