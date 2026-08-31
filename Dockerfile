# syntax=docker/dockerfile:1.4
ARG PYTHON_VERSION=3.11
ARG DEBIAN_BASE=bookworm

# ==============================================================================
# 1. BUILDER STAGE
# ==============================================================================
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS builder

ARG FRAPPE_REPO=https://github.com/idibek-alimov/frappe.git
ARG FRAPPE_BRANCH=version-15
ARG NODE_VERSION=20

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/home/frappe/frappe-bench/env/bin:$PATH"

# Install build dependencies, Node.js and Yarn
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libffi-dev \
    libssl-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    pkg-config \
    python3-dev \
    python3-venv \
    cron \
    ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g yarn \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create frappe user
RUN useradd -ms /bin/bash -u 1000 frappe
USER frappe
WORKDIR /home/frappe

# Initialize frappe bench structure
RUN mkdir -p frappe-bench/apps frappe-bench/sites frappe-bench/config frappe-bench/logs
WORKDIR /home/frappe/frappe-bench

# Create Python virtual environment and install bench CLI
RUN python3 -m venv env && \
    ./env/bin/pip install --no-cache-dir --upgrade pip setuptools wheel && \
    ./env/bin/pip install --no-cache-dir frappe-bench

# Ensure latest code from GitHub is pulled on new builds
ARG CACHEBUST=1

# Clone and install Frappe
RUN git clone --depth 1 -b ${FRAPPE_BRANCH} ${FRAPPE_REPO} apps/frappe && \
    ./env/bin/pip install --no-cache-dir -e apps/frappe

# Copy apps list and installer script
COPY --chown=frappe:frappe apps.json apps.json
COPY --chown=frappe:frappe install_apps.py install_apps.py

# Run install_apps.py to clone and install ERPNext and POS Awesome
RUN python3 install_apps.py

# Install Node dependencies for Frappe and custom apps
RUN cd apps/frappe && (yarn install --frozen-lockfile --ignore-engines || yarn install --ignore-engines)
RUN for d in apps/*; do \
      if [ -f "$d/package.json" ]; then \
        echo "Installing yarn dependencies for $d..."; \
        (cd "$d" && (yarn install --frozen-lockfile --ignore-engines || yarn install --ignore-engines)); \
      fi \
    done

# Build JS/CSS assets into sites/assets using Frappe's native build runner
RUN cd sites && python3 -m frappe.utils.bench_helper frappe build && \
    cp -r assets /home/frappe/frappe-bench/assets_dist

# Remove unnecessary caches to keep image size small
RUN find env/ -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
RUN rm -rf /home/frappe/.cache /home/frappe/.npm /home/frappe/.yarn

# ==============================================================================
# 2. RUNTIME STAGE
# ==============================================================================
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS runtime

ARG NODE_VERSION=20

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/home/frappe/frappe-bench/env/bin:$PATH"

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    mariadb-client \
    redis-tools \
    wkhtmltopdf \
    fontconfig \
    libxrender1 \
    libxext6 \
    libjpeg62-turbo \
    libmariadb3 \
    ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create frappe user
RUN useradd -ms /bin/bash -u 1000 frappe

# Copy built bench environment from builder
COPY --chown=frappe:frappe --from=builder /home/frappe/frappe-bench /home/frappe/frappe-bench

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER frappe
WORKDIR /home/frappe/frappe-bench/sites

EXPOSE 8000 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["backend"]
