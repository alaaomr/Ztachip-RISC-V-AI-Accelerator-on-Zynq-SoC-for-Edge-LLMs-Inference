#!/usr/bin/env bash
# FULL board-day: program FPGA, load model+firmware, run the chatbot console.
#   bash run_board_day.sh
source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb \
  /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/board_day_run.tcl
