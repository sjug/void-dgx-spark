#!/bin/bash
# Set up a Void Linux aarch64 QEMU VM for testing DGX Spark packages
# Requires: qemu-system-aarch64, edk2-aarch64, wget
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DIR="${SCRIPT_DIR}/../vm"
ROOTFS_URL="https://repo-default.voidlinux.org/live/current/void-aarch64-ROOTFS-20250202.tar.xz"
ROOTFS_FILE="${VM_DIR}/void-aarch64-rootfs.tar.xz"
DISK_IMAGE="${VM_DIR}/void-aarch64.qcow2"
DISK_SIZE="20G"
EFI_FW="/usr/share/edk2/aarch64/QEMU_EFI.fd"
EFI_VARS="${VM_DIR}/QEMU_VARS.fd"

mkdir -p "${VM_DIR}"

# Check dependencies
for cmd in qemu-system-aarch64 qemu-img wget; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed"
        exit 1
    fi
done

if [ ! -f "${EFI_FW}" ]; then
    echo "ERROR: edk2-aarch64 UEFI firmware not found at ${EFI_FW}"
    echo "Install with: pacman -S edk2-aarch64"
    exit 1
fi

# Download Void Linux aarch64 rootfs
if [ ! -f "${ROOTFS_FILE}" ]; then
    echo "Downloading Void Linux aarch64 rootfs..."
    wget -O "${ROOTFS_FILE}" "${ROOTFS_URL}"
fi

# Create disk image
if [ ! -f "${DISK_IMAGE}" ]; then
    echo "Creating ${DISK_SIZE} disk image..."
    qemu-img create -f qcow2 "${DISK_IMAGE}" "${DISK_SIZE}"

    # Create a raw image, partition, format, and install rootfs
    RAW_IMG="${VM_DIR}/void-aarch64.raw"
    qemu-img create -f raw "${RAW_IMG}" "${DISK_SIZE}"

    # Partition: 512MB EFI + rest as root
    echo "Partitioning disk..."
    parted -s "${RAW_IMG}" \
        mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart root ext4 513MiB 100%

    # Set up loop device
    LOOP_DEV=$(sudo losetup --find --show --partscan "${RAW_IMG}")
    echo "Loop device: ${LOOP_DEV}"

    # Format partitions
    echo "Formatting partitions..."
    sudo mkfs.vfat -F32 "${LOOP_DEV}p1"
    sudo mkfs.ext4 -L voidlinux "${LOOP_DEV}p2"

    # Mount and extract rootfs
    MOUNT_DIR="${VM_DIR}/mnt"
    mkdir -p "${MOUNT_DIR}"
    sudo mount "${LOOP_DEV}p2" "${MOUNT_DIR}"
    sudo mkdir -p "${MOUNT_DIR}/boot/efi"
    sudo mount "${LOOP_DEV}p1" "${MOUNT_DIR}/boot/efi"

    echo "Extracting Void Linux rootfs..."
    sudo tar xf "${ROOTFS_FILE}" -C "${MOUNT_DIR}"

    # Configure the system
    echo "Configuring system..."

    # Set root password to 'void'
    echo 'root:void' | sudo chroot "${MOUNT_DIR}" chpasswd

    # Enable DHCP on eth0
    sudo mkdir -p "${MOUNT_DIR}/etc/sv/dhcpcd-eth0"
    cat <<'DHCP_EOF' | sudo tee "${MOUNT_DIR}/etc/sv/dhcpcd-eth0/run" > /dev/null
#!/bin/sh
exec dhcpcd -B eth0 2>&1
DHCP_EOF
    sudo chmod 755 "${MOUNT_DIR}/etc/sv/dhcpcd-eth0/run"
    sudo ln -sf /etc/sv/dhcpcd-eth0 "${MOUNT_DIR}/var/service/"

    # Enable SSH
    sudo ln -sf /etc/sv/sshd "${MOUNT_DIR}/var/service/"

    # Set hostname
    echo "void-dgx-test" | sudo tee "${MOUNT_DIR}/etc/hostname" > /dev/null

    # Enable serial console
    sudo ln -sf /etc/sv/agetty-ttyAMA0 "${MOUNT_DIR}/var/service/" 2>/dev/null || true

    # fstab
    cat <<'FSTAB_EOF' | sudo tee "${MOUNT_DIR}/etc/fstab" > /dev/null
LABEL=voidlinux / ext4 defaults 0 1
FSTAB_EOF

    # Install GRUB for aarch64 EFI
    # This needs to be done inside the chroot with proper packages
    # For now, we'll use direct kernel boot via QEMU -kernel flag

    # Cleanup
    sudo umount "${MOUNT_DIR}/boot/efi" 2>/dev/null || true
    sudo umount "${MOUNT_DIR}"
    sudo losetup -d "${LOOP_DEV}"

    # Convert raw to qcow2
    qemu-img convert -f raw -O qcow2 "${RAW_IMG}" "${DISK_IMAGE}"
    rm -f "${RAW_IMG}"

    echo "Disk image created: ${DISK_IMAGE}"
fi

# Create EFI variable store
if [ ! -f "${EFI_VARS}" ]; then
    truncate -s 64M "${EFI_VARS}"
fi

# Create VM start script
cat > "${VM_DIR}/start-vm.sh" <<VMEOF
#!/bin/bash
# Start Void Linux aarch64 VM
# SSH: ssh -p 2222 root@localhost (password: void)
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"

exec qemu-system-aarch64 \\
    -M virt \\
    -cpu max \\
    -m 8G \\
    -smp 4 \\
    -drive if=pflash,format=raw,readonly=on,file=${EFI_FW} \\
    -drive if=pflash,format=raw,file=\${SCRIPT_DIR}/QEMU_VARS.fd \\
    -drive file=\${SCRIPT_DIR}/void-aarch64.qcow2,format=qcow2,if=virtio \\
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \\
    -device virtio-net-pci,netdev=net0 \\
    -device virtio-rng-pci \\
    -nographic
VMEOF
chmod +x "${VM_DIR}/start-vm.sh"

echo ""
echo "=== Void Linux aarch64 VM ready ==="
echo "Start VM:  ${VM_DIR}/start-vm.sh"
echo "SSH:       ssh -p 2222 root@localhost"
echo "Password:  void"
echo ""
echo "Inside the VM, install build tools:"
echo "  xbps-install -Su"
echo "  xbps-install -y base-devel git"
