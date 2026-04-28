#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDFLARE_SECRETS_FILE="${CLOUDFLARE_SECRETS_FILE:-${ROOT_DIR}/.runtime/production/cloudflare-prod.env}"

if [[ -f "${CLOUDFLARE_SECRETS_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${CLOUDFLARE_SECRETS_FILE}"
  set +a
fi

PAGES_PROJECT_NAME="${PAGES_PROJECT_NAME:-capybara-web-prod}"
PAGES_BRANCH="${PAGES_BRANCH:-main}"
WEB_DOMAIN="${WEB_DOMAIN:-www.kapi-net.com}"
API_DOMAIN="${API_DOMAIN:-api.kapi-net.com}"
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-${CF_ACCOUNT_ID:-}}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-${CF_API_TOKEN:-}}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/web}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd flutter
require_cmd npx
require_cmd zip

if [[ -z "${CLOUDFLARE_ACCOUNT_ID}" ]]; then
  echo "Set CLOUDFLARE_ACCOUNT_ID (or CF_ACCOUNT_ID)." >&2
  exit 1
fi

if [[ -z "${CLOUDFLARE_API_TOKEN}" ]]; then
  echo "Set CLOUDFLARE_API_TOKEN (or CF_API_TOKEN)." >&2
  exit 1
fi

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD}" != "1" ]]; then
  APP_CONFIG_URLS= \
  APP_API_DEFAULT_DOMAIN="https://${API_DOMAIN}" \
    bash "${ROOT_DIR}/scripts/build_web_release.sh"
fi

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "Missing Pages build directory: ${BUILD_DIR}" >&2
  exit 1
fi

if [[ ! -f "${BUILD_DIR}/index.html" ]]; then
  echo "Pages build directory does not contain index.html: ${BUILD_DIR}" >&2
  exit 1
fi

zip_path="/tmp/${PAGES_PROJECT_NAME}-pages.zip"
rm -f "${zip_path}"
(
  cd "${BUILD_DIR}"
  zip -qr "${zip_path}" .
)

echo "Prepared Pages bundle: ${zip_path}"
echo "Expected site: https://${WEB_DOMAIN}/"
echo "Project: ${PAGES_PROJECT_NAME}"
echo "Branch: ${PAGES_BRANCH}"

if [[ "${SKIP_DEPLOY}" == "1" ]]; then
  exit 0
fi

export CLOUDFLARE_ACCOUNT_ID
export CLOUDFLARE_API_TOKEN

npx --yes wrangler pages deploy \
  "${BUILD_DIR}" \
  --project-name="${PAGES_PROJECT_NAME}" \
  --branch="${PAGES_BRANCH}"
