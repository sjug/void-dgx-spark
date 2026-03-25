#!/bin/bash
# Set up a Void Linux aarch64 chroot for building packages
# Uses qemu-user-static + binfmt_misc (much faster than full QEMU VM)
#
# Prerequisites: qemu-user-static qemu-user-static-binfmt
# On Arch: pacman -S qemu-user-static qemu-user-static-binfmt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
CHROOT_DIR="${PROJECT_DIR}/vm/void-aarch64-chroot"
ROOTFS_URL="https://repo-default.voidlinux.org/live/current/void-aarch64-ROOTFS-20250202.tar.xz"
ROOTFS_FILE="${PROJECT_DIR}/vm/void-aarch64-rootfs.tar.xz"

# Check prerequisites
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "ERROR: binfmt_misc for aarch64 not registered"
    echo "Run: sudo systemctl restart systemd-binfmt"
    exit 1
fi

if [ ! -f /usr/bin/qemu-aarch64-static ]; then
    echo "ERROR: qemu-user-static not installed"
    echo "Run: pacman -S qemu-user-static qemu-user-static-binfmt"
    exit 1
fi

mkdir -p "${PROJECT_DIR}/vm"

# Download rootfs
if [ ! -f "${ROOTFS_FILE}" ]; then
    echo "Downloading Void Linux aarch64 rootfs..."
    wget -O "${ROOTFS_FILE}" "${ROOTFS_URL}"
fi

# Create chroot
if [ ! -d "${CHROOT_DIR}/usr" ]; then
    echo "Creating aarch64 chroot at ${CHROOT_DIR}..."
    mkdir -p "${CHROOT_DIR}"
    sudo tar xf "${ROOTFS_FILE}" -C "${CHROOT_DIR}"

    # Copy qemu-aarch64-static into chroot
    sudo cp /usr/bin/qemu-aarch64-static "${CHROOT_DIR}/usr/bin/"

    # Set root password
    echo 'root:void' | sudo chroot "${CHROOT_DIR}" chpasswd

    # Configure DNS
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
fi

echo ""
echo "=== Void Linux aarch64 chroot ready ==="
echo ""
echo "Enter chroot:"
echo "  sudo ${SCRIPT_DIR}/enter-chroot.sh"
echo ""
echo "Or use systemd-nspawn (cleaner):"
echo "  sudo systemd-nspawn -D ${CHROOT_DIR}"
echo ""
echo "First time setup inside chroot:"
echo "  xbps-install -Su"
echo "  xbps-install -y base-devel git"
echo "  git clone --depth 1 https://github.com/void-linux/void-packages"
echo "  cd void-packages && ./xbps-src binary-bootstrap"
