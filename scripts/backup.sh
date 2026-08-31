#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

if [ -f .env ]; then
  source .env
fi

SITE_NAME="${1:-${SITE_NAME:-mysite.localhost}}"

echo "========================================================="
echo "Backing up Site: ${SITE_NAME}"
echo "========================================================="

docker compose exec backend bench --site "${SITE_NAME}" backup --with-files

echo ""
echo "Backup completed. Backup files are stored in sites/${SITE_NAME}/private/backups inside the sites volume."
