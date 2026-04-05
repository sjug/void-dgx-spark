# Void Linux on the NVIDIA DGX Spark

Provides xbps-src templates to run Void Linux on the NVIDIA DGX Spark (aarch64),
with full GPU, ConnectX-7 200G networking, and RDMA support.

Ported from the [NixOS DGX Spark](https://github.com/graham33/nixos-dgx-spark)
project, applying lessons learned to Void Linux packaging.

## Components

### Core

| Package | Description |
|---|---|
| `linux-dgx-spark` | NVIDIA kernel 6.17.9 with GB10 SoC and r8127 Realtek NIC support |
| `linux-dgx-spark-headers` | Kernel headers for building out-of-tree modules |
| `nvidia-dgx-spark` | NVIDIA 580.142 userspace (nvidia-smi, libs, persistenced, udev rules) |
| `nvidia-dgx-spark-modules` | Pre-built NVIDIA 580.142 open kernel modules |
| `nvidia-dgx-spark-firmware` | GPU firmware blobs (580.126.09 + 580.142) |
| `dgx-spark-config` | Meta-package: pulls in all DGX Spark packages + lldpd, installs sysctl/dracut/modprobe/limits config |
| `dgx-dashboard` | DGX Dashboard web interface with runit services |
| `nvidia-conf-xconfig` | Auto-configures X for NVIDIA GPUs at boot (oneshot runit service) |

### Networking and RDMA

| Package | Description |
|---|---|
| `rdma-core` | RDMA userspace libraries (bumped to 62.0, with runit core-service for module loading) |
| `perftest` | RDMA performance testing tools |
| `mstflint` | Mellanox firmware burning and diagnostics |
| `nvidia-mlnx-tools` | Mellanox network tools (mlnx_qos, tc_wrap, etc.) |
| `dgx-spark-mlnx-hotplug` | ConnectX hotplug udev rules |
| `nvidia-spark-mlnx-firmware-manager` | ConnectX firmware management |
| `nvidia-mstflint-loader` | Loads mstflint-access kernel module at boot |
| `mlnx-pxe-setup` | PXE boot configuration scripts for Mellanox NICs |

### Hardware tuning

| Package | Description |
|---|---|
| `nv-cpu-governor` | Sets CPU frequency governor to performance (runit service) |
| `nv-common-apis` | NVIDIA platform detection scripts |
| `nvidia-relaxed-ordering-nvme` | Enables PCIe Relaxed Ordering on NVMe drives |
| `nvidia-sbsa-gwdt-options` | SBSA watchdog timer options |
| `nvidia-cppc-cpufreq-options` | CPPC CPU frequency driver options |
| `nvidia-drm-options-modeset0` | DRM modeset=0 override |
| `nvidia-spark-realtek-mod-options` | r8127 Realtek NIC module options |
| `nvidia-kernel-defaults` | NVIDIA kernel sysctl defaults |
| `nvidia-disable-aqc-nic` | Blacklists Aquantia NIC driver |
| `nvidia-disable-init-on-alloc` | Disables init_on_alloc for performance |
| `nvidia-disable-numa-balancing` | Disables NUMA balancing for GPU workloads |
| `nvidia-nvme-options` | NVMe interrupt coalescing service (Samsung/Kioxia/Micron drives) |
| `nvidia-earlycon` | Early console UART configuration |
| `nvidia-spark-initcall-bl` | Tegra CBB initcall blacklist |
| `nvidia-spark-grub-pci` | PCIe bus safety configuration |

## Hardware

- NVIDIA DGX Spark (GB10 SoC, aarch64)

## Quick Start

1. Clone this repository and void-packages:
   ```bash
   git clone https://github.com/<user>/void-dgx-spark
   cd void-dgx-spark
   git clone --depth 1 https://github.com/void-linux/void-packages
   ```

2. Copy the custom templates into void-packages:
   ```bash
   ./scripts/link-templates.sh
   ```

3. Bootstrap xbps-src and build:
   ```bash
   cd void-packages
   ./xbps-src binary-bootstrap
   ./xbps-src -a aarch64 pkg dgx-spark-config   # builds all dependencies
   ```

4. Build a bootable live USB:
   ```bash
   git clone --depth 1 https://github.com/void-linux/void-mklive
   sudo ./scripts/build-iso.sh
   sudo dd if=void-dgx-spark-live.iso of=/dev/sdX bs=4M status=progress
   ```

## Development

### Cross-compilation from x86_64

The recommended build method. Requires the `xbps` package on your host
(available in AUR for Arch Linux).

```bash
cd void-packages
./xbps-src binary-bootstrap
./xbps-src -a aarch64 pkg <package-name>
```

Built packages appear in `hostdir/binpkgs/`.

**Important**: after changing a template, always run `./scripts/link-templates.sh`
to copy the updated templates into void-packages, then
`./xbps-src -a aarch64 clean <package>` before rebuilding.

### Kernel configuration

The kernel config (`srcpkgs/linux-dgx-spark/files/arm64-dotconfig`) is taken
from the production DGX OS system at `/boot/config-6.17.0-*-nvidia`. This is
more reliable than exporting from NVIDIA's Debian annotations, which require
the base Ubuntu config annotations that aren't included in the NV-Kernels repo.

The `SYSTEM_TRUSTED_KEYS` and `SYSTEM_REVOCATION_KEYS` options must be set to
empty strings (they reference Ubuntu-specific certificate files).

### Recovery image

The DGX Spark recovery image (`dgx-spark-recovery-image-*.tar.gz`) contains
split XZ-compressed filesystem parts (`fastos.partaa` + `fastos.partab`).
Concatenate and decompress to get the root filesystem:

```bash
tar xf dgx-spark-recovery-image-*.tar.gz
cat usbimg.customer/usb/fastos.parta* | xz -d > fastos.img
fuse2fs -o ro,fakeroot fastos.img /mnt    # no root needed
```

## Licence

MIT
