#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBOARD_DIR="${ROOT_DIR}/upstreams/xboard"
COMPOSE_FILE="${ROOT_DIR}/docker/xboard-local.compose.yaml"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command docker
require_command python3

STATUS_OUTPUT="$(docker compose -f "${COMPOSE_FILE}" exec -T web php artisan migrate:status)"
printf '%s\n' "${STATUS_OUTPUT}"

PENDING_MIGRATIONS=()
while IFS= read -r migration; do
  [[ -n "${migration}" ]] || continue
  PENDING_MIGRATIONS+=("${migration}")
done < <(printf '%s\n' "${STATUS_OUTPUT}" | sed -n "s/^  \\([0-9_][^ ]*\\).*Pending[[:space:]]*$/\\1/p")

if [[ "${#PENDING_MIGRATIONS[@]}" -eq 0 ]]; then
  echo
  echo "No pending migrations."
  exit 0
fi

echo
echo "Pending migration review:"

for migration in "${PENDING_MIGRATIONS[@]}"; do
  migration_file="${XBOARD_DIR}/database/migrations/${migration}.php"
  if [[ ! -f "${migration_file}" ]]; then
    echo
    echo "- ${migration}"
    echo "  file: missing (${migration_file})"
    continue
  fi

  echo
  echo "- ${migration}"
  echo "  file: ${migration_file}"

  python3 - "${migration_file}" "${XBOARD_DIR}" <<'PY'
import os
import re
import sqlite3
import sys

file_path = sys.argv[1]
xboard_dir = sys.argv[2]
text = open(file_path, "r", encoding="utf-8").read()

creates = re.findall(r"Schema::create\('([^']+)'", text)
alters = re.findall(r"Schema::table\('([^']+)'", text)
down_drops = re.findall(r"Schema::dropIfExists\('([^']+)'", text)

def parse_env(path):
    data = {}
    if not os.path.exists(path):
        return data
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            data[key] = value
    return data

env = parse_env(os.path.join(xboard_dir, ".env"))
db_connection = env.get("DB_CONNECTION", "")
db_database = env.get("DB_DATABASE", "")
db_path = os.path.join(xboard_dir, db_database) if db_connection == "sqlite" and db_database else None

print("  summary:")
if creates:
    print(f"    creates tables: {', '.join(creates)}")
if alters:
    print(f"    alters tables: {', '.join(sorted(set(alters)))}")
if down_drops:
    print(f"    down() drops: {', '.join(down_drops)}")
if not any([creates, alters, down_drops]):
    print("    unable to infer table operations from source")

if db_connection != "sqlite" or not db_path or not os.path.exists(db_path):
    print(f"  pre-check: database inspection skipped (DB_CONNECTION={db_connection or 'unknown'})")
    sys.exit(0)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

def table_exists(name):
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,))
    return cur.fetchone() is not None

def row_count(name):
    cur.execute(f'SELECT COUNT(*) FROM "{name}"')
    return cur.fetchone()[0]

def columns(name):
    cur.execute(f'PRAGMA table_info("{name}")')
    return [row[1] for row in cur.fetchall()]

print("  pre-check:")
for table in creates:
    if table_exists(table):
      print(f"    {table}: already exists with {row_count(table)} rows")
    else:
      print(f"    {table}: does not exist yet")

for table in sorted(set(alters)):
    if table_exists(table):
      cols = columns(table)
      preview = ", ".join(cols[:12])
      suffix = " ..." if len(cols) > 12 else ""
      print(f"    {table}: exists with {row_count(table)} rows; columns: {preview}{suffix}")
    else:
      print(f"    {table}: missing")
PY

  echo "  pretend SQL:"
  docker compose -f "${COMPOSE_FILE}" exec -T web \
    php artisan migrate --pretend --force --path="database/migrations/${migration}.php" \
    | sed 's/^/    /'
done
