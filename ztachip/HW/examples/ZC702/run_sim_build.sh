#!/bin/bash
# =============================================================================
# Simulation Build Script — ztachip ZC702 Graduation Project
#
# What this does (4 steps):
#   Step 1: Fix a small typo in makefile.sim (soc.c → soc.cpp)
#   Step 2: Build the ztachip kernel compiler (a tool written in C++)
#   Step 3: Use that compiler to generate kernel C files (.m → .m.c)
#   Step 4: Compile everything into a RISC-V hex file for simulation
#
# The output is: SW/build/ztachip_sim.hex
# This hex file is loaded into the simulated DDR3 memory when you run
# Vivado simulation. The RISC-V CPU will execute it.
#
# Run from a terminal:
#   bash ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_sim_build.sh
# =============================================================================

set -e  # Stop immediately if any command fails

ZTACHIP=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
SW=$ZTACHIP/SW

echo "============================================================"
echo "SIMULATION BUILD — ztachip ZC702"
echo "============================================================"

# ---- Step 1: Fix makefile.sim typo (soc.c -> soc.cpp) ----------------------
echo ""
echo "Step 1: Fixing makefile.sim typo (src/soc.c -> src/soc.cpp)..."
# Only fix if the typo is still there (so script is safe to run multiple times)
if grep -q "src/soc.c " "$SW/makefile.sim"; then
    sed -i 's|\tsrc/soc.c \\|\tsrc/soc.cpp \\|' "$SW/makefile.sim"
    echo "  Fixed: src/soc.c -> src/soc.cpp"
else
    echo "  Already fixed, skipping."
fi

# ---- Step 2: Build the ztachip kernel compiler ------------------------------
echo ""
echo "Step 2: Building ztachip kernel compiler..."
echo "  (This is a tool that translates .m kernel files to C code)"
cd "$SW/compiler"
make clean all
if [ ! -f "./compiler" ]; then
    echo "ERROR: Compiler binary not found after build!"
    exit 1
fi
echo "  Compiler built successfully: $SW/compiler/compiler"

# ---- Step 3: Generate kernel .m.c files -------------------------------------
echo ""
echo "Step 3: Compiling kernels (.m files -> .m.c files)..."
echo "  (Kernels are programs that run on ztachip's tensor processor array)"
cd "$SW"
make clean all -f makefile.kernels
echo ""

# Check key output files exist
for f in apps/main/kernels/main.m.c apps/test/kernels/test.m.c; do
    if [ -f "$SW/$f" ]; then
        echo "  OK: $f generated"
    else
        echo "  ERROR: $f was NOT generated!"
        exit 1
    fi
done

# ---- Step 4: Compile simulation firmware ------------------------------------
echo ""
echo "Step 4: Compiling simulation firmware..."
echo "  (This creates the RISC-V program that runs in simulation)"
export PATH=/opt/riscv/bin:$PATH
cd "$SW"
make clean all -f makefile.sim
echo ""

# Check the hex file was produced
HEX="$SW/build/ztachip_sim.hex"
if [ -f "$HEX" ]; then
    SIZE=$(wc -c < "$HEX")
    echo "============================================================"
    echo "SUCCESS! Simulation firmware built."
    echo "Output: $HEX"
    echo "Size:   $SIZE bytes"
    echo "============================================================"
else
    echo "ERROR: $HEX was NOT produced. Check errors above."
    exit 1
fi

echo ""
echo "Next step: Copy hex to simulation working directory and run Vivado simulation."
echo "  The Vivado sim script will do this automatically."
echo "============================================================"
