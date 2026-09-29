#!/usr/bin/env bash
# Fresh, verified preparation of the SmolLM2 ZUF models for the board benchmark.
#   1. re-download SmolLM2-135M-Instruct F16 GGUF from HuggingFace
#   2. build SMOLLM2_Q4.ZUF  (repo default, INT4)
#   3. build SMOLLM2_Q8.ZUF  (INT8)
#   4. sanity-check: fresh Q4 must equal the model currently in models/SMOLLM2.ZUF
set -e
ROOT=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
M="$ROOT/models"
Q="$ROOT/SW/apps/llm/gguf/quant"
URL="https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-f16.gguf"
GGUF="$M/SmolLM2-135M-Instruct-f16.gguf"

echo "===================================================================="
echo " STEP 1/4  Re-download SmolLM2-135M-Instruct F16 GGUF (fresh copy)"
echo "===================================================================="
wget -q --show-progress -O "$GGUF.new" "$URL"
mv "$GGUF.new" "$GGUF"
echo -n "downloaded size (bytes): "; stat -c %s "$GGUF"
echo -n "sha256: "; sha256sum "$GGUF" | cut -d' ' -f1

echo "===================================================================="
echo " STEP 2/4  Build Q4 ZUF (repo default)"
echo "===================================================================="
"$Q" ZTA Q4 "$GGUF" "$M/SMOLLM2_Q4.ZUF"
echo -n "Q4 size: "; stat -c %s "$M/SMOLLM2_Q4.ZUF"

echo "===================================================================="
echo " STEP 3/4  Build Q8 ZUF"
echo "===================================================================="
"$Q" ZTA Q8 "$GGUF" "$M/SMOLLM2_Q8.ZUF"
echo -n "Q8 size: "; stat -c %s "$M/SMOLLM2_Q8.ZUF"

echo "===================================================================="
echo " STEP 4/4  Sanity check: fresh Q4 == model currently on chip?"
echo "===================================================================="
if cmp -s "$M/SMOLLM2_Q4.ZUF" "$M/SMOLLM2.ZUF"; then
  echo "PASS: fresh Q4 is byte-identical to models/SMOLLM2.ZUF (the model in DDR now)."
else
  echo "NOTE: fresh Q4 differs from models/SMOLLM2.ZUF (will overwrite for the Q4 run)."
fi
echo ""
echo "Prepared files:"
ls -lh "$M/SMOLLM2_Q4.ZUF" "$M/SMOLLM2_Q8.ZUF" "$M/SMOLLM2.ZUF"
echo "DONE."
