#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBOARD_DIR="${ROOT_DIR}/upstreams/xboard"
ADMIN_SUBMODULE_DIR="${XBOARD_DIR}/public/assets/admin"
LOCAL_RUNTIME_DIR="${ROOT_DIR}/.runtime/local-xboard"
LOCAL_RUNTIME_ENV="${LOCAL_RUNTIME_DIR}/xboard.env"
LOCAL_RUNTIME_DATA="${LOCAL_RUNTIME_DIR}/xboard-data"

repair_admin_submodule() {
  if [[ -d "${ADMIN_SUBMODULE_DIR}" ]] && \
    git -C "${ADMIN_SUBMODULE_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    return 0
  fi

  echo "Repairing Xboard admin submodule..."
  rm -rf "${ADMIN_SUBMODULE_DIR}"
  git -C "${XBOARD_DIR}" submodule update --init --force --checkout public/assets/admin
}

repair_admin_submodule

bash "${ROOT_DIR}/scripts/ensure_xboard_runtime_env.sh" \
  "local-xboard" \
  "${LOCAL_RUNTIME_ENV}" \
  "${ROOT_DIR}/deploy/local-xboard/xboard.env.template" \
  "http://127.0.0.1:7001"

mkdir -p "${LOCAL_RUNTIME_DATA}"
if [[ ! -e "${LOCAL_RUNTIME_DATA}/database.sqlite" && -d "${XBOARD_DIR}/.docker/.data" ]]; then
  cp -a "${XBOARD_DIR}/.docker/.data/." "${LOCAL_RUNTIME_DATA}/"
fi

bash "${ROOT_DIR}/scripts/check_xboard_upstream_update.sh"

docker compose -f "${ROOT_DIR}/docker/xboard-local.compose.yaml" run --rm web \
  composer install --no-dev

bash "${ROOT_DIR}/scripts/sync_xboard_admin_assets.sh"

echo "Local Xboard prerequisites are ready."
