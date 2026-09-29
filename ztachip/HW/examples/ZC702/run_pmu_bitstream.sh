#!/usr/bin/env bash
# Rebuild the bitstream WITH the PMU (no board needed). ~1-2 h.
# Reuses the existing Vivado project so MMCM + timing closure are preserved.
#
#   bash run_pmu_bitstream.sh
#
# Tip: close your web browser / heavy apps first (synthesis uses -jobs 2 + RAM).
set -e
ZC702=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702

# --- locate vivado (source settings64.sh if not already on PATH) ------------
if ! command -v vivado >/dev/null 2>&1; then
  for v in "$HOME"/Xilinx/*/Vivado/settings64.sh /tools/Xilinx/Vivado/*/settings64.sh \
           /opt/Xilinx/Vivado/*/settings64.sh "$HOME"/Xilinx/Vivado/*/settings64.sh \
           /tools/Xilinx/*/Vivado/*/settings64.sh; do
    [ -f "$v" ] && { echo "Sourcing $v"; source "$v"; break; }
  done
fi
if ! command -v vivado >/dev/null 2>&1; then
  echo "ERROR: 'vivado' not found."
  echo "Source your Vivado settings first, e.g.:"
  echo "    source /tools/Xilinx/Vivado/2025.2/settings64.sh"
  echo "then re-run:  bash $ZC702/run_pmu_bitstream.sh"
  exit 1
fi

echo "Using: $(command -v vivado)"
cd "$ZC702"
vivado -mode batch -source "$ZC702/run_pmu_bitstream.tcl" \
       -log "$ZC702/pmu_build.log" -journal "$ZC702/pmu_build.jou" -notrace

echo ""
echo "Done. Look for the 'TIMING CLOSED' line above."
echo "Bitstream: $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit"
