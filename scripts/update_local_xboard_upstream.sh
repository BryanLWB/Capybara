#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBOARD_DIR="${ROOT_DIR}/upstreams/xboard"
COMPOSE_FILE="${ROOT_DIR}/docker/xboard-local.compose.yaml"
BACKUP_ROOT="${ROOT_DIR}/.local/xboard-backups"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
APPLY_MIGRATIONS=false

if [[ "${1:-}" == "--apply-migrations" ]]; then
  APPLY_MIGRATIONS=true
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command git
require_command docker
require_command tar

if [[ ! -d "${XBOARD_DIR}" ]]; then
  echo "Missing upstream checkout: ${XBOARD_DIR}" >&2
  exit 1
fi

if [[ -n "$(git -C "${XBOARD_DIR}" status --short)" ]]; then
  echo "Refusing to update because ${XBOARD_DIR} has tracked changes." >&2
  echo "Please commit, stash, or discard those changes first." >&2
  exit 1
fi

CURRENT_COMMIT="$(git -C "${XBOARD_DIR}" rev-parse HEAD)"
git -C "${XBOARD_DIR}" fetch origin --prune
TARGET_COMMIT="$(git -C "${XBOARD_DIR}" rev-parse origin/master)"

if [[ "${CURRENT_COMMIT}" == "${TARGET_COMMIT}" ]]; then
  echo "Xboard is already up to date at ${CURRENT_COMMIT}."
  exit 0
fi

mkdir -p "${BACKUP_DIR}"

echo "Creating local backup in ${BACKUP_DIR} ..."

if [[ -f "${XBOARD_DIR}/.env" ]]; then
  cp -a "${XBOARD_DIR}/.env" "${BACKUP_DIR}/xboard.env"
fi

if [[ -d "${XBOARD_DIR}/.docker/.data" ]]; then
  mkdir -p "${BACKUP_DIR}/docker-data"
  cp -a "${XBOARD_DIR}/.docker/.data/." "${BACKUP_DIR}/docker-data/"
fi

if [[ -d "${XBOARD_DIR}/storage/app" ]]; then
  mkdir -p "${BACKUP_DIR}/storage-app"
  cp -a "${XBOARD_DIR}/storage/app/." "${BACKUP_DIR}/storage-app/"
fi

REDIS_VOLUME_NAME="$(docker volume ls --format '{{.Name}}' | awk '/(^|_)xboard-redis-data$/ {print; exit}')"
if [[ -n "${REDIS_VOLUME_NAME}" ]]; then
  docker run --rm \
    -v "${REDIS_VOLUME_NAME}:/from" \
    -v "${BACKUP_DIR}:/to" \
    alpine:3.21 \
    sh -lc 'cd /from && tar -czf /to/redis-volume.tar.gz .'
fi

cat > "${BACKUP_DIR}/backup-meta.txt" <<EOF
created_at=${TIMESTAMP}
previous_commit=${CURRENT_COMMIT}
target_commit=${TARGET_COMMIT}
redis_volume=${REDIS_VOLUME_NAME}
EOF

echo "Stopping local Xboard services ..."
docker compose -f "${COMPOSE_FILE}" stop web horizon ws-server redis >/dev/null

echo "Updating upstreams/xboard from ${CURRENT_COMMIT} to ${TARGET_COMMIT} ..."
git -C "${XBOARD_DIR}" checkout master >/dev/null 2>&1 || true
git -C "${XBOARD_DIR}" merge --ff-only origin/master
git -C "${XBOARD_DIR}" submodule update --init --recursive --checkout

echo "Refreshing local Xboard prerequisites ..."
bash "${ROOT_DIR}/scripts/prepare_local_xboard.sh"

echo "Starting local Xboard stack ..."
docker compose -f "${COMPOSE_FILE}" up -d

if [[ "${APPLY_MIGRATIONS}" == "true" ]]; then
  echo "Applying Xboard migrations ..."
  docker compose -f "${COMPOSE_FILE}" exec -T web php artisan migrate --force
else
  echo "Reviewing pending migrations (no schema changes applied) ..."
  bash "${ROOT_DIR}/scripts/review_xboard_pending_migrations.sh" || true
fi

cat <<EOF

Local Xboard update complete.

Previous commit: ${CURRENT_COMMIT}
Current commit:  ${TARGET_COMMIT}
Backup:          ${BACKUP_DIR}

Rollback outline:
1. docker compose -f docker/xboard-local.compose.yaml stop web horizon ws-server redis
2. git -C upstreams/xboard checkout ${CURRENT_COMMIT}
3. restore ${BACKUP_DIR}/xboard.env to upstreams/xboard/.env
4. restore ${BACKUP_DIR}/docker-data to upstreams/xboard/.docker/.data
5. restore ${BACKUP_DIR}/storage-app to upstreams/xboard/storage/app
6. if needed, restore ${BACKUP_DIR}/redis-volume.tar.gz back into ${REDIS_VOLUME_NAME}
7. bash scripts/prepare_local_xboard.sh
8. docker compose -f docker/xboard-local.compose.yaml up -d
EOF
