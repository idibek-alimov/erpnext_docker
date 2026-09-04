# syntax=docker/dockerfile:1.4
ARG PYTHON_VERSION=3.11
ARG DEBIAN_BASE=bookworm

# ==============================================================================
# STAGE 1 — BUILDER
# Clones your custom GitHub repos, installs all dependencies,
# compiles JS/CSS assets. The result is a clean bench directory.
# ==============================================================================
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS builder

ARG FRAPPE_REPO=https://github.com/idibek-alimov/frappe.git
ARG FRAPPE_BRANCH=version-15
ARG NODE_VERSION=20

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/home/frappe/frappe-bench/env/bin:$PATH"

# ---- System packages and Node.js -----------------------------------------
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential curl git \
        libffi-dev libssl-dev \
        libmariadb-dev libmariadb-dev-compat \
        pkg-config python3-dev python3-venv \
        ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g yarn \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Create unprivileged frappe user & bench directory -------------------
RUN useradd -ms /bin/bash -u 1000 frappe \
    && mkdir -p /home/frappe/frappe-bench \
    && chown -R frappe:frappe /home/frappe
USER frappe
WORKDIR /home/frappe/frappe-bench

# ---- Bench skeleton directories ------------------------------------------
RUN mkdir -p apps sites config config/pids logs

# ---- Configure GitHub Token if provided (for private repositories) -------
ARG GITHUB_TOKEN=""
RUN if [ -n "${GITHUB_TOKEN}" ]; then \
        git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"; \
    fi

# ---- Python virtualenv + frappe-bench CLI --------------------------------
RUN python3 -m venv env \
    && ./env/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && ./env/bin/pip install --no-cache-dir frappe-bench

# ---- Clone & install your custom Frappe ----------------------------------
# (CACHEBUST above this line busts Docker cache so fresh code is always pulled)
ARG CACHEBUST=1
RUN echo "Cache bust: ${CACHEBUST}" \
    && git clone --depth 1 -b ${FRAPPE_BRANCH} ${FRAPPE_REPO} apps/frappe \
    && ./env/bin/pip install --no-cache-dir -e apps/frappe

# ---- Clone & install ERPNext, HRMS, and POS Awesome via apps.json --------
COPY --chown=frappe:frappe apps.json apps.json
COPY --chown=frappe:frappe install_apps.py install_apps.py
RUN python3 install_apps.py \
    && git config --global --unset-all url."https://${GITHUB_TOKEN}@github.com/".insteadOf 2>/dev/null || true

# ---- Node dependencies for all apps with package.json --------------------
RUN for d in apps/frappe apps/erpnext apps/hrms apps/posawesome; do \
        if [ -f "$d/package.json" ]; then \
            echo "yarn: installing $d..." && \
            (cd "$d" && yarn install --ignore-engines 2>&1); \
        fi \
    done

# ---- Build SPA/frontend apps (e.g. HRMS, POS Awesome) if build script exists ---
RUN for d in apps/hrms apps/posawesome; do \
        if [ -f "$d/package.json" ]; then \
            echo "yarn build: $d..." && \
            (cd "$d" && yarn build 2>&1 || true); \
        fi \
    done

# ---- Build all JS/CSS assets (must run from sites/ — bench_helper reads ./apps.txt)
RUN cd sites && python3 -m frappe.utils.bench_helper frappe build

# ---- Dereference all symlinks in assets so Nginx can serve real files ----
#      (-L = follow symlinks, result has no symlink entries)
RUN cp -r -L sites/assets assets_dist

# ---- Strip dev caches to reduce image size --------------------------------
RUN find env/ -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
RUN rm -rf /home/frappe/.cache /home/frappe/.npm /home/frappe/.yarn

# ==============================================================================
# STAGE 2 — RUNTIME
# Lean image. Only what is needed to run Frappe at production.
# ==============================================================================
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS runtime

ARG NODE_VERSION=20

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/home/frappe/frappe-bench/env/bin:$PATH"

# ---- Minimal runtime packages ---------------------------------------------
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git \
        mariadb-client redis-tools \
        wkhtmltopdf fontconfig \
        libxrender1 libxext6 libjpeg62-turbo libmariadb3 \
        ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Create frappe user with same UID (1000) as builder ------------------
RUN useradd -ms /bin/bash -u 1000 frappe

# ---- Copy the fully-built bench from the builder stage -------------------
COPY --chown=frappe:frappe --from=builder /home/frappe/frappe-bench /home/frappe/frappe-bench

# ---- Entrypoint ----------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER frappe
WORKDIR /home/frappe/frappe-bench

EXPOSE 8000 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["backend"]
