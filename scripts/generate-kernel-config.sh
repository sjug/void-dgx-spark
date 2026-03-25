#!/bin/bash
# Generate NVIDIA DGX Spark kernel configuration for Void Linux
# Uses NVIDIA's Debian annotation script to export the upstream config,
# then applies Void-specific adjustments.
#
# Usage: ./generate-kernel-config.sh [kernel-source-dir]
#
# If kernel-source-dir is not specified, downloads from GitHub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
OUTPUT="${PROJECT_DIR}/kernel-config/config-6.17.1-nvidia"

KERNEL_REV="47ca203bcc5f4e1580c06fe1074d71497462ac8b"
KERNEL_VERSION="6.17.1"

KERNEL_SOURCE="${1:-}"

if [ -z "${KERNEL_SOURCE}" ]; then
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "${WORK_DIR}"' EXIT

    echo "Downloading NVIDIA kernel source..."
    wget -q "https://github.com/NVIDIA/NV-Kernels/archive/${KERNEL_REV}.tar.gz" \
        -O "${WORK_DIR}/kernel.tar.gz"
    tar xf "${WORK_DIR}/kernel.tar.gz" -C "${WORK_DIR}"
    KERNEL_SOURCE="${WORK_DIR}/NV-Kernels-${KERNEL_REV}"
fi

echo "Kernel source: ${KERNEL_SOURCE}"

# Step 1: Export NVIDIA config from Debian annotations
ANNOTATIONS="${KERNEL_SOURCE}/debian.nvidia-6.17/config/annotations"
ANNOTATION_SCRIPT="${KERNEL_SOURCE}/debian/scripts/misc/annotations"

if [ ! -f "${ANNOTATIONS}" ]; then
    echo "ERROR: Annotations file not found: ${ANNOTATIONS}"
    exit 1
fi

if [ ! -f "${ANNOTATION_SCRIPT}" ]; then
    echo "ERROR: Annotation script not found: ${ANNOTATION_SCRIPT}"
    exit 1
fi

echo "Exporting NVIDIA config from Debian annotations..."
python3 "${ANNOTATION_SCRIPT}" \
    --file "${ANNOTATIONS}" \
    --arch arm64 \
    --flavour arm64-nvidia \
    --export > "${KERNEL_SOURCE}/.config"

echo "Exported $(grep -c '^CONFIG_' "${KERNEL_SOURCE}/.config") options"

# Step 2: Run olddefconfig to fill defaults
echo "Running olddefconfig..."
cd "${KERNEL_SOURCE}"
make ARCH=arm64 olddefconfig

# Step 3: Apply Void-specific adjustments
echo "Applying Void-specific adjustments..."

# Ensure these are set
scripts/config --set-val CONFIG_USB_STORAGE y
scripts/config --set-val CONFIG_USB_UAS y
scripts/config --set-val CONFIG_OVERLAY_FS y
scripts/config --set-val CONFIG_SQUASHFS y

# Disable Ubuntu-specific options
scripts/config --set-val CONFIG_UBUNTU_HOST n 2>/dev/null || true

# Ensure r8127 Realtek driver is built as module
# (should already be set from NVIDIA annotations)
grep -q "CONFIG_R8127" .config && echo "r8127 config found" || echo "WARNING: CONFIG_R8127 not found in config"

# Ensure virtio drivers for QEMU testing
scripts/config --set-val CONFIG_VIRTIO y
scripts/config --set-val CONFIG_VIRTIO_PCI y
scripts/config --set-val CONFIG_VIRTIO_NET y
scripts/config --set-val CONFIG_VIRTIO_BLK y
scripts/config --set-val CONFIG_VIRTIO_CONSOLE y

# Run olddefconfig again to resolve any dependencies
make ARCH=arm64 olddefconfig

# Step 4: Copy to output
cp .config "${OUTPUT}"

echo ""
echo "=== Kernel config generated ==="
echo "Output: ${OUTPUT}"
echo "Total options: $(grep -c '^CONFIG_' "${OUTPUT}")"
echo ""
echo "Key options:"
grep -E "CONFIG_R8127|CONFIG_NVIDIA|CONFIG_USB_STORAGE|CONFIG_OVERLAY_FS|CONFIG_VIRTIO" "${OUTPUT}" | head -20
