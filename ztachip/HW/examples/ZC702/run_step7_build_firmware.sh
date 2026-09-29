#!/bin/bash
# =============================================================================
# run_step7_build_firmware.sh  — Build the board firmware (RISC-V ELF)
#
# Run from a terminal:
#   bash ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step7_build_firmware.sh
#
# This compiles the chatbot firmware (chat.cpp + all kernel code) into a
# RISC-V ELF file that XSCT will load into the ZC702 DDR at boot time.
# =============================================================================

set -e
ZTACHIP=~/Desktop/AIDAChip_Workshop_01/ztachip

echo "============================================================"
echo " Level 5 Step 2: Build RISC-V board firmware"
echo "============================================================"

# Check RISC-V toolchain
if ! command -v riscv32-unknown-elf-gcc &>/dev/null; then
    echo "ERROR: riscv32-unknown-elf-gcc not found."
    echo "The RISC-V toolchain should be at /opt/riscv/ or /opt/riscv32im/"
    echo "Check the makefile for RISCV_PATH settings."
    exit 1
fi

cd $ZTACHIP/SW

echo "Building board firmware (chat.cpp + LLM kernels)..."
echo "This takes 1-3 minutes..."
make clean
make

# Generate the flat binary that the XSCT loader downloads into DDR.
# We load a raw binary at 0x4000, NOT the ELF — the XSCT target is the ARM
# core, and a RISC-V ELF would be rejected / mis-loaded there.
echo ""
echo "Generating flat firmware binary for JTAG load..."
/opt/riscv/bin/riscv32-unknown-elf-objcopy -O binary build/ztachip.elf build/ztachip.bin

echo ""
echo "============================================================"
echo " DONE!"
ls -lh build/ztachip.elf build/ztachip.bin
echo "------------------------------------------------------------"
echo " entry point (must be 0x4000): $(/opt/riscv/bin/riscv32-unknown-elf-readelf -h build/ztachip.elf 2>/dev/null | grep -i entry | awk '{print $NF}')"
echo " ztachip.bin is what XSCT loads to DDR 0x4000"
echo "============================================================"
echo ""
echo "Next: Flash the board and run the XSCT loader."
echo "  In Vivado Tcl console (xsct):"
echo "    source ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step8_xsct_boot.tcl"
