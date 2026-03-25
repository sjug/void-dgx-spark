#!/bin/bash
# Copy DGX Spark templates into a void-packages tree and create subpackage symlinks.
# Templates are copied (not symlinked) because xbps-src chroot can't follow
# symlinks pointing outside the masterdir.
#
# Usage: ./link-templates.sh [void-packages-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
VOID_PACKAGES="${1:-${PROJECT_DIR}/void-packages}"

if [ ! -d "${VOID_PACKAGES}/srcpkgs" ]; then
    echo "ERROR: void-packages directory not found at ${VOID_PACKAGES}"
    echo "Clone it first: git clone --depth 1 https://github.com/void-linux/void-packages ${VOID_PACKAGES}"
    exit 1
fi

echo "Copying DGX Spark templates into ${VOID_PACKAGES}/srcpkgs/"

for pkg in "${PROJECT_DIR}"/srcpkgs/*/; do
    pkg_name=$(basename "${pkg}")
    rm -rf "${VOID_PACKAGES}/srcpkgs/${pkg_name}"
    cp -a "${pkg}" "${VOID_PACKAGES}/srcpkgs/${pkg_name}"
    echo "  COPY: ${pkg_name}"
done

# Create subpackage symlink for kernel headers
cd "${VOID_PACKAGES}/srcpkgs"
rm -rf linux-dgx-spark-headers
ln -sf linux-dgx-spark linux-dgx-spark-headers
echo "  LINK: linux-dgx-spark-headers -> linux-dgx-spark"

echo ""
echo "Done. Build with:"
echo "  cd ${VOID_PACKAGES}"
echo "  ./xbps-src -a aarch64 pkg dgx-spark-config"
