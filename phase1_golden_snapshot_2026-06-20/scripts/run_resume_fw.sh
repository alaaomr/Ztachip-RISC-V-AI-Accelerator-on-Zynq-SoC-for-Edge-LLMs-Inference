#!/usr/bin/env bash
# RESUME: model already in DDR -> just fix OCM, load firmware, open the console.
#   bash run_resume_fw.sh
source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb \
  /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/board_resume_fw.tcl
