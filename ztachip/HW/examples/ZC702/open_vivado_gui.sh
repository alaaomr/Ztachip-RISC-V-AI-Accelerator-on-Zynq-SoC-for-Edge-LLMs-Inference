#!/usr/bin/env bash
# Open the Vivado GUI (so you can watch the build), then source the build script
# in the Tcl Console yourself - same way you ran step13/step16 before.
#
#   bash open_vivado_gui.sh
#
# After the GUI opens, in the Tcl Console at the bottom type:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_pmu_bitstream.tcl
source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
cd /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
echo "Launching Vivado GUI (empty)... then source run_pmu_bitstream.tcl in the Tcl Console."
vivado &
