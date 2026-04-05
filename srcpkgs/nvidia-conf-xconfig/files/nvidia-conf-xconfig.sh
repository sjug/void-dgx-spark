#!/bin/bash
# Configure X for NVIDIA GPU -- simplified from upstream nvidia-conf-xconfig 26.02-1
# The upstream adaptive/OEM logic is stripped; Spark always needs this.
exec nvidia-xconfig --allow-empty-initial-configuration
