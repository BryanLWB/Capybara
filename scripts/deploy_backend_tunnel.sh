#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_XBOARD_CONFIG="${ROOT_DIR}/.runtime/xboard/shared.env"
CLOUDFLARE_SECRETS_FILE="${CLOUDFLARE_SECRETS_FILE:-${ROOT_DIR}/.runtime/production/cloudflare-prod.env}"
BACKEND_DB_SECRETS_FILE="${BACKEND_DB_SECRETS_FILE:-${ROOT_DIR}/.runtime/production/backend-db.env}"

if [[ -f "${CLOUDFLARE_SECRETS_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${CLOUDFLARE_SECRETS_FILE}"
  set +a
fi

BACKEND_HOST="${BACKEND_HOST:?Set BACKEND_HOST, for example root@178.104.115.63}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/capybara-backend}"
API_DOMAIN="${API_DOMAIN:-api.kapi-net.com}"
PANEL_DOMAIN="${PANEL_DOMAIN:-panel.kapi-net.com}"
ADMIN_ACCOUNT="${ADMIN_ACCOUNT:-admin@demo.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?Set ADMIN_PASSWORD for the initial admin}"
TUNNEL_TOKEN="${TUNNEL_TOKEN:?Set TUNNEL_TOKEN from Cloudflare Tunnel}"
RESET_DATA="${RESET_DATA:-0}"
XBOARD_IMAGE="${XBOARD_IMAGE:-ghcr.io/cedar2025/xboard:new}"
PREPARE_WEB_BUILD="${PREPARE_WEB_BUILD:-1}"
BACKUP_BEFORE_DEPLOY="${BACKUP_BEFORE_DEPLOY:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_backend_db_secrets() {
  local secrets_dir
  local mysql_password
  local mysql_root_password

  secrets_dir="$(dirname "${BACKEND_DB_SECRETS_FILE}")"
  mkdir -p "${secrets_dir}"

  if [[ -f "${BACKEND_DB_SECRETS_FILE}" ]]; then
    return
  fi

  require_cmd openssl
  mysql_password="$(openssl rand -hex 18)"
  mysql_root_password="$(openssl rand -hex 18)"

  cat > "${BACKEND_DB_SECRETS_FILE}" <<EOF
MYSQL_DATABASE=xboard
MYSQL_USER=xboard
MYSQL_PASSWORD=${mysql_password}
MYSQL_ROOT_PASSWORD=${mysql_root_password}
EOF
  chmod 600 "${BACKEND_DB_SECRETS_FILE}"
  echo "Created backend DB secrets at ${BACKEND_DB_SECRETS_FILE}"
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

ensure_backend_db_secrets

set -a
# shellcheck disable=SC1090
source "${BACKEND_DB_SECRETS_FILE}"
set +a

MYSQL_DATABASE="${MYSQL_DATABASE:-xboard}"
MYSQL_USER="${MYSQL_USER:-xboard}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in ${BACKEND_DB_SECRETS_FILE}}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?Set MYSQL_ROOT_PASSWORD in ${BACKEND_DB_SECRETS_FILE}}"

cd "${ROOT_DIR}"

XBOARD_IMAGE="${XBOARD_IMAGE}" bash "${ROOT_DIR}/scripts/prepare_local_xboard.sh"

if [[ "${BACKUP_BEFORE_DEPLOY}" == "1" ]]; then
  BACKEND_HOST="${BACKEND_HOST}" \
  DEPLOY_PATH="${DEPLOY_PATH}" \
  BACKEND_DB_SECRETS_FILE="${BACKEND_DB_SECRETS_FILE}" \
    bash "${ROOT_DIR}/scripts/backup_backend_mysql.sh"
fi

if [[ "${PREPARE_WEB_BUILD}" == "1" ]]; then
  APP_CONFIG_URLS= \
  APP_API_DEFAULT_DOMAIN="https://${API_DOMAIN}" \
    bash "${ROOT_DIR}/scripts/build_web_release.sh"
fi

ssh "${BACKEND_HOST}" "mkdir -p \
  '${DEPLOY_PATH}/backend' \
  '${DEPLOY_PATH}/deploy/backend-tunnel' \
  '${DEPLOY_PATH}/docker' \
  '${DEPLOY_PATH}/scripts' \
  '${DEPLOY_PATH}/upstreams' \
  '${DEPLOY_PATH}/.local' \
  '${DEPLOY_PATH}/.runtime/xboard' \
  '${DEPLOY_PATH}/.runtime/backend'"

rsync -az --delete \
  --exclude='.dart_tool' \
  "${ROOT_DIR}/backend/app_api/" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/backend/app_api/"

rsync -az --delete \
  "${ROOT_DIR}/docker/backend-tunnel.compose.yaml" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/docker/backend-tunnel.compose.yaml"

rsync -az --delete \
  "${ROOT_DIR}/deploy/backend-tunnel/xboard.env.template" \
  "${ROOT_DIR}/deploy/backend-tunnel/backend-db.env.template" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/deploy/backend-tunnel/"

rsync -az \
  "${ROOT_DIR}/scripts/ensure_xboard_runtime_env.sh" \
  "${ROOT_DIR}/scripts/bootstrap_xboard.php" \
  "${ROOT_DIR}/scripts/reset_xboard_admin_password.php" \
  "${ROOT_DIR}/scripts/check_xboard_admin_password.php" \
  "${ROOT_DIR}/scripts/xboard_sync_settings.php" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/scripts/"

rsync -az --delete \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.env' \
  --exclude='.docker/.data' \
  --exclude='storage/logs' \
  "${ROOT_DIR}/upstreams/xboard/" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/upstreams/xboard/"

rsync -az --delete \
  "${ROOT_DIR}/.local/xboard-admin-assets/" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/.local/xboard-admin-assets/"

rsync -az \
  "${SHARED_XBOARD_CONFIG}" \
  "${BACKEND_HOST}:${DEPLOY_PATH}/.runtime/xboard/shared.env"

ssh "${BACKEND_HOST}" \
  "API_DOMAIN='${API_DOMAIN}' PANEL_DOMAIN='${PANEL_DOMAIN}' ADMIN_ACCOUNT='${ADMIN_ACCOUNT}' ADMIN_PASSWORD='${ADMIN_PASSWORD}' RESET_DATA='${RESET_DATA}' DEPLOY_PATH='${DEPLOY_PATH}' TUNNEL_TOKEN='${TUNNEL_TOKEN}' MYSQL_DATABASE='${MYSQL_DATABASE}' MYSQL_USER='${MYSQL_USER}' MYSQL_PASSWORD='${MYSQL_PASSWORD}' MYSQL_ROOT_PASSWORD='${MYSQL_ROOT_PASSWORD}' bash -s" <<'EOF'
set -euo pipefail

ensure_remote_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y docker.io docker-compose-v2
  systemctl enable --now docker
}

compose_args=(--env-file .runtime/backend/compose.env -f docker/backend-tunnel.compose.yaml)

compose() {
  docker compose "${compose_args[@]}" "$@"
}

write_compose_env() {
  cat > .runtime/backend/compose.env <<ENV
TUNNEL_TOKEN=${TUNNEL_TOKEN}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ENV
  chmod 600 .runtime/backend/compose.env
}

wait_for_mysql() {
  local attempt=0

  while (( attempt < 60 )); do
    if compose exec -T mysql sh -lc 'mysqladmin ping -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --silent' </dev/null >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done

  echo "MySQL did not become healthy in time." >&2
  return 1
}

mysql_has_migrations_table() {
  local output

  output="$(compose exec -T mysql sh -lc 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -Nse "SHOW TABLES LIKE '\''migrations'\''" "$MYSQL_DATABASE" 2>/dev/null || true' </dev/null | tr -d '\r')"
  [[ "${output}" == "migrations" ]]
}

ensure_remote_docker

cd "${DEPLOY_PATH}"
write_compose_env

if [[ "${RESET_DATA}" == "1" ]]; then
  compose down -v --remove-orphans || true
  rm -f .runtime/backend/xboard.env
else
  compose down --remove-orphans || true
fi

XBOARD_DB_CONNECTION="mysql" \
XBOARD_DB_HOST="mysql" \
XBOARD_DB_PORT="3306" \
XBOARD_DB_DATABASE="${MYSQL_DATABASE}" \
XBOARD_DB_USERNAME="${MYSQL_USER}" \
XBOARD_DB_PASSWORD="${MYSQL_PASSWORD}" \
XBOARD_CACHE_DRIVER="redis" \
XBOARD_QUEUE_CONNECTION="redis" \
XBOARD_ENABLE_SQLITE="false" \
XBOARD_ENABLE_REDIS="true" \
XBOARD_REDIS_HOST="/data/redis.sock" \
XBOARD_REDIS_PASSWORD="null" \
XBOARD_REDIS_PORT="0" \
XBOARD_SERVER_WS_URL="wss://${PANEL_DOMAIN}/ws" \
bash scripts/ensure_xboard_runtime_env.sh \
  "backend" \
  ".runtime/backend/xboard.env" \
  "deploy/backend-tunnel/xboard.env.template" \
  "https://${PANEL_DOMAIN}"

compose up -d mysql redis
wait_for_mysql

compose run --rm --entrypoint sh \
  -e BOOTSTRAP_ADMIN_ACCOUNT="${ADMIN_ACCOUNT}" \
  xboard-web -lc 'php /codex-scripts/bootstrap_xboard.php' </dev/null

if ! mysql_has_migrations_table; then
  echo "Failed to initialize MySQL schema." >&2
  exit 1
fi

compose run --rm --entrypoint sh \
  -e RESET_ADMIN_ACCOUNT="${ADMIN_ACCOUNT}" \
  -e RESET_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  xboard-web -lc 'php /codex-scripts/reset_xboard_admin_password.php' </dev/null

XBOARD_DB_CONNECTION="mysql" \
XBOARD_DB_HOST="mysql" \
XBOARD_DB_PORT="3306" \
XBOARD_DB_DATABASE="${MYSQL_DATABASE}" \
XBOARD_DB_USERNAME="${MYSQL_USER}" \
XBOARD_DB_PASSWORD="${MYSQL_PASSWORD}" \
XBOARD_CACHE_DRIVER="redis" \
XBOARD_QUEUE_CONNECTION="redis" \
XBOARD_ENABLE_SQLITE="false" \
XBOARD_ENABLE_REDIS="true" \
XBOARD_REDIS_HOST="/data/redis.sock" \
XBOARD_REDIS_PASSWORD="null" \
XBOARD_REDIS_PORT="0" \
XBOARD_SERVER_WS_URL="wss://${PANEL_DOMAIN}/ws" \
bash scripts/ensure_xboard_runtime_env.sh \
  "backend" \
  ".runtime/backend/xboard.env" \
  "deploy/backend-tunnel/xboard.env.template" \
  "https://${PANEL_DOMAIN}"

APP_URL_STATUS="$(compose run --rm --entrypoint sh \
  xboard-web -lc "php artisan tinker --execute='echo env(\"APP_URL\");'" \
  </dev/null \
  | tr -d '\r')"

if [[ "${APP_URL_STATUS}" != *"https://${PANEL_DOMAIN}"* ]]; then
  echo "Failed to persist APP_URL in backend xboard.env." >&2
  exit 1
fi

APP_KEY_STATUS="$(grep '^APP_KEY=' .runtime/backend/xboard.env | cut -d= -f2-)"

if [[ -z "${APP_KEY_STATUS}" ]]; then
  echo "Failed to persist APP_KEY in backend xboard.env." >&2
  exit 1
fi

SYNC_STATUS="$(compose run --rm --entrypoint sh \
  xboard-web -lc "php /codex-scripts/xboard_sync_settings.php >/dev/null && php artisan tinker --execute='echo ((admin_setting(\"app_url\") === env(\"APP_URL\")) && (admin_setting(\"email_host\") === env(\"MAIL_HOST\")) && (admin_setting(\"app_name\") === env(\"APP_NAME\")) && (admin_setting(\"server_ws_url\") === env(\"SERVER_WS_URL\"))) ? \"ok\" : \"fail\";'" \
  </dev/null \
  | tr -d '\r')"

if [[ "${SYNC_STATUS}" != *ok* ]]; then
  echo "Failed to persist Xboard app/mail/ws settings." >&2
  exit 1
fi

PASSWORD_STATUS="$(compose run --rm --entrypoint sh \
  -e CHECK_ADMIN_ACCOUNT="${ADMIN_ACCOUNT}" \
  -e CHECK_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  xboard-web -lc "php /codex-scripts/check_xboard_admin_password.php" \
  </dev/null \
  | tr -d '\r')"

if [[ "${PASSWORD_STATUS}" != *ok* ]]; then
  echo "Failed to reset admin password." >&2
  exit 1
fi

if ! grep -q '^INSTALLED=1$' .runtime/backend/xboard.env; then
  echo "Failed to persist INSTALLED=1 in backend xboard.env." >&2
  exit 1
fi

compose up -d --remove-orphans --force-recreate \
  mysql \
  redis \
  xboard-web \
  xboard-horizon \
  xboard-ws-server \
  app-api \
  cloudflared
EOF

echo "Backend deployment finished."
echo "API: https://${API_DOMAIN}/api/app/v1/public/config"
echo "Panel: https://${PANEL_DOMAIN}/"
echo "Admin account: ${ADMIN_ACCOUNT}"
echo "Backend DB secrets file: ${BACKEND_DB_SECRETS_FILE}"
if [[ "${PREPARE_WEB_BUILD}" == "1" ]]; then
  echo "Pages upload directory: ${ROOT_DIR}/build/web"
fi
