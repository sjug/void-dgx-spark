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

    # Check if anything changed (template, files/, patches/, etc.)
    if [ -d "${target}" ] && diff -rq "${pkg}" "${target}" >/dev/null 2>&1; then
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

# Create subpackage symlinks for kernel headers and debug
cd "${VOID_PACKAGES}/srcpkgs"
for sub in linux-dgx-spark-headers linux-dgx-spark-dbg; do
    rm -rf "$sub"
    ln -sf linux-dgx-spark "$sub"
    echo "  LINK: $sub -> linux-dgx-spark"
done

# Patch common/shlibs for missing rdma-core provider libraries
# (PR submitted upstream: void-linux/void-packages#59592)
for _lib in libmlx5.so.1 libmlx4.so.1 libefa.so.1 libmana.so.1 libhns.so.1 libibmad.so.5 libibnetdisc.so.5; do
    if ! grep -q "^${_lib} " "${VOID_PACKAGES}/common/shlibs"; then
        echo "${_lib} rdma-core-22.1_1" >> "${VOID_PACKAGES}/common/shlibs"
        echo "  PATCH: added ${_lib} to common/shlibs"
    fi
done

echo ""
echo "Done. Build with:"
echo "  cd ${VOID_PACKAGES}"
echo "  ./xbps-src -a aarch64 pkg dgx-spark-config"
