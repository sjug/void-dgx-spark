# Void Linux on the NVIDIA DGX Spark

Provides xbps-src templates to run Void Linux on the NVIDIA DGX Spark (aarch64),
with full GPU support via the NVIDIA kernel and driver stack.

Ported from the [NixOS DGX Spark](https://github.com/graham33/nixos-dgx-spark)
project, applying lessons learned to Void Linux packaging.

## Components

| Package | Description |
|---|---|
| `linux-dgx-spark` | NVIDIA kernel 6.17.1 with GB10 SoC and r8127 Realtek NIC support |
| `linux-dgx-spark-headers` | Kernel headers for building out-of-tree modules |
| `nvidia-dgx-spark` | NVIDIA 580.142 userspace libraries and utilities (nvidia-smi, etc.) |
| `nvidia-dgx-spark-dkms` | NVIDIA 580.142 open kernel modules (DKMS) |
| `nvidia-dgx-spark-firmware` | NVIDIA GPU firmware blobs (580.126.09 + 580.142) |
| `dgx-spark-config` | Module blacklisting, sysctl, dracut configuration |
| `dgx-dashboard` | DGX Dashboard web interface with runit services |

## Hardware

- NVIDIA DGX Spark (GB10 SoC, aarch64)
- Also reported to work on the Asus Ascent GX10

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
   ./xbps-src -a aarch64 pkg linux-dgx-spark
   ./xbps-src -a aarch64 pkg nvidia-dgx-spark
   ./xbps-src -a aarch64 pkg nvidia-dgx-spark-dkms
   ./xbps-src -a aarch64 pkg nvidia-dgx-spark-firmware
   ./xbps-src -a aarch64 pkg dgx-spark-config
   ./xbps-src -a aarch64 pkg dgx-dashboard
   ```

4. Install on your DGX Spark:
   ```bash
   xbps-install -R hostdir/binpkgs -R hostdir/binpkgs/nonfree \
       linux-dgx-spark nvidia-dgx-spark nvidia-dgx-spark-dkms \
       nvidia-dgx-spark-firmware dgx-spark-config dgx-dashboard
   ```

## Development

### Cross-Compilation from x86_64

The recommended build method. Requires the `xbps` package on your host
(available in AUR for Arch Linux).

```bash
cd void-packages
./xbps-src binary-bootstrap
./xbps-src -a aarch64 pkg <package-name>
```

Built packages appear in `hostdir/binpkgs/` and `hostdir/binpkgs/nonfree/`.

**Important**: after changing a template, always run `./scripts/link-templates.sh`
to copy the updated templates into void-packages, then
`./xbps-src -a aarch64 clean <package>` before rebuilding.

### Recovery Image

The DGX Spark recovery image (`dgx-spark-recovery-image-*.tar.gz`) contains
split XZ-compressed filesystem parts (`fastos.partaa` + `fastos.partab`).
Concatenate and decompress to get the root filesystem:

```bash
tar xf dgx-spark-recovery-image-*.tar.gz
cat usbimg.customer/usb/fastos.parta* | xz -d > fastos.img
fuse2fs -o ro,fakeroot fastos.img /mnt    # no root needed
```

### Kernel Configuration

The kernel config (`srcpkgs/linux-dgx-spark/files/arm64-dotconfig`) is exported
from NVIDIA's Debian annotations using the script in the NV-Kernels source:

```bash
python3 debian/scripts/misc/annotations \
    --file debian.nvidia-6.17/config/annotations \
    --arch arm64 --flavour arm64-nvidia --export > arm64-dotconfig
```

The `SYSTEM_TRUSTED_KEYS` and `SYSTEM_REVOCATION_KEYS` options must be set to
empty strings (they reference Ubuntu-specific certificate files).

## Licence

MIT
