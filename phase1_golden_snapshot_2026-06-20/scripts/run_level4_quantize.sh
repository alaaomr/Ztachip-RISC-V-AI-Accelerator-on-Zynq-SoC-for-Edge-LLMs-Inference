#!/bin/bash
# =============================================================================
# run_level4_quantize.sh  — Level 4: Download SmolLM2-135M (F32 GGUF) and
#                           convert it to SMOLLM2.ZUF for ztachip.
#
# Run from a terminal (NOT Vivado):
#   bash ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_level4_quantize.sh
#
# What this does:
#   1. Downloads SmolLM2-135M-Instruct F32 GGUF from HuggingFace (~540 MB)
#   2. Runs the ztachip 'quant' tool to convert GGUF → SMOLLM2.ZUF
#      (INT4 quantization, optimized for ztachip hardware)
#   3. Copies SMOLLM2.ZUF to SW/build/ ready for the board
#
# IMPORTANT: The quant tool only accepts F32 GGUF as input.
#            Do NOT use F16 or pre-quantized (Q4_K_M etc.) GGUFs — they crash.
# =============================================================================

set -e  # stop on first error

ZTACHIP=~/Desktop/AIDAChip_Workshop_01/ztachip
QUANT=$ZTACHIP/SW/build/quant
MODEL_DIR=$ZTACHIP/SW/build/models
GGUF_FILE=$MODEL_DIR/SmolLM2-135M-Instruct-f16.gguf
ZUF_FILE=$MODEL_DIR/SMOLLM2.ZUF

echo "============================================================"
echo " Level 4: SmolLM2-135M Quantization"
echo "============================================================"

# ---- Step 1: Build quant tool (always rebuild: gguf.cpp was patched) ------
echo "Building quant tool (gguf.cpp patched to accept F16 input)..."
cd $ZTACHIP/SW
make -f makefile.quant
cd - > /dev/null
echo "OK: quant tool built at $QUANT"

# ---- Step 2: Create model directory ----------------------------------------
mkdir -p $MODEL_DIR

# ---- Step 3: Download F32 GGUF if not already present ----------------------
if [ -f "$GGUF_FILE" ]; then
    echo "OK: GGUF file already exists, skipping download."
    ls -lh "$GGUF_FILE"
else
    echo ""
    echo "Downloading SmolLM2-135M-Instruct F16 GGUF (~270 MB)..."
    echo "This will take a few minutes depending on your internet speed."
    echo ""
    wget -c \
        "https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-f16.gguf" \
        -O "$GGUF_FILE"
    echo "Download complete."
fi

# ---- Step 4: Run quantization -----------------------------------------------
echo ""
echo "Converting GGUF → SMOLLM2.ZUF (INT4, for ztachip hardware)..."
echo "This takes about 1-2 minutes..."
$QUANT ZTA Q4 "$GGUF_FILE" "$ZUF_FILE"

# ---- Step 5: Show result ----------------------------------------------------
echo ""
echo "============================================================"
echo " DONE!"
echo "============================================================"
ls -lh "$ZUF_FILE"
echo ""
echo "ZUF file is at: $ZUF_FILE"
echo ""
echo "Next step (Level 5): Load SMOLLM2.ZUF onto the ZC702 board"
echo "using JTAG/XSCT instead of Ethernet TFTP."
echo "============================================================"
