#!/bin/bash
# Remove AQC113 NIC before shutdown to prevent hang
# From nvidia-disable-aqc-nic 25.06-1

aqc113_pci_ids=$(lspci -d 1d6a:04c0 -n | awk '{print $1}')

if [ "${aqc113_pci_ids}" != "" ]; then
    for pci_id in ${aqc113_pci_ids}; do
        echo "AQC113 device found: ${pci_id}"
        echo 1 > /sys/bus/pci/devices/${pci_id}/remove
    done
fi

exit 0
