#!/bin/bash
# Configure NVMe Interrupt Coalescing for DGX Spark
# From nvidia-nvme-options 26.02-1

ENABLED_VALUE="0x00000107"
DISABLED_VALUE="00000000"

get_nvme_drives() {
    # Find all nvme controller devices (not partitions or namespaces)
    # Using [0-9]* to match any number of digits (e.g., nvme0, nvme10, nvme33)
    echo "$(ls -d /dev/nvme[0-9]* 2>/dev/null | grep -E '^/dev/nvme[0-9]+$')"
}

set_coalescing() {
    local device=${1}
    local value=${2}
    local vendor_id=${3}

    logger "Setting interrupt coalescing for ${device} (vendor: ${vendor_id}) to ${value}"
    if ! nvme set-feature "${device}" -f 8 --value "${value}"; then
        logger "Error: Failed to set interrupt coalescing for ${device}"
        return 1
    fi

    local current_value=$(nvme get-feature "${device}" -f 8 | awk -F':' '{print $3}')
    if [ "${current_value}" != "${value}" ]; then
        logger "Error: Failed to verify interrupt coalescing setting for ${device}. Expected: ${value}, Got: ${current_value}"
        return 1
    fi
    return 0
}

main() {
    local action=${1:-"enable"}
    local value

    if [[ ${EUID} -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi

    logger "Starting nvidia-nvme-interrupt-coalescing with action: ${action}"

    case ${action} in
        "enable") value="${ENABLED_VALUE}" ;;
        "disable") value="${DISABLED_VALUE}" ;;
        *)
            logger "Error: Invalid action ${action}"
            echo "Usage: ${0} [enable|disable]"
            exit 1
            ;;
    esac

    nvme_drives="$(get_nvme_drives)"
    if [ -z "${nvme_drives}" ]; then
        logger "No NVMe drives found, nothing to do"
        exit 0
    fi

    for device in ${nvme_drives}; do
        device_name=$(basename "${device}")
        vendor_id=$(cat "/sys/class/nvme/${device_name}/device/vendor" 2>/dev/null)
        case "${vendor_id}" in
            "0x144d"|"0x1e0f"|"0x1344") # Samsung, Kioxia, or Micron
                set_coalescing "${device}" "${value}" "${vendor_id}"
                ;;
            *)
                logger "Skipping unsupported device ${device_name} (vendor: ${vendor_id})"
                ;;
        esac
    done

    exit 0
}

main "$@"
