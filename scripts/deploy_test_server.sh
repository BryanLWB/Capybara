#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_XBOARD_CONFIG="${ROOT_DIR}/.runtime/xboard/shared.env"

DEPLOY_HOST="${DEPLOY_HOST:?Set DEPLOY_HOST, for example root@178.104.242.246}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/capybara-test-stack}"
ROOT_DOMAIN="${ROOT_DOMAIN:-kapi-net.com}"
WWW_DOMAIN="${WWW_DOMAIN:-www.kapi-net.com}"
ADMIN_ACCOUNT="${ADMIN_ACCOUNT:-admin@demo.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?Set ADMIN_PASSWORD for the initial test admin}"
RESET_DATA="${RESET_DATA:-0}"
XBOARD_IMAGE="${XBOARD_IMAGE:-ghcr.io/cedar2025/xboard:new}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd flutter
require_cmd rsync
require_cmd ssh

if [[ ! -f "${SHARED_XBOARD_CONFIG}" ]]; then
  echo "Missing shared Xboard config: ${SHARED_XBOARD_CONFIG}" >&2
  echo "Create it from deploy/xboard/shared.env.template first." >&2
  exit 1
fi

cd "${ROOT_DIR}"

XBOARD_IMAGE="${XBOARD_IMAGE}" bash "${ROOT_DIR}/scripts/prepare_local_xboard.sh"
APP_CONFIG_URLS= \
APP_API_DEFAULT_DOMAIN="https://${WWW_DOMAIN}" \
  bash "${ROOT_DIR}/scripts/build_web_release.sh"

ssh "${DEPLOY_HOST}" "mkdir -p \
  '${DEPLOY_PATH}/backend' \
  '${DEPLOY_PATH}/build' \
  '${DEPLOY_PATH}/deploy/test-server/static/payment-icons' \
  '${DEPLOY_PATH}/docker' \
  '${DEPLOY_PATH}/scripts' \
  '${DEPLOY_PATH}/upstreams' \
  '${DEPLOY_PATH}/.local' \
  '${DEPLOY_PATH}/.runtime/xboard' \
  '${DEPLOY_PATH}/.runtime/test-server'"

rsync -az --delete \
  --exclude='.dart_tool' \
  "${ROOT_DIR}/backend/app_api/" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/backend/app_api/"

rsync -az --delete \
  "${ROOT_DIR}/build/web/" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/build/web/"

rsync -az --delete \
  "${ROOT_DIR}/deploy/test-server/" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/deploy/test-server/"

rsync -az --delete \
  "${ROOT_DIR}/docker/test-server.compose.yaml" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/docker/test-server.compose.yaml"

rsync -az \
  "${ROOT_DIR}/scripts/ensure_xboard_runtime_env.sh" \
  "${ROOT_DIR}/scripts/xboard_sync_settings.php" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/scripts/"

rsync -az --delete \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.env' \
  --exclude='.docker/.data' \
  --exclude='storage/logs' \
  "${ROOT_DIR}/upstreams/xboard/" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/upstreams/xboard/"

rsync -az --delete \
  "${ROOT_DIR}/.local/xboard-admin-assets/" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/.local/xboard-admin-assets/"

rsync -az \
  "${SHARED_XBOARD_CONFIG}" \
  "${DEPLOY_HOST}:${DEPLOY_PATH}/.runtime/xboard/shared.env"

ssh "${DEPLOY_HOST}" "ROOT_DOMAIN='${ROOT_DOMAIN}' WWW_DOMAIN='${WWW_DOMAIN}' ADMIN_ACCOUNT='${ADMIN_ACCOUNT}' ADMIN_PASSWORD='${ADMIN_PASSWORD}' RESET_DATA='${RESET_DATA}' DEPLOY_PATH='${DEPLOY_PATH}' bash -s" <<'EOF'
set -euo pipefail

cd "${DEPLOY_PATH}"

mkdir -p .runtime/test-server/caddy-data \
  .runtime/test-server/caddy-config \
  .runtime/test-server/xboard-data

