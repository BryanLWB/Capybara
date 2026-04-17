#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBOARD_DIR="${ROOT_DIR}/upstreams/xboard"

if [[ ! -d "${XBOARD_DIR}" ]]; then
  echo "Skipping upstream update check: missing ${XBOARD_DIR}" >&2
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Skipping upstream update check: git is not installed" >&2
  exit 0
fi

CURRENT_COMMIT="$(git -C "${XBOARD_DIR}" rev-parse HEAD)"

if ! git -C "${XBOARD_DIR}" fetch origin --prune >/dev/null 2>&1; then
  echo "Warning: unable to check whether Xboard upstream has new commits. Continuing with local startup." >&2
  exit 0
fi

TARGET_COMMIT="$(git -C "${XBOARD_DIR}" rev-parse origin/master)"

if [[ "${CURRENT_COMMIT}" == "${TARGET_COMMIT}" ]]; then
  echo "Xboard upstream check: local mirror is up to date at ${CURRENT_COMMIT}."
  exit 0
fi

BEHIND_COUNT="$(git -C "${XBOARD_DIR}" rev-list --count "${CURRENT_COMMIT}..${TARGET_COMMIT}")"

cat <<EOF
Xboard upstream check: update available.
- local:  ${CURRENT_COMMIT}
- remote: ${TARGET_COMMIT}
- behind: ${BEHIND_COUNT} commit(s)

If you want to update safely without losing local data, run:
  bash scripts/update_local_xboard_upstream.sh
EOF
