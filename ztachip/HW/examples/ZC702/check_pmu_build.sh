#!/usr/bin/env bash
# Check on the PMU bitstream build (safe to run anytime).
#   bash check_pmu_build.sh
ZC702=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
BIT=$ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit

echo "==================== PMU BUILD STATUS ===================="
if pgrep -f 'run_pmu_bitstream.tcl' >/dev/null; then
  echo "STATE: ⏳ STILL RUNNING"
  # which stage?
  if pgrep -f 'impl_1' >/dev/null || grep -q 'launching implementation' "$ZC702/pmu_build_console.log" 2>/dev/null; then
    echo "STAGE: implementation / bitstream"
  else
    echo "STAGE: synthesis"
  fi
  echo "(re-run this script later; full build ~1-2 h)"
else
  echo "STATE: ✅ FINISHED (no build process running)"
fi
echo ""
echo "---- timing result (if reached) ----"
grep -E 'TIMING|CLOSED|VIOLATION|bitstream:' "$ZC702/pmu_build_console.log" 2>/dev/null | tail -6 || echo "(timing not reported yet)"
echo ""
echo "---- any errors ----"
grep -iE 'ERROR:|^ERROR' "$ZC702/pmu_build_console.log" 2>/dev/null | tail -5 || echo "(none)"
echo ""
if [ -f "$BIT" ]; then
  echo "Bitstream file: $BIT"
  echo "  modified: $(date -r "$BIT" '+%Y-%m-%d %H:%M:%S')   size: $(stat -c %s "$BIT") bytes"
fi
echo "========================================================="
