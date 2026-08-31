#!/bin/bash
set -e

# Default environment configurations
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-3306}
REDIS_CACHE=${REDIS_CACHE:-redis-cache:6379}
REDIS_QUEUE=${REDIS_QUEUE:-redis-queue:6379}
SOCKETIO_PORT=${SOCKETIO_PORT:-9000}

BENCH_DIR="/home/frappe/frappe-bench"
SITES_DIR="${BENCH_DIR}/sites"

cd "${BENCH_DIR}"

# Ensure sites/apps.txt exists in mounted volume
if [ ! -f "${SITES_DIR}/apps.txt" ] && [ -f "${BENCH_DIR}/apps_txt_dist" ]; then
    echo "Creating sites/apps.txt..."
    cp "${BENCH_DIR}/apps_txt_dist" "${SITES_DIR}/apps.txt"
fi

# Ensure sites/common_site_config.json exists and has correct service endpoints
if [ ! -f "${SITES_DIR}/common_site_config.json" ]; then
    echo "Creating initial common_site_config.json..."
    cat <<EOF > "${SITES_DIR}/common_site_config.json"
{
  "db_host": "${DB_HOST}",
  "db_port": ${DB_PORT},
  "redis_cache": "redis://${REDIS_CACHE}",
  "redis_queue": "redis://${REDIS_QUEUE}",
  "redis_socketio": "redis://${REDIS_QUEUE}",
  "socketio_port": ${SOCKETIO_PORT},
  "webserver_port": 8000,
  "developer_mode": 0
}
EOF
else
    # Update host endpoints in existing common_site_config.json if provided
    python3 -c "
import json
config_file = '${SITES_DIR}/common_site_config.json'
try:
    with open(config_file, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}

data['db_host'] = '${DB_HOST}'
data['db_port'] = int('${DB_PORT}')
data['redis_cache'] = 'redis://${REDIS_CACHE}'
data['redis_queue'] = 'redis://${REDIS_QUEUE}'
data['redis_socketio'] = 'redis://${REDIS_QUEUE}'
data['socketio_port'] = int('${SOCKETIO_PORT}')

with open(config_file, 'w') as f:
    json.dump(data, f, indent=2)
"
fi

# Ensure sites/assets directory is populated with compiled assets
if [ -d "${BENCH_DIR}/assets_dist" ]; then
    mkdir -p "${SITES_DIR}/assets"
    cp -ru "${BENCH_DIR}/assets_dist/"* "${SITES_DIR}/assets/" 2>/dev/null || cp -r "${BENCH_DIR}/assets_dist/"* "${SITES_DIR}/assets/"
fi

# Handle execution modes
case "$1" in
    backend)
        echo "Starting Gunicorn Web Server on port 8000..."
        cd "${SITES_DIR}"
        exec gunicorn \
            --bind 0.0.0.0:8000 \
            --workers ${GUNICORN_WORKERS:-4} \
            --threads ${GUNICORN_THREADS:-2} \
            --timeout ${GUNICORN_TIMEOUT:-120} \
            --keep-alive 5 \
            frappe.app:application
        ;;

    websocket)
        echo "Starting Socket.IO Node Server on port ${SOCKETIO_PORT}..."
        cd "${SITES_DIR}"
        exec node "${BENCH_DIR}/apps/frappe/socketio.js"
        ;;

    worker)
        QUEUE=${2:-default}
        echo "Starting Frappe Worker for queue: ${QUEUE}..."
        cd "${SITES_DIR}"
        exec bench worker --queue "${QUEUE}"
        ;;

    scheduler)
        echo "Starting Frappe Schedule daemon..."
        cd "${SITES_DIR}"
        exec bench schedule
        ;;

    *)
        # If user passed custom command (like bench new-site, bench migrate, bash, etc.)
        cd "${SITES_DIR}"
        exec "$@"
        ;;
esac
