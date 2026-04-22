#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBOARD_IMAGE="${XBOARD_IMAGE:-ghcr.io/cedar2025/xboard:new}"
TARGET_DIR="${ROOT_DIR}/.local/xboard-admin-assets"

rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"

container_id="$(docker create "${XBOARD_IMAGE}")"
cleanup() {
  docker rm -f "${container_id}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker cp "${container_id}:/www/public/assets/admin/." "${TARGET_DIR}/"

echo "Synced Xboard admin assets into ${TARGET_DIR}"
