#!/usr/bin/env bash
# =============================================================================
# setup-site.sh — One-shot site initializer.
# Run this ONCE on a fresh installation (new machine, empty volume).
# Usage: ./scripts/setup-site.sh [site-name] [admin-password] [db-root-password]
# =============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

# Load .env
if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
fi

SITE_NAME="${1:-${SITE_NAME:-radolfa.localhost}}"
ADMIN_PASS="${2:-${ADMIN_PASSWORD:-admin_password}}"
DB_ROOT_PASS="${3:-${DB_ROOT_PASSWORD:-mariadb_root_password}}"
HTTP_PORT="${HTTP_PORT:-8088}"

echo "========================================================="
echo "  Frappe Site Initializer"
echo "  Site Name  : ${SITE_NAME}"
echo "  HTTP Port  : ${HTTP_PORT}"
echo "========================================================="

# ---- 1. Bring up the stack if it is not already running ------------------
if ! docker compose ps --status running | grep -q "backend"; then
    echo "[setup] Starting services..."
    docker compose up -d
fi

# ---- 2. Wait for MariaDB to be genuinely ready ---------------------------
echo "[setup] Waiting for database to be ready..."
for i in $(seq 1 30); do
    if docker compose exec db mysqladmin ping -h localhost -u root -p"${DB_ROOT_PASS}" --silent 2>/dev/null; then
        echo "[setup] Database is ready."
        break
    fi
    echo "[setup] ... attempt ${i}/30, retrying in 3s"
    sleep 3
done

# ---- 3. Ensure bench directory structure is present ----------------------
docker compose exec -w /home/frappe/frappe-bench backend \
    mkdir -p config/pids logs sites apps

# ---- 4. Create the Frappe site and install apps --------------------------
echo "[setup] Creating site '${SITE_NAME}' and installing apps..."
echo "[setup] (This takes 2–5 minutes on first run)"
docker compose exec -w /home/frappe/frappe-bench backend \
    bench new-site "${SITE_NAME}" \
        --admin-password "${ADMIN_PASS}" \
        --db-root-password "${DB_ROOT_PASS}" \
        --mariadb-user-host-login-scope "%" \
        --install-app erpnext \
        --install-app hrms \
        --install-app posawesome \
        --set-default

# Install web_sync if available in apps
docker compose exec -w /home/frappe/frappe-bench backend \
    bash -c "if [ -d 'apps/web_sync' ]; then echo '[setup] Installing web_sync...' && bench --site '${SITE_NAME}' install-app web_sync || true; fi"

# ---- 4b. Ensure default customer 'Гость' exists ---------------------------
echo "[setup] Ensuring default customer 'Гость' exists..."
docker compose exec -w /home/frappe/frappe-bench/sites backend \
    python -c "
import frappe
frappe.init('${SITE_NAME}')
frappe.connect()
if not frappe.db.exists('Customer', 'Гость'):
    cg = frappe.db.get_value('Customer Group', {'is_group': 0}, 'name') or 'Individual'
    ter = frappe.db.get_value('Territory', {'is_group': 0}, 'name') or 'All Territories'
    doc = frappe.get_doc({'doctype': 'Customer', 'customer_name': 'Гость', 'customer_type': 'Individual', 'customer_group': cg, 'territory': ter})
    doc.insert(ignore_permissions=True)
    frappe.db.commit()
for profile in frappe.get_all('POS Profile', fields=['name', 'customer']):
    if not profile.customer or profile.customer in ('WalkIn Customer', 'Walk-in Customer'):
        frappe.db.set_value('POS Profile', profile.name, 'customer', 'Гость')
frappe.db.commit()
" || true

# ---- 5. Write the site name into currentsite.txt so Frappe always knows --
#         which site to serve even when the Host header is just "localhost"
docker compose exec -w /home/frappe/frappe-bench backend \
    bash -c "echo '${SITE_NAME}' > sites/currentsite.txt"

# ---- 6. Set default_site in common_site_config.json ----------------------
docker compose exec -w /home/frappe/frappe-bench backend \
    bench set-config -g default_site "${SITE_NAME}"

# ---- 7. Copy dereferenced assets into the volume (so Nginx can serve them)
echo "[setup] Copying static assets..."
docker compose exec -w /home/frappe/frappe-bench backend \
    bash -c "rm -rf sites/assets && cp -r assets_dist sites/assets"

# ---- 8. Enable the background scheduler ---------------------------------
docker compose exec -w /home/frappe/frappe-bench backend \
    bench --site "${SITE_NAME}" enable-scheduler

echo ""
echo "========================================================="
echo "  Site ready!"
echo "  URL      : http://localhost:${HTTP_PORT}"
echo "  Username : Administrator"
echo "  Password : ${ADMIN_PASS}"
echo "========================================================="