if [[ "${RESET_DATA}" == "1" ]]; then
  rm -rf .runtime/test-server/xboard-data
  rm -f .runtime/test-server/xboard.env
fi

bash scripts/ensure_xboard_runtime_env.sh \
  "test-server" \
  ".runtime/test-server/xboard.env" \
  "deploy/test-server/xboard.env.template" \
  "https://${ROOT_DOMAIN}"

if [[ -f /opt/capybara-xboard/docker-compose.yml ]]; then
  (cd /opt/capybara-xboard && docker compose down) || true
fi

if [[ -f /opt/capybara-frank-web/docker-compose.yml ]]; then
  (cd /opt/capybara-frank-web && docker compose down) || true
fi

systemctl disable --now caddy >/dev/null 2>&1 || true

docker compose -f docker/test-server.compose.yaml down --remove-orphans || true
docker compose -f docker/test-server.compose.yaml up -d redis

NEEDS_INSTALL=0
if [[ "${RESET_DATA}" == "1" ]]; then
  NEEDS_INSTALL=1
elif [[ ! -f .runtime/test-server/xboard-data/database.sqlite ]]; then
  NEEDS_INSTALL=1
elif ! grep -q '^INSTALLED=1' .runtime/test-server/xboard.env; then
  NEEDS_INSTALL=1
fi

if [[ "${NEEDS_INSTALL}" == "1" ]]; then
  docker compose -f docker/test-server.compose.yaml run --rm --entrypoint sh \
    -e ENABLE_SQLITE=true \
    -e ENABLE_REDIS=true \
    -e ADMIN_ACCOUNT="${ADMIN_ACCOUNT}" \
    xboard-web -lc 'php artisan xboard:install' </dev/null
fi

docker compose -f docker/test-server.compose.yaml run --rm --entrypoint sh \
  -e ADMIN_ACCOUNT="${ADMIN_ACCOUNT}" \
  -e ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  xboard-web -lc 'php artisan reset:password "$(printenv ADMIN_ACCOUNT)" "$(printenv ADMIN_PASSWORD)"' </dev/null

if ! grep -q "^APP_URL=https://${ROOT_DOMAIN}\$" .runtime/test-server/xboard.env; then
  echo "Failed to persist APP_URL in xboard.env." >&2
  exit 1
fi

SYNC_STATUS="$(docker compose -f docker/test-server.compose.yaml run --rm --entrypoint sh \
  xboard-web -lc "php /codex-scripts/xboard_sync_settings.php >/dev/null && php artisan tinker --execute='echo ((admin_setting(\"app_url\") === env(\"APP_URL\")) && (admin_setting(\"email_host\") === env(\"MAIL_HOST\")) && (admin_setting(\"app_name\") === env(\"APP_NAME\"))) ? \"ok\" : \"fail\";'" \
  </dev/null \
  | tr -d "\r")"

if [[ "${SYNC_STATUS}" != *ok* ]]; then
  echo "Failed to persist Xboard app/mail settings." >&2
  exit 1
fi

PASSWORD_STATUS="$(docker compose -f docker/test-server.compose.yaml run --rm --entrypoint sh \
  -e ADMIN_ACCOUNT="${ADMIN_ACCOUNT}" \
  -e ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  xboard-web -lc "php artisan tinker --execute='use App\Models\User; \$user = User::byEmail(getenv(\"ADMIN_ACCOUNT\"))->first(); echo (\$user && password_verify(getenv(\"ADMIN_PASSWORD\"), \$user->password)) ? \"ok\" : \"fail\";'" \
  </dev/null \
  | tr -d "\r")"

if [[ "${PASSWORD_STATUS}" != *ok* ]]; then
  echo "Failed to reset admin password." >&2
  exit 1
fi

docker compose -f docker/test-server.compose.yaml up -d --remove-orphans --force-recreate
EOF

echo "Deployment finished."
echo "Web: https://${WWW_DOMAIN}/"
echo "Panel: https://${ROOT_DOMAIN}/"
echo "Admin account: ${ADMIN_ACCOUNT}"
