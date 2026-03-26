#!/bin/bash
# Copy DGX Spark templates into a void-packages tree and create subpackage symlinks.
# Templates are copied (not symlinked) because xbps-src chroot can't follow
# symlinks pointing outside the masterdir.
#
# Also cleans xbps-src build state for any package whose template changed,
# so you don't have to manually delete _done markers.
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
    target="${VOID_PACKAGES}/srcpkgs/${pkg_name}"

    # Check if template changed
    if [ -f "${target}/template" ] && diff -q "${pkg}/template" "${target}/template" >/dev/null 2>&1; then
        echo "  SKIP: ${pkg_name} (unchanged)"
    else
        rm -rf "${target}"
        cp -a "${pkg}" "${target}"
        echo "  COPY: ${pkg_name}"

        # Clean build state so xbps-src picks up the new template
        local_builddir="${VOID_PACKAGES}/masterdir-x86_64/builddir/.xbps-${pkg_name}"
        if [ -d "${local_builddir}" ]; then
            rm -f "${local_builddir}"/*_done
            echo "        (cleaned build state)"
        fi
    fi
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
