#!/usr/bin/env bash
# Board-day STEP 1 launcher: program FPGA + test DDR-over-JTAG.
# Run it with:   bash run_bringup_test.sh
echo "Sourcing Vivado (gives us xsdb)..."
source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
echo "Launching xsdb foundation test..."
# 2025.2: xsct was replaced by xsdb (same commands). Use full path to be safe.
/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb \
  /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/board_bringup_test.tcl
