#!/usr/bin/env bash
# rebuild_fw.sh — recompile the chatbot firmware and produce the two-binary
# split (vector.bin -> OCM @0x4000, main.bin -> DDR @0x100000).
#
# Run:  bash /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/SW/rebuild_fw.sh
set -e

SW=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/SW
cd "$SW"

OBJCOPY=/opt/riscv/bin/riscv32-unknown-elf-objcopy

echo "=== [1] Forcing relink (linker.ld is not a make dependency) ==="
rm -f build/ztachip.elf build/ztachip.bin

echo "=== [2] Building ELF (recompiles changed sources, e.g. llm.cpp) ==="
make build/ztachip.elf

echo "=== [3] Splitting into vector.bin (OCM) + main.bin (DDR) ==="
# vector stub: just the ._vector section -> loads at 0x4000 (OCM)
$OBJCOPY -O binary -j ._vector build/ztachip.elf build/vector.bin
# everything else -> loads at 0x100000 (DDR), minus OCM/stack/TCM sections
$OBJCOPY -O binary -R ._vector -R ._stack -R .TCM_DATA build/ztachip.elf build/main.bin

echo "=== [4] Sanity ==="
echo "vector.bin: $(stat -c %s build/vector.bin) bytes"
echo "main.bin:   $(stat -c %s build/main.bin) bytes"
echo ".data VMA (must be 0x00100000):"
/opt/riscv/bin/riscv32-unknown-elf-objdump -h build/ztachip.elf | grep -E '\.data|\._vector' || true

echo "=== DONE.  Now run the board flow: ==="
echo "  bash $SW/../HW/examples/ZC702/run_board_day.sh   (board was powered OFF)"
