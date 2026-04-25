#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DB_SECRETS_FILE="${BACKEND_DB_SECRETS_FILE:-${ROOT_DIR}/.runtime/production/backend-db.env}"
BACKEND_HOST="${BACKEND_HOST:?Set BACKEND_HOST, for example root@178.104.115.63}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/capybara-backend}"
LOCAL_BACKUP_ROOT="${LOCAL_BACKUP_ROOT:-${ROOT_DIR}/.local/backend-mysql-backups}"
LOCAL_BACKUP_KEEP="${LOCAL_BACKUP_KEEP:-3}"
TIMESTAMP="${TIMESTAMP:-$(date +"%Y%m%d-%H%M%S")}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

prune_local_backups() {
  local backup_root="$1"
  local keep_count="$2"
  local backup_dirs=()
  local backup_dir

  while IFS= read -r backup_dir; do
    backup_dirs+=("${backup_dir}")
  done < <(find "${backup_root}" -mindepth 1 -maxdepth 1 -type d -print | sort)

  if (( ${#backup_dirs[@]} <= keep_count )); then
    return
  fi

  while (( ${#backup_dirs[@]} > keep_count )); do
    rm -rf "${backup_dirs[0]}"
    backup_dirs=("${backup_dirs[@]:1}")
  done
}

require_cmd rsync
require_cmd ssh

if [[ -f "${BACKEND_DB_SECRETS_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${BACKEND_DB_SECRETS_FILE}"
  set +a
fi

mkdir -p "${LOCAL_BACKUP_ROOT}"

LOCAL_BACKUP_DIR="${LOCAL_BACKUP_ROOT}/${TIMESTAMP}"
REMOTE_BACKUP_RELATIVE_DIR=".backups/mysql"
REMOTE_BACKUP_FILENAME="xboard-mysql-${TIMESTAMP}.sql.gz"
REMOTE_METADATA_FILENAME="xboard-mysql-${TIMESTAMP}.meta"
REMOTE_BACKUP_PATH="${DEPLOY_PATH}/${REMOTE_BACKUP_RELATIVE_DIR}/${REMOTE_BACKUP_FILENAME}"
REMOTE_METADATA_PATH="${DEPLOY_PATH}/${REMOTE_BACKUP_RELATIVE_DIR}/${REMOTE_METADATA_FILENAME}"

mkdir -p "${LOCAL_BACKUP_DIR}"

cleanup_incomplete_backup() {
  if [[ ! -f "${LOCAL_BACKUP_DIR}/${REMOTE_BACKUP_FILENAME}" ]]; then
    rm -rf "${LOCAL_BACKUP_DIR}"
  fi
}

trap cleanup_incomplete_backup EXIT

REMOTE_BACKUP_RESULT="$(
ssh "${BACKEND_HOST}" \
  "DEPLOY_PATH='${DEPLOY_PATH}' TIMESTAMP='${TIMESTAMP}' REMOTE_BACKUP_RELATIVE_DIR='${REMOTE_BACKUP_RELATIVE_DIR}' REMOTE_BACKUP_FILENAME='${REMOTE_BACKUP_FILENAME}' REMOTE_METADATA_FILENAME='${REMOTE_METADATA_FILENAME}' bash -s" <<'EOF'
set -euo pipefail

compose() {
  docker compose --env-file .runtime/backend/compose.env -f docker/backend-tunnel.compose.yaml "$@"
}

cd "${DEPLOY_PATH}"

if [[ ! -f ".runtime/backend/compose.env" ]]; then
  echo "Missing remote compose env at ${DEPLOY_PATH}/.runtime/backend/compose.env" >&2
  exit 1
fi

mkdir -p "${REMOTE_BACKUP_RELATIVE_DIR}"

if ! compose ps --status running mysql >/dev/null 2>&1; then
  echo "MySQL service is not running; cannot create backup." >&2
  exit 1
fi

compose exec -T mysql sh -lc 'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction --quick --routines --triggers --events --no-tablespaces "$MYSQL_DATABASE"' </dev/null \
  | gzip -1 > "${REMOTE_BACKUP_RELATIVE_DIR}/${REMOTE_BACKUP_FILENAME}"

DB_NAME="$(compose exec -T mysql sh -lc 'printf "%s" "$MYSQL_DATABASE"' </dev/null)"
TABLE_COUNT="$(compose exec -T mysql sh -lc 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '\''$MYSQL_DATABASE'\'';" "$MYSQL_DATABASE"' </dev/null | tr -d '\r')"

cat > "${REMOTE_BACKUP_RELATIVE_DIR}/${REMOTE_METADATA_FILENAME}" <<META
created_at=${TIMESTAMP}
deploy_path=${DEPLOY_PATH}
db_name=${DB_NAME}
table_count=${TABLE_COUNT}
backup_file=${REMOTE_BACKUP_FILENAME}
META

printf '%s\n%s\n' \
  "${DEPLOY_PATH}/${REMOTE_BACKUP_RELATIVE_DIR}/${REMOTE_BACKUP_FILENAME}" \
  "${DEPLOY_PATH}/${REMOTE_BACKUP_RELATIVE_DIR}/${REMOTE_METADATA_FILENAME}"
EOF
)"

REMOTE_ARTIFACTS=()
while IFS= read -r remote_artifact; do
  REMOTE_ARTIFACTS+=("${remote_artifact}")
done <<<"${REMOTE_BACKUP_RESULT}"

if (( ${#REMOTE_ARTIFACTS[@]} != 2 )); then
  echo "Unexpected remote backup output:" >&2
  echo "${REMOTE_BACKUP_RESULT}" >&2
  exit 1
fi

rsync -az \
  "${BACKEND_HOST}:${REMOTE_ARTIFACTS[0]}" \
  "${BACKEND_HOST}:${REMOTE_ARTIFACTS[1]}" \
  "${LOCAL_BACKUP_DIR}/"

LOCAL_BACKUP_FILE="${LOCAL_BACKUP_DIR}/${REMOTE_BACKUP_FILENAME}"
LOCAL_METADATA_FILE="${LOCAL_BACKUP_DIR}/${REMOTE_METADATA_FILENAME}"

if [[ ! -s "${LOCAL_BACKUP_FILE}" ]]; then
  echo "Backup file was downloaded but is empty: ${LOCAL_BACKUP_FILE}" >&2
  exit 1
fi

cat > "${LOCAL_BACKUP_DIR}/backup-meta.txt" <<EOF
created_at=${TIMESTAMP}
backend_host=${BACKEND_HOST}
deploy_path=${DEPLOY_PATH}
remote_backup_path=${REMOTE_ARTIFACTS[0]}
remote_metadata_path=${REMOTE_ARTIFACTS[1]}
local_backup_file=${LOCAL_BACKUP_FILE}
local_metadata_file=${LOCAL_METADATA_FILE}
EOF

prune_local_backups "${LOCAL_BACKUP_ROOT}" "${LOCAL_BACKUP_KEEP}"

echo "MySQL backup complete."
echo "Local backup dir: ${LOCAL_BACKUP_DIR}"
echo "Backup file: ${LOCAL_BACKUP_FILE}"
echo "Metadata file: ${LOCAL_METADATA_FILE}"

trap - EXIT
