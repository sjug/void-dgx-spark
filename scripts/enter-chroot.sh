#!/bin/bash
# Enter the Void Linux aarch64 chroot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHROOT_DIR="${SCRIPT_DIR}/../vm/void-aarch64-chroot"

if [ ! -d "${CHROOT_DIR}/usr" ]; then
    echo "ERROR: chroot not set up. Run setup-chroot.sh first."
    exit 1
fi

# Bind-mount host filesystems
sudo mount --bind /dev "${CHROOT_DIR}/dev" 2>/dev/null || true
sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
sudo mount -t proc proc "${CHROOT_DIR}/proc" 2>/dev/null || true
sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys" 2>/dev/null || true
sudo mount -t tmpfs tmpfs "${CHROOT_DIR}/tmp" 2>/dev/null || true

# Refresh DNS
sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

# Enter chroot
echo "Entering Void Linux aarch64 chroot..."
echo "(Architecture: $(sudo chroot "${CHROOT_DIR}" uname -m 2>/dev/null || echo 'aarch64'))"
sudo chroot "${CHROOT_DIR}" /bin/bash -l

# Cleanup on exit
echo "Cleaning up mounts..."
sudo umount "${CHROOT_DIR}/tmp" 2>/dev/null || true
sudo umount "${CHROOT_DIR}/sys" 2>/dev/null || true
sudo umount "${CHROOT_DIR}/proc" 2>/dev/null || true
sudo umount "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
sudo umount "${CHROOT_DIR}/dev" 2>/dev/null || true
