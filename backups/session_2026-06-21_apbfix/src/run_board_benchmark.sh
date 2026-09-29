#!/usr/bin/env bash
# Automated Jetson-format benchmark of SmolLM2-135M on ZC702.
#
# Usage:
#   bash run_board_benchmark.sh full smoke     # bring up board+model, run 1 prompt (VALIDATE FIRST)
#   bash run_board_benchmark.sh reprog smoke   # flash NEW bitstream, keep model in DDR, run 1 prompt
#   bash run_board_benchmark.sh resume 5       # board already up -> run 5 repeats x 30 prompts
#   bash run_board_benchmark.sh resume smoke   # quick re-check, no reload
#   bash run_board_benchmark.sh full 5         # one-shot: bring up AND run full sweep
#
# arg1 = full | reprog | resume
#        full   : program FPGA + load model (~40min) + benchmark
#        reprog : program a NEW bitstream but KEEP model+firmware in DDR (no reload), then benchmark
#        resume : board already up, model live in DDR -> just benchmark
# arg2 = smoke | <N>      (smoke = 1 prompt 1 repeat; N = number of repeats over all 30 prompts)
set -e
MODE="${1:-full}"
SCOPE="${2:-smoke}"

case "$MODE" in full|reprog|resume) ;; *) echo "arg1 must be 'full', 'reprog' or 'resume'"; exit 1;; esac
case "$SCOPE" in smoke) ;; *) [[ "$SCOPE" =~ ^[0-9]+$ ]] || { echo "arg2 must be 'smoke' or a number"; exit 1; };; esac

export BENCH_MODE="$MODE"
export BENCH_SCOPE="$SCOPE"

echo "=== ZC702 benchmark: mode=$MODE scope=$SCOPE ==="
source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh
/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb \
  /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/board_benchmark.tcl
