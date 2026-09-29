#!/usr/bin/env bash
# =============================================================================
# upload_model.sh -- upload ONE (large) model into the board's DDR over JTAG.
#
#   bash upload_model.sh                 # default: 360M large model, no FPGA prog
#   bash upload_model.sh 360m            # SmolLM2-360M Q4  (308 MB, the large one)
#   bash upload_model.sh q4              # SmolLM2-135M Q4  (141 MB)
#   bash upload_model.sh q8              # SmolLM2-135M Q8  (191 MB)
#   bash upload_model.sh /path/to/x.ZUF # any .ZUF file by path
#
#   add  prog  as a 2nd arg to ALSO program the bitstream first:
#   bash upload_model.sh 360m prog
#
# Slow JTAG? lower the clock:  UP_JTAG_HZ=10000000 bash upload_model.sh 360m
# =============================================================================
set -e

ROOT=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
ZC="$ROOT/HW/examples/ZC702"
M="$ROOT/models"
TCL="$ZC/upload_model.tcl"
XSDB=/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb

WHICH="${1:-360m}"
PROG_ARG="${2:-}"

case "$WHICH" in
  q4)   ZUF="$M/SMOLLM2_Q4.ZUF"      ;;
  q8)   ZUF="$M/SMOLLM2_Q8.ZUF"      ;;
  360m) ZUF="$M/SMOLLM2_360M_Q4.ZUF" ;;
  *)    ZUF="$WHICH"                 ;;   # treat as a path
esac

[ -f "$ZUF" ] || { echo "MISSING model: $ZUF"; exit 1; }
[ -x "$XSDB" ] || { echo "MISSING xsdb: $XSDB"; exit 1; }

UP_PROG=0
[ "$PROG_ARG" = "prog" ] && UP_PROG=1

echo "##############################################################"
echo "#  UPLOAD MODEL : $(basename "$ZUF")  ($(stat -c %s "$ZUF") bytes)"
echo "#  program bitstream first : $([ $UP_PROG -eq 1 ] && echo yes || echo no)"
echo "##############################################################"

source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
UP_ZUF="$ZUF" UP_PROG="$UP_PROG" "$XSDB" "$TCL"

echo ""
echo "=== UPLOAD DONE: $(basename "$ZUF") is in DDR @ 0x10000000 ==="
