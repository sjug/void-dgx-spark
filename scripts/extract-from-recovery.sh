#!/bin/bash
# Extract NVIDIA packages from the DGX Spark recovery image
#
# The recovery image (dgx-spark-recovery-image-*.tar.gz) contains:
#   usbimg.customer/usb/fastos.partaa (3.8GB)  } concatenated = squashfs/ext4 image
#   usbimg.customer/usb/fastos.partab (1.5GB)  }
#   usbimg.customer/usb/vmlinuz                - kernel
#   usbimg.customer/usb/initrd                 - initramfs
#   usbimg.customer/usb/fw/                    - firmware updates (EC, SoC, TPM, etc.)
#
# Usage: ./extract-from-recovery.sh /path/to/dgx-spark-recovery-image-*.tar.gz [output-dir]
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <recovery-image.tar.gz> [output-dir]"
    exit 1
fi

RECOVERY_TAR="$(realpath "$1")"
OUTPUT_DIR="${2:-./recovery-extracted}"
WORK_DIR=$(mktemp -d)

cleanup() {
    echo "Cleaning up..."
    sudo umount "${WORK_DIR}/mnt" 2>/dev/null || true
    sudo losetup -D 2>/dev/null || true
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Extracting recovery image ==="
echo "Source: ${RECOVERY_TAR}"
echo "Output: ${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${WORK_DIR}/mnt"

# Step 1: Extract the split filesystem parts from the tarball
echo "Extracting filesystem image parts from tarball..."
tar xf "${RECOVERY_TAR}" -C "${WORK_DIR}" \
    usbimg.customer/usb/fastos.partaa \
    usbimg.customer/usb/fastos.partab

# Step 2: Concatenate the split parts into a single image
FS_IMAGE="${WORK_DIR}/fastos.img"
echo "Concatenating fastos.partaa + fastos.partab..."
cat "${WORK_DIR}/usbimg.customer/usb/fastos.partaa" \
    "${WORK_DIR}/usbimg.customer/usb/fastos.partab" > "${FS_IMAGE}"

echo "Filesystem image size: $(du -h "${FS_IMAGE}" | cut -f1)"
echo "Image type: $(file "${FS_IMAGE}" | cut -d: -f2)"

# Free the split parts to save disk space
rm -f "${WORK_DIR}/usbimg.customer/usb/fastos.partaa" \
      "${WORK_DIR}/usbimg.customer/usb/fastos.partab"

# Step 3: Mount the filesystem image
echo "Mounting filesystem image..."
if sudo mount -o loop,ro "${FS_IMAGE}" "${WORK_DIR}/mnt" 2>/dev/null; then
    echo "Mounted directly (squashfs/ext4)"
elif file "${FS_IMAGE}" | grep -qi "partition\|dos/mbr\|gpt"; then
    # Disk image with partitions — find and mount root
    LOOP_DEV=$(sudo losetup --find --show --partscan "${FS_IMAGE}")
    echo "Loop device: ${LOOP_DEV}"
    for part in "${LOOP_DEV}p"*; do
        if sudo mount -o ro "${part}" "${WORK_DIR}/mnt" 2>/dev/null; then
            echo "Mounted partition ${part}"
            break
        fi
    done
else
    echo "ERROR: Could not mount filesystem image"
    file "${FS_IMAGE}"
    exit 1
fi

# Verify mount
if ! mountpoint -q "${WORK_DIR}/mnt"; then
    echo "ERROR: Mount failed"
    exit 1
fi

echo "Mounted successfully. Root contents:"
ls "${WORK_DIR}/mnt/"

# Step 4: Extract NVIDIA components
echo ""
echo "=== Extracting NVIDIA components ==="

# NVIDIA driver binaries
echo "--- NVIDIA binaries ---"
mkdir -p "${OUTPUT_DIR}/nvidia-bin"
for bin in nvidia-smi nvidia-debugdump nvidia-persistenced nvidia-settings \
           nvidia-cuda-mps-control nvidia-cuda-mps-server nvidia-ctk \
           nvidia-container-runtime nvidia-container-cli; do
    if [ -f "${WORK_DIR}/mnt/usr/bin/${bin}" ]; then
        cp "${WORK_DIR}/mnt/usr/bin/${bin}" "${OUTPUT_DIR}/nvidia-bin/"
        echo "  ${bin}"
    fi
done

# NVIDIA libraries
echo "--- NVIDIA libraries ---"
mkdir -p "${OUTPUT_DIR}/nvidia-lib"
for libdir in usr/lib/aarch64-linux-gnu lib/aarch64-linux-gnu; do
    if [ -d "${WORK_DIR}/mnt/${libdir}" ]; then
        find "${WORK_DIR}/mnt/${libdir}/" \
            \( -name "libnvidia*" -o -name "libcuda*" -o -name "libnvcuvid*" \
               -o -name "libnvoptix*" -o -name "libvdpau_nvidia*" \) \
            -exec cp -a {} "${OUTPUT_DIR}/nvidia-lib/" \; 2>/dev/null || true
    fi
done
echo "  $(ls "${OUTPUT_DIR}/nvidia-lib/" 2>/dev/null | wc -l) library files"

# NVIDIA firmware
echo "--- NVIDIA firmware ---"
if [ -d "${WORK_DIR}/mnt/lib/firmware/nvidia" ]; then
    mkdir -p "${OUTPUT_DIR}/nvidia-firmware"
    cp -a "${WORK_DIR}/mnt/lib/firmware/nvidia/"* "${OUTPUT_DIR}/nvidia-firmware/"
    echo "  $(find "${OUTPUT_DIR}/nvidia-firmware" -type f | wc -l) firmware files"
    echo "  Dirs: $(ls "${OUTPUT_DIR}/nvidia-firmware/")"
fi

# Realtek firmware
echo "--- Realtek firmware ---"
if [ -d "${WORK_DIR}/mnt/lib/firmware/rtl_nic" ]; then
    mkdir -p "${OUTPUT_DIR}/rtl-firmware"
    cp -a "${WORK_DIR}/mnt/lib/firmware/rtl_nic/"* "${OUTPUT_DIR}/rtl-firmware/"
    echo "  $(ls "${OUTPUT_DIR}/rtl-firmware/" | wc -l) firmware files"
fi

# NVIDIA kernel modules (pre-built)
echo "--- NVIDIA kernel modules ---"
mkdir -p "${OUTPUT_DIR}/nvidia-modules"
find "${WORK_DIR}/mnt/lib/modules/" -name "nvidia*.ko*" 2>/dev/null | while read f; do
    cp "$f" "${OUTPUT_DIR}/nvidia-modules/"
    echo "  $(basename "$f")"
done

# r8127 module
find "${WORK_DIR}/mnt/lib/modules/" -name "r8127*" 2>/dev/null | while read f; do
    cp "$f" "${OUTPUT_DIR}/nvidia-modules/"
    echo "  $(basename "$f") (Realtek NIC)"
done

# DGX Dashboard
echo "--- DGX Dashboard ---"
mkdir -p "${OUTPUT_DIR}/dgx-dashboard"
for d in opt/nvidia/dgx-dashboard opt/nvidia/dgx-dashboard-service; do
    if [ -d "${WORK_DIR}/mnt/${d}" ]; then
        cp -a "${WORK_DIR}/mnt/${d}/"* "${OUTPUT_DIR}/dgx-dashboard/"
    fi
done
ls "${OUTPUT_DIR}/dgx-dashboard/" 2>/dev/null

# CUDA toolkit
echo "--- CUDA toolkit ---"
if [ -d "${WORK_DIR}/mnt/usr/local/cuda-13.0" ]; then
    echo "  Found CUDA 13.0 at /usr/local/cuda-13.0"
    echo "  Size: $(du -sh "${WORK_DIR}/mnt/usr/local/cuda-13.0" | cut -f1)"
    # Only copy headers and key binaries (full CUDA is huge)
    mkdir -p "${OUTPUT_DIR}/cuda/bin" "${OUTPUT_DIR}/cuda/lib64"
    cp "${WORK_DIR}/mnt/usr/local/cuda-13.0/bin/nvcc" "${OUTPUT_DIR}/cuda/bin/" 2>/dev/null || true
    cp "${WORK_DIR}/mnt/usr/local/cuda-13.0/version.json" "${OUTPUT_DIR}/cuda/" 2>/dev/null || true
    echo "  (Skipping full CUDA copy — use .deb packages from NVIDIA repo instead)"
fi

# Package list for reference
echo "--- Installed packages ---"
if [ -f "${WORK_DIR}/mnt/var/lib/dpkg/status" ]; then
    grep "^Package: " "${WORK_DIR}/mnt/var/lib/dpkg/status" | \
        sed 's/^Package: //' | sort > "${OUTPUT_DIR}/package-list.txt"
    echo "  $(wc -l < "${OUTPUT_DIR}/package-list.txt") packages"
    echo "  NVIDIA packages:"
    grep -i nvidia "${OUTPUT_DIR}/package-list.txt" | sed 's/^/    /'
fi

# Kernel version info
echo "--- Kernel info ---"
ls "${WORK_DIR}/mnt/lib/modules/" 2>/dev/null | sed 's/^/  /'
if [ -f "${WORK_DIR}/mnt/boot/vmlinuz-"* ]; then
    ls "${WORK_DIR}/mnt/boot/vmlinuz-"* 2>/dev/null | sed 's/^/  /'
fi

echo ""
echo "=== Extraction complete ==="
echo "Output directory: ${OUTPUT_DIR}"
du -sh "${OUTPUT_DIR}"/* 2>/dev/null
