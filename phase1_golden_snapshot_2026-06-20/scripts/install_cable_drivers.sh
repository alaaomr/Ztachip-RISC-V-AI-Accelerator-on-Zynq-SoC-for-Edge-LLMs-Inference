#!/usr/bin/env bash
# Installs the Xilinx USB cable udev rules so hw_server can open the
# Platform Cable USB II (fixes LIBUSB_ERROR_ACCESS). MUST run with sudo.
#   sudo bash install_cable_drivers.sh
set -e
cd /home/eslam-elshokafy/Xilinx/2025.2/data/xicom/cable_drivers/lin64/install_script/install_drivers
./install_drivers
echo ""
echo "=== Done. Now UNPLUG and REPLUG the Platform Cable USB from your PC. ==="
