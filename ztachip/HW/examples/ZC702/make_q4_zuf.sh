#!/usr/bin/env bash
# Reproduce the ORIGINAL ztachip repo's model build: quant ZTA Q4 <gguf> <zuf>
# (README.md line 184). Output is INT4 ZUF, the author's documented default.
#
# Repo uses an FP32 GGUF as input; we use the F16 GGUF we already have. The Q4
# quantizer dequantizes to float then re-quantizes to 4-bit per-group, so F16 vs
# F32 source is numerically irrelevant to the INT4 result.
set -e
ROOT=/home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
QUANT="$ROOT/SW/apps/llm/gguf/quant"
GGUF="$ROOT/models/SmolLM2-135M-Instruct-f16.gguf"
OUT="$ROOT/models/SMOLLM2_Q4.ZUF"

echo "=== Quantizing SmolLM2-135M-Instruct -> Q4 ZUF (repo default) ==="
ls -lh "$GGUF"
"$QUANT" ZTA Q4 "$GGUF" "$OUT"
echo "=== done ==="
ls -lh "$OUT"
echo -n "Q4 ZUF size (bytes): "; stat -c %s "$OUT"
echo -n "Q8 ZUF size (bytes): "; stat -c %s "$ROOT/models/SMOLLM2.ZUF"
