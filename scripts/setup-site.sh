#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

if [ -f .env ]; then
  source .env
fi

SITE_NAME="${1:-${SITE_NAME:-mysite.localhost}}"
ADMIN_PASS="${2:-${ADMIN_PASSWORD:-admin_password}}"
DB_ROOT_PASS="${3:-${DB_ROOT_PASSWORD:-mariadb_root_password}}"

echo "========================================================="
echo "Initializing New Site: ${SITE_NAME}"
echo "Apps to Install: ERPNext, POS Awesome"
echo "========================================================="

# Ensure backend container is running
if ! docker compose ps | grep -q "backend"; then
    echo "Starting Docker Compose services..."
    docker compose up -d
    echo "Waiting for Database to become ready..."
    sleep 10
fi

echo "Creating site and installing apps (this may take 2-3 minutes)..."
docker compose exec backend bench new-site "${SITE_NAME}" \
  --admin-password "${ADMIN_PASS}" \
  --db-root-password "${DB_ROOT_PASS}" \
  --install-app erpnext \
  --install-app posawesome \
  --set-default

echo "Enabling scheduler for site..."
docker compose exec backend bench --site "${SITE_NAME}" enable-scheduler

echo ""
echo "========================================================="
echo "Site created successfully!"
echo "Site URL: http://localhost:${HTTP_PORT:-80} (or http://${SITE_NAME}:${HTTP_PORT:-80})"
echo "Username: Administrator"
echo "Password: ${ADMIN_PASS}"
echo "========================================================="
