#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBOARD_DIR="${ROOT_DIR}/upstreams/xboard"
ADMIN_SUBMODULE_DIR="${XBOARD_DIR}/public/assets/admin"

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

bash "${ROOT_DIR}/scripts/check_xboard_upstream_update.sh"

docker compose -f "${ROOT_DIR}/docker/xboard-local.compose.yaml" run --rm web \
  composer install --no-dev

bash "${ROOT_DIR}/scripts/sync_xboard_admin_assets.sh"

echo "Local Xboard prerequisites are ready."
