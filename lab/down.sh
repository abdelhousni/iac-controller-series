#!/usr/bin/env bash
# Stops the lab. With --wipe, also deletes its volumes and lab/.env, so the
# next lab/up.sh starts from nothing.
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = --wipe ]; then
  docker compose down -v
  rm -f .env
else
  docker compose down
fi
