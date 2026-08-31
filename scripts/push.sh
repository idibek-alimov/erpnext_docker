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

echo "========================================================="
echo "Pushing Custom Image to Docker Hub: ${IMAGE_TAG}"
echo "========================================================="

echo "Ensuring Docker login..."
docker login

echo "Pushing ${IMAGE_TAG}..."
docker push "${IMAGE_TAG}"

echo ""
echo "========================================================="
echo "Push completed successfully!"
echo "Image is now available on Docker Hub: ${IMAGE_TAG}"
echo "You can pull and run this on any machine using Docker Compose."
echo "========================================================="
