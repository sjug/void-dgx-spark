#!/bin/bash
# Post-setup script for mklive (-x flag)
# Runs after packages are installed but before initramfs/squashfs generation.
ROOTFS="$1"

# Run depmod to index nvidia modules (the INSTALL script may not run in chroot)
echo "Running depmod for nvidia modules..."
chroot "$ROOTFS" depmod -a 6.17.9_1

# Switch iptables to nft backend
echo "Switching iptables to nft backend..."
chroot "$ROOTFS" xbps-alternatives -s iptables-nft
