#!/bin/bash
# =============================================================================
# Frappe Bench Entrypoint
# All services start from here. Handles:
#   - Bench directory structure validation
#   - common_site_config.json creation/update
#   - Static asset population (dereferenced, real files for Nginx)
#   - apps.txt sync from image into the persistent volume
# =============================================================================
set -eo pipefail

DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-3306}
REDIS_CACHE=${REDIS_CACHE:-redis-cache:6379}
REDIS_QUEUE=${REDIS_QUEUE:-redis-queue:6379}
SOCKETIO_PORT=${SOCKETIO_PORT:-9000}
SITE_NAME=${SITE_NAME:-}

BENCH_DIR="/home/frappe/frappe-bench"
SITES_DIR="${BENCH_DIR}/sites"

# ---------------------------------------------------------------------------
# 1. Ensure the bench directory structure is always present.
#    bench's is_bench_directory() checks for apps, sites, config, logs, config/pids.
# ---------------------------------------------------------------------------
mkdir -p \
    "${BENCH_DIR}/apps" \
    "${BENCH_DIR}/sites" \
    "${BENCH_DIR}/config" \
    "${BENCH_DIR}/config/pids" \
    "${BENCH_DIR}/logs"

cd "${BENCH_DIR}"

# ---------------------------------------------------------------------------
# 2. Sync apps.txt from image into the shared volume.
# ---------------------------------------------------------------------------
if [ -f "${BENCH_DIR}/apps_txt_dist" ]; then
    echo "[entrypoint] Syncing apps.txt into sites volume..."
    cp "${BENCH_DIR}/apps_txt_dist" "${SITES_DIR}/apps.txt"
fi

# ---------------------------------------------------------------------------
# 3. Create or update common_site_config.json with correct service addresses.
#    This makes the containers relocatable — just change env vars.
# ---------------------------------------------------------------------------
python3 - <<PYEOF
import json, os

config_file = "${SITES_DIR}/common_site_config.json"
try:
    with open(config_file) as f:
        data = json.load(f)
except Exception:
    data = {}

data.update({
    "db_host": "${DB_HOST}",
    "db_port": int("${DB_PORT}"),
    "redis_cache": "redis://${REDIS_CACHE}",
    "redis_queue": "redis://${REDIS_QUEUE}",
    "redis_socketio": "redis://${REDIS_QUEUE}",
    "socketio_port": int("${SOCKETIO_PORT}"),
    "webserver_port": 8000,
    "developer_mode": 0,
})

os.makedirs(os.path.dirname(config_file), exist_ok=True)
with open(config_file, "w") as f:
    json.dump(data, f, indent=2)

print("[entrypoint] common_site_config.json written.")
PYEOF

# ---------------------------------------------------------------------------
# 4. Wait for MariaDB to be accepting connections.
#    On PC reboot Docker starts all containers in parallel so the backend
#    can start before MariaDB is ready — causing 500 errors.
# ---------------------------------------------------------------------------
echo "[entrypoint] Waiting for database at ${DB_HOST}:${DB_PORT}..."
for i in $(seq 1 60); do
    if mariadb-admin ping -h "${DB_HOST}" -P "${DB_PORT}" --silent 2>/dev/null || \
       python3 -c "
import socket, sys
try:
    s = socket.create_connection(('${DB_HOST}', int('${DB_PORT}')), timeout=2)
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "[entrypoint] Database is ready."
        break
    fi
    echo "[entrypoint] DB not ready (attempt ${i}/60), retrying in 2s..."
    sleep 2
done

# ---------------------------------------------------------------------------
# 5. Populate the shared volume with REAL (dereferenced) static asset files.
#    assets_dist is baked into the image with cp -r -L so no symlinks exist.
#    We only copy if the assets directory is missing or empty.
# ---------------------------------------------------------------------------
if [ -d "${BENCH_DIR}/assets_dist" ]; then
    if [ ! -f "${SITES_DIR}/assets/assets.json" ]; then
        echo "[entrypoint] Copying compiled assets into sites volume..."
        mkdir -p "${SITES_DIR}/assets"
        cp -r "${BENCH_DIR}/assets_dist/." "${SITES_DIR}/assets/"
        echo "[entrypoint] Assets copied."
    fi
fi

# ---------------------------------------------------------------------------
# 6. If SITE_NAME is set and a currentsite.txt is missing, create it so
#    Frappe knows which site is the default without needing a Host: header match.
# ---------------------------------------------------------------------------
if [ -n "${SITE_NAME}" ] && [ ! -f "${SITES_DIR}/currentsite.txt" ]; then
    echo "${SITE_NAME}" > "${SITES_DIR}/currentsite.txt"
fi

# ---------------------------------------------------------------------------
# 6. Dispatch to the requested service mode.
# ---------------------------------------------------------------------------
case "$1" in
    backend)
        echo "[entrypoint] Starting Gunicorn on port 8000 (workers=${GUNICORN_WORKERS:-4})..."
        cd "${SITES_DIR}"
        exec gunicorn \
            --bind 0.0.0.0:8000 \
            --workers "${GUNICORN_WORKERS:-4}" \
            --threads "${GUNICORN_THREADS:-2}" \
            --timeout "${GUNICORN_TIMEOUT:-120}" \
            --keep-alive 5 \
            frappe.app:application
        ;;

    websocket)
        echo "[entrypoint] Starting Socket.IO on port ${SOCKETIO_PORT}..."
        cd "${SITES_DIR}"
        exec node "${BENCH_DIR}/apps/frappe/socketio.js"
        ;;

    worker)
        QUEUE="${2:-default}"
        echo "[entrypoint] Starting background worker for queue: ${QUEUE}..."
        exec bench worker --queue "${QUEUE}"
        ;;

    scheduler)
        echo "[entrypoint] Starting scheduler..."
        exec bench schedule
        ;;

    *)
        # Pass through — allows: docker compose exec backend bench new-site ...
        exec "$@"
        ;;
esac
