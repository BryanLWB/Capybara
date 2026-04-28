#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_TEMPLATE="${ROOT_DIR}/deploy/xboard/shared.env.template"
SHARED_CONFIG_FILE="${XBOARD_SHARED_CONFIG_FILE:-${ROOT_DIR}/.runtime/xboard/shared.env}"

usage() {
  cat <<EOF >&2
Usage: $0 <target-name> <runtime-env-path> <base-template-path> [app-url]
EOF
  exit 1
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
fi

TARGET_NAME="$1"
RUNTIME_ENV_PATH="$2"
BASE_TEMPLATE_PATH="$3"
APP_URL="${4:-}"

if [[ ! -f "${BASE_TEMPLATE_PATH}" ]]; then
  echo "Missing Xboard base template: ${BASE_TEMPLATE_PATH}" >&2
  exit 1
fi

mkdir -p "$(dirname "${RUNTIME_ENV_PATH}")" "$(dirname "${SHARED_CONFIG_FILE}")"

if [[ ! -f "${SHARED_CONFIG_FILE}" ]]; then
  cp "${SHARED_TEMPLATE}" "${SHARED_CONFIG_FILE}"
  echo "Created shared Xboard config at ${SHARED_CONFIG_FILE}. Edit it before deployment if needed." >&2
fi

if [[ ! -f "${RUNTIME_ENV_PATH}" ]]; then
  cp "${BASE_TEMPLATE_PATH}" "${RUNTIME_ENV_PATH}"
fi

ensure_trailing_newline() {
  local file="$1"
  local last_char=""

  if [[ ! -s "${file}" ]]; then
    return
  fi

  last_char="$(tail -c1 "${file}" 2>/dev/null || true)"
  if [[ -n "${last_char}" ]]; then
    printf '\n' >> "${file}"
  fi
}

upsert_env() {
  local key="$1"
  local value="$2"
  local file="$3"

  if grep -q "^${key}=" "${file}"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "${file}"
    rm -f "${file}.bak"
  else
    ensure_trailing_newline "${file}"
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

set -a
. "${SHARED_CONFIG_FILE}"
set +a

[[ -n "${APP_URL}" ]] && upsert_env APP_URL "${APP_URL}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_DB_CONNECTION:-}" ]] && upsert_env DB_CONNECTION "${XBOARD_DB_CONNECTION}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_DB_HOST:-}" ]] && upsert_env DB_HOST "${XBOARD_DB_HOST}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_DB_PORT:-}" ]] && upsert_env DB_PORT "${XBOARD_DB_PORT}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_DB_DATABASE:-}" ]] && upsert_env DB_DATABASE "${XBOARD_DB_DATABASE}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_DB_USERNAME:-}" ]] && upsert_env DB_USERNAME "${XBOARD_DB_USERNAME}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_DB_PASSWORD:-}" ]] && upsert_env DB_PASSWORD "${XBOARD_DB_PASSWORD}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_CACHE_DRIVER:-}" ]] && upsert_env CACHE_DRIVER "${XBOARD_CACHE_DRIVER}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_QUEUE_CONNECTION:-}" ]] && upsert_env QUEUE_CONNECTION "${XBOARD_QUEUE_CONNECTION}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_SESSION_DRIVER:-}" ]] && upsert_env SESSION_DRIVER "${XBOARD_SESSION_DRIVER}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_ENABLE_SQLITE:-}" ]] && upsert_env ENABLE_SQLITE "${XBOARD_ENABLE_SQLITE}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_ENABLE_REDIS:-}" ]] && upsert_env ENABLE_REDIS "${XBOARD_ENABLE_REDIS}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_APP_NAME:-}" ]] && upsert_env APP_NAME "${XBOARD_APP_NAME}" "${RUNTIME_ENV_PATH}"
upsert_env MAIL_DRIVER "smtp" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_MAIL_HOST:-}" ]] && upsert_env MAIL_HOST "${XBOARD_MAIL_HOST}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_MAIL_PORT:-}" ]] && upsert_env MAIL_PORT "${XBOARD_MAIL_PORT}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_MAIL_ENCRYPTION:-}" ]] && upsert_env MAIL_ENCRYPTION "${XBOARD_MAIL_ENCRYPTION}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_MAIL_USERNAME:-}" ]] && upsert_env MAIL_USERNAME "${XBOARD_MAIL_USERNAME}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_MAIL_PASSWORD:-}" ]] && upsert_env MAIL_PASSWORD "${XBOARD_MAIL_PASSWORD}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_MAIL_FROM_ADDRESS:-}" ]] && upsert_env MAIL_FROM_ADDRESS "${XBOARD_MAIL_FROM_ADDRESS}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_APP_NAME:-}" ]] && upsert_env MAIL_FROM_NAME "${XBOARD_APP_NAME}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_REDIS_HOST:-}" ]] && upsert_env REDIS_HOST "${XBOARD_REDIS_HOST}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_REDIS_PASSWORD:-}" ]] && upsert_env REDIS_PASSWORD "${XBOARD_REDIS_PASSWORD}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_REDIS_PORT:-}" ]] && upsert_env REDIS_PORT "${XBOARD_REDIS_PORT}" "${RUNTIME_ENV_PATH}"
[[ -n "${XBOARD_SERVER_WS_URL:-}" ]] && upsert_env SERVER_WS_URL "${XBOARD_SERVER_WS_URL}" "${RUNTIME_ENV_PATH}"

echo "Prepared ${TARGET_NAME} runtime env at ${RUNTIME_ENV_PATH}"
