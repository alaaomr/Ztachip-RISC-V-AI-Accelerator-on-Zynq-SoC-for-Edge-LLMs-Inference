#!/usr/bin/env bash
# =============================================================================
# run_three_models.sh — benchmark THREE models on ZC702 back-to-back, unattended.
#
#   1. SmolLM2-135M  Q4   (repo default)   -- bring up board + load model + run
#   2. SmolLM2-135M  Q8                     -- swap model (keep bitstream+fw) + run
#   3. SmolLM2-360M  Q4                     -- swap model + run
#
# Each model runs the SAME 30 prompts (1 repeat) so the three are directly
# comparable.  Together they give a tok/s-vs-bytes/token line that demonstrates
# the design is memory-bandwidth-bound (Q4<Q8<360M in bytes -> tps drops).
#
# Board must be POWERED ON (step 1 uses mode=full to bring it up from cold).
# The model in DDR survives between steps (PS owns DDR), so steps 2-3 only
# reload the model (~minutes), not the firmware/bitstream.
#
# Usage:
#   bash run_three_models.sh          # 30 prompts x 1 repeat per model (default)
#   bash run_three_models.sh smoke    # 1 prompt per model (validate the flow fast)
#   bash run_three_models.sh 3        # 3 repeats x 30 prompts per model
#
# If a step fails, you can re-run just that model, e.g.:
#   BENCH_MODE=swap BENCH_SCOPE=1 BENCH_ZUF=$M/SMOLLM2_Q8.ZUF \
#     BENCH_MODELNAME=SmolLM2-135M-Instruct-Q8ZUF BENCH_TAG=smollm135_q8 \
#     $XSDB board_benchmark.tcl
# =============================================================================
set -e
SCOPE="${1:-1}"

ROOT=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
ZC="$ROOT/HW/examples/ZC702"
M="$ROOT/models"
TCL="$ZC/board_benchmark.tcl"
XSDB=/home/eslam-elshokafy/Xilinx/2025.2/Vivado/bin/xsdb

echo "=== sanity: all three model files present ==="
for f in "$M/SMOLLM2_Q4.ZUF" "$M/SMOLLM2_Q8.ZUF" "$M/SMOLLM2_360M_Q4.ZUF"; do
  [ -f "$f" ] || { echo "MISSING: $f  (run prep_models.sh + make_q4_zuf for 360M)"; exit 1; }
  printf "  %-28s %s bytes\n" "$(basename "$f")" "$(stat -c %s "$f")"
done

source /home/eslam-elshokafy/Xilinx/2025.2/Vivado/settings64.sh

run_one () {
  local mode="$1" zuf="$2" name="$3" tag="$4"
  echo ""
  echo "##############################################################"
  echo "#  MODEL: $name"
  echo "#  mode=$mode  scope=$SCOPE  tag=$tag"
  echo "##############################################################"
  BENCH_MODE="$mode" BENCH_SCOPE="$SCOPE" \
  BENCH_ZUF="$zuf" BENCH_MODELNAME="$name" BENCH_TAG="$tag" \
    "$XSDB" "$TCL"
}

# 1) Q4 — full bring-up (powers DDR, programs bitstream, loads firmware + model)
run_one full "$M/SMOLLM2_Q4.ZUF"      "SmolLM2-135M-Instruct-Q4ZUF"  "smollm135_q4"

# 2) Q8 — swap model only (bitstream + firmware stay resident in DDR)
run_one swap "$M/SMOLLM2_Q8.ZUF"      "SmolLM2-135M-Instruct-Q8ZUF"  "smollm135_q8"

# 3) 360M Q4 — swap model only
run_one swap "$M/SMOLLM2_360M_Q4.ZUF" "SmolLM2-360M-Instruct-Q4ZUF"  "smollm360_q4"

echo ""
echo "=== ALL THREE MODELS DONE.  Summarize with: ==="
echo "    python3 $ZC/bench/summarize.py"
