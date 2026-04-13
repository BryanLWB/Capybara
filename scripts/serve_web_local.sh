#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-3006}"
APP_API_DOMAIN="${APP_API_DEFAULT_DOMAIN:-http://127.0.0.1:8787}"

cd "${ROOT_DIR}"

flutter build web \
  --no-wasm-dry-run \
  --dart-define=APP_CONFIG_URLS= \
  --dart-define=APP_API_DEFAULT_DOMAIN="${APP_API_DOMAIN}"

exec python3 -m http.server "${PORT}" --bind "${HOST}" --directory build/web
