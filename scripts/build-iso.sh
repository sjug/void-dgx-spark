#!/bin/bash
# Build a Void Linux live ISO for the DGX Spark
# Requires: xbps, squashfs-tools, libisoburn (xorriso), qemu-user-static
#
# Usage: sudo ./scripts/build-iso.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
MKLIVE_DIR="${PROJECT_DIR}/void-mklive"
PACKAGES_DIR="$(realpath "${PROJECT_DIR}/void-packages/hostdir/binpkgs")"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (mklive creates filesystems)"
    echo "Usage: sudo $0"
    exit 1
fi

if [ ! -d "${MKLIVE_DIR}" ]; then
    echo "ERROR: void-mklive not found. Clone it first:"
    echo "  git clone --depth 1 https://github.com/void-linux/void-mklive ${MKLIVE_DIR}"
    exit 1
fi

# Check required tools
for cmd in xorriso mksquashfs xbps-install; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found"
        echo "Install: pacman -S libisoburn squashfs-tools xbps"
        exit 1
    fi
done

# Check binfmt_misc for aarch64
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "ERROR: binfmt_misc for aarch64 not registered"
    echo "Run: systemctl restart systemd-binfmt"
    exit 1
fi

# Ensure repos are indexed
echo "Indexing local package repos..."
XBPS_ARCH=aarch64 xbps-rindex -fa "${PACKAGES_DIR}"/*.xbps
XBPS_ARCH=aarch64 xbps-rindex -fa "${PACKAGES_DIR}"/nonfree/*.xbps

# Bundle our packages as a local repo on the ISO so they're available
# during installation to NVMe (xbps-install -R /repo ...)
INCLUDE_DIR=$(mktemp -d)
mkdir -p "${INCLUDE_DIR}/repo/nonfree"
cp "${PACKAGES_DIR}"/*.xbps "${PACKAGES_DIR}"/aarch64-repodata "${INCLUDE_DIR}/repo/"
cp "${PACKAGES_DIR}"/nonfree/*.xbps "${PACKAGES_DIR}"/nonfree/aarch64-repodata "${INCLUDE_DIR}/repo/nonfree/"
echo "Bundled $(find "${INCLUDE_DIR}/repo" -name '*.xbps' | wc -l) packages for local repo"

cd "${MKLIVE_DIR}"

# DGX Spark kernel command line parameters
# Validated against sparky/buddy 2026-03-25
CMDLINE="console=tty0 console=ttyS0,921600"
CMDLINE+=" earlycon=uart,mmio32,0x16A00000"
CMDLINE+=" init_on_alloc=0"
CMDLINE+=" iommu.passthrough=0"
CMDLINE+=" initcall_blacklist=tegra234_cbb_init"
CMDLINE+=" pci=pcie_bus_safe"

# Packages to include in the live image
# linux-dgx-spark replaces the default linux kernel (ignored via -g)
# dgx-spark-config pulls in the full DGX Spark stack
EXTRA_PKGS="dgx-spark-config"
EXTRA_PKGS+=" nvidia-dgx-spark-modules"
EXTRA_PKGS+=" cryptsetup rpcbind nftables iptables-nft wireless-regdb"
EXTRA_PKGS+=" ethtool rdma-core iperf3"
EXTRA_PKGS+=" pciutils usbutils lshw htop"
EXTRA_PKGS+=" vim git curl tmux uv podman"

# Services to enable
SERVICES="sshd dhcpcd nvidia-persistenced"
SERVICES+=" dgx-dashboard dgx-dashboard-admin"

echo ""
echo "=== Building DGX Spark Void Linux ISO ==="
echo "Arch:     aarch64"
echo "Kernel:   linux-dgx-spark"
echo "Packages: ${EXTRA_PKGS}"
echo "Services: ${SERVICES}"
echo "Cmdline:  ${CMDLINE}"
echo ""

# Workaround: mklive uses 'mount --rbind /$f' which pulls in sub-mounts like
# cgroup2, efivarfs, binfmt_misc from the host. These can't be unmounted since
# the host systemd owns them, causing mklive to fail at the squashfs step.
# Fix: use --bind (no sub-mounts) instead of --rbind.
sed -i 's/mount --rbind/mount --bind/' mklive.sh

# Workaround: mklive's -v flag only accepts linux<version> or linux-<series>.
# Add linux-dgx-spark to the case statement so it's treated as a custom kernel.
sed -i '/linux-asahi)/i\
    linux-dgx-spark)\
        IGNORE_PKGS+=(linux)\
        PACKAGE_LIST+=(linux-dgx-spark linux-base)\
        ;;' mklive.sh

# Use -g to ignore the default 'linux' metapackage (we provide linux-dgx-spark)
# -K keeps builddir on failure for debugging
# Local repos listed first so our packages take priority
./mklive.sh \
    -a aarch64 \
    -K \
    -I "${INCLUDE_DIR}" \
    -x "${PROJECT_DIR}/scripts/iso-postsetup.sh" \
    -r "${PACKAGES_DIR}" \
    -r "${PACKAGES_DIR}/nonfree" \
    -r "https://repo-default.voidlinux.org/current/aarch64" \
    -r "https://repo-default.voidlinux.org/current/aarch64/nonfree" \
    -v linux-dgx-spark \
    -g "linux linux-headers" \
    -p "${EXTRA_PKGS}" \
    -S "${SERVICES}" \
    -C "${CMDLINE}" \
    -T "Void Linux DGX Spark" \
    -o "${PROJECT_DIR}/void-dgx-spark-live.iso"

echo ""
echo "=== ISO built ==="
ls -lh "${PROJECT_DIR}/void-dgx-spark-live.iso"
echo ""
echo "Write to USB:"
echo "  sudo dd if=void-dgx-spark-live.iso of=/dev/sdX bs=4M status=progress"
