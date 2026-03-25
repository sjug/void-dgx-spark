#!/bin/bash
# Compare our config files against a live DGX Spark system.
# Usage: ./check-upstream-configs.sh [hostname]
set -euo pipefail

HOST="${1:-sparky}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../srcpkgs/dgx-spark-config/files"

echo "Checking configs against ${HOST}..."
echo ""

# modprobe configs
for remote_file in \
    "/etc/modprobe.d/nvidia-graphics-drivers-kms.conf" \
    "/etc/modprobe.d/nvidia-spark-r8169.conf" \
    "/etc/modprobe.d/zz-nvidia-drm-override.conf" \
    "/etc/modprobe.d/sbsa_gwdt.conf" \
    "/etc/modprobe.d/cppc_cpufreq.conf"; do
    echo "--- ${remote_file} ---"
    ssh "${HOST}" "cat ${remote_file} 2>/dev/null" || echo "(not found)"
done

echo ""
echo "--- NVIDIA sysctl (20-nvidia-defaults.conf) ---"
ssh "${HOST}" "cat /etc/sysctl.d/20-nvidia-defaults.conf 2>/dev/null" || echo "(not found)"

echo ""
echo "--- Upstream package versions ---"
ssh "${HOST}" 'dpkg -l nvidia-sbsa-gwdt-options nvidia-cppc-cpufreq-options nvidia-kernel-defaults nvidia-kernel-common-580 2>/dev/null | grep ^ii'

echo ""
echo "--- Our config ---"
cat "${CONFIG_DIR}/nvidia-dgx-spark.conf"
echo ""
echo "--- Our sysctl ---"
cat "${CONFIG_DIR}/99-dgx-spark.conf"

echo ""
echo "Compare manually and update if upstream has changed."
