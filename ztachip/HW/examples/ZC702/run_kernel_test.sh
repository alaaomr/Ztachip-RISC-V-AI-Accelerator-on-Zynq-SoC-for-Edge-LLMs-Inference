#!/usr/bin/env bash
# =============================================================================
# run_kernel_test.sh — run the ztachip KERNEL self-test on the ZC702 board.
#
#   bash run_kernel_test.sh
#
# Loads the UNIT_TEST firmware (no model needed), runs every ztachip kernel
# against its reference C implementation, and captures the "<NAME> ok=N bad=0"
# results over JTAG into bench/results/kernel_selftest.log.
#
# 'bad=0' on every line  =>  all ztachip compute kernels verified on silicon.
# These same kernels take HOURS in RTL simulation; on the chip it's seconds.
#
# To rebuild the test firmware first (only if you changed the tests):
#   cd ../../../SW && make clean && make build/ztachip.elf UNIT_TEST=yes LLM_TEST=no
#   then objcopy ._vector -> fw_kerneltest/vector.bin, rest -> fw_kerneltest/main.bin
# =============================================================================
set -e
ZC=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
XSDB=/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb
LOG=$ZC/bench/results/kernel_selftest.log

if [ ! -f "$ZC/fw_kerneltest/main.bin" ]; then
  echo "MISSING: $ZC/fw_kerneltest/main.bin  (build the UNIT_TEST firmware first)"; exit 1
fi

echo "######################################################################"
echo "#  ztachip ON-SILICON KERNEL SELF-TEST"
echo "#  firmware : fw_kerneltest/main.bin ($(stat -c %s "$ZC/fw_kerneltest/main.bin") bytes)"
echo "#  log      : $LOG"
echo "#  NOTE: full bring-up (programs bitstream); does NOT load a model."
echo "######################################################################"

mkdir -p "$ZC/bench/results"
source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
"$XSDB" "$ZC/board_kernel_test.tcl" 2>&1 | tee "$LOG"

echo ""
echo "=== DONE.  Saved: $LOG ==="
echo "    Quick check — any kernel that FAILED (should print nothing):"
grep -iE "bad=[1-9]|fail=[1-9]|mismatch|FAILED" "$LOG" || echo "    (none — every kernel reported bad=0 / fail=0)"
echo "    Per-kernel PASS lines:"
grep -iE "ok=|PASS|====> LLM" "$LOG" || true
