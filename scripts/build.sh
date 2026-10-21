#!/usr/bin/env bash
set -e

# Change directory to docker root folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

# Load .env if present
if [ -f .env ]; then
  source .env
fi

IMAGE_TAG="${1:-${DOCKER_IMAGE:-idibek/frappe-custom:v15}}"

# Auto-detect GITHUB_TOKEN from ~/.git-credentials if not set in .env
if [ -z "${GITHUB_TOKEN}" ] && [ -f ~/.git-credentials ]; then
  DETECTED_LINE=$(grep -E 'github\.com' ~/.git-credentials | head -n 1 || true)
  if [[ "$DETECTED_LINE" =~ https://([^:]+):([^@]+)@github\.com ]]; then
    GITHUB_TOKEN="${BASH_REMATCH[2]}"
  elif [[ "$DETECTED_LINE" =~ https://([^@]+)@github\.com ]]; then
    GITHUB_TOKEN="${BASH_REMATCH[1]}"
  fi
fi

echo "========================================================="
echo "Building Custom Frappe + ERPNext + HRMS + POS Awesome Image"
echo "Image Tag: ${IMAGE_TAG}"
if [ -n "${GITHUB_TOKEN}" ]; then
  echo "GitHub Auth: Configured (Private repos accessible)"
else
  echo "GitHub Auth: Anonymous (Public repos)"
fi
echo "========================================================="

# Try building with BuildKit if available, otherwise regular build
export DOCKER_BUILDKIT=1
docker build \
  --build-arg FRAPPE_REPO=https://github.com/idibek-alimov/frappe.git \
  --build-arg FRAPPE_BRANCH=main \
  --build-arg GITHUB_TOKEN="${GITHUB_TOKEN}" \
  --build-arg CACHEBUST=$(date +%s) \
  -t "${IMAGE_TAG}" \
  -f Dockerfile . "$@" || {
    echo "Retrying build without BuildKit..."
    export DOCKER_BUILDKIT=0
    docker build \
      --build-arg FRAPPE_REPO=https://github.com/idibek-alimov/frappe.git \
      --build-arg FRAPPE_BRANCH=main \
      --build-arg GITHUB_TOKEN="${GITHUB_TOKEN}" \
      --build-arg CACHEBUST=$(date +%s) \
      -t "${IMAGE_TAG}" \
      -f Dockerfile . "$@"
  }

echo ""
echo "========================================================="
echo "Build completed successfully: ${IMAGE_TAG}"
echo "Next step: Run ./scripts/push.sh to push to Docker Hub"
echo "========================================================="
