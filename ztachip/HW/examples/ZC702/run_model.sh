#!/usr/bin/env bash
# =============================================================================
# run_model.sh — benchmark ONE model on ZC702, independently.
#
#   bash run_model.sh q4            # SmolLM2-135M Q4 (repo default), 30 prompts
#   bash run_model.sh q8            # SmolLM2-135M Q8
#   bash run_model.sh 360m          # SmolLM2-360M Q4
#
#   arg1 = q4 | q8 | 360m           (which model)
#   arg2 = smoke | 1 | N            (scope; default 1 = 30 prompts x 1 repeat)
#   arg3 = full | swap | resume     (default full = self-contained bring-up)
#            full  : power-up bring-up + program bitstream + load THIS model
#            swap  : board already up -> just load THIS model + restart firmware
#            resume: model already in DDR -> just benchmark (no reload)
#
# Each invocation writes its own files in bench/results/:
#   results_<tag>.csv  raw_runs_<tag>.txt  console_<tag>.log
# Then run:  python3 bench/summarize.py   (aggregates whatever models are present)
#
# Slow JTAG? lower the clock:  BENCH_JTAG_HZ=10000000 bash run_model.sh 360m
# =============================================================================
set -e
WHICH="${1:?usage: bash run_model.sh <q4|q8|360m> [smoke|1|N] [full|swap|resume]}"
SCOPE="${2:-1}"
MODE="${3:-full}"

ROOT=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
ZC="$ROOT/HW/examples/ZC702"
M="$ROOT/models"
TCL="$ZC/board_benchmark.tcl"
XSDB=/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb

case "$WHICH" in
  q4)   ZUF="$M/SMOLLM2_Q4.ZUF";      NAME="SmolLM2-135M-Instruct-Q4ZUF"; TAG="smollm135_q4"  ;;
  q8)   ZUF="$M/SMOLLM2_Q8.ZUF";      NAME="SmolLM2-135M-Instruct-Q8ZUF"; TAG="smollm135_q8"  ;;
  360m) ZUF="$M/SMOLLM2_360M_Q4.ZUF"; NAME="SmolLM2-360M-Instruct-Q4ZUF"; TAG="smollm360_q4" ;;
  *) echo "arg1 must be q4 | q8 | 360m"; exit 1 ;;
esac

[ -f "$ZUF" ] || { echo "MISSING model: $ZUF"; exit 1; }

echo "##############################################################"
echo "#  MODEL : $NAME"
echo "#  file  : $(basename "$ZUF")  ($(stat -c %s "$ZUF") bytes)"
echo "#  mode  : $MODE     scope: $SCOPE     tag: $TAG"
echo "##############################################################"

source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
BENCH_MODE="$MODE" BENCH_SCOPE="$SCOPE" \
BENCH_ZUF="$ZUF" BENCH_MODELNAME="$NAME" BENCH_TAG="$TAG" \
  "$XSDB" "$TCL"

echo ""
echo "=== DONE: $NAME ==="
echo "    results: $ZC/bench/results/results_${TAG}.csv"
echo "    summarize all models so far:  python3 $ZC/bench/summarize.py"
