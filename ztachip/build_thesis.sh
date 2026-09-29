#!/usr/bin/env bash
# Build THESIS_REPORT.md into .docx and .pdf using only Python (stdlib) + LibreOffice.
# Run:  bash build_thesis.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

SRC="THESIS_REPORT.md"
OUTDIR="build/thesis"
TITLE="Mapping and Execution of the ztachip AI Accelerator on the Xilinx Zynq-7000 (ZC702)"

mkdir -p "$OUTDIR"

echo "==> [1/3] Markdown -> HTML"
python3 tools/md_to_html.py "$SRC" "$OUTDIR/THESIS_REPORT.html" "$TITLE"

PROFILE="$(mktemp -d)"

echo "==> [2/3] HTML -> DOCX (LibreOffice)"
soffice --headless -env:UserInstallation="file://$PROFILE/d" \
        --convert-to "docx:MS Word 2007 XML" --outdir "$OUTDIR" \
        "$OUTDIR/THESIS_REPORT.html" >/dev/null 2>&1

echo "==> [3/3] HTML -> PDF (LibreOffice)"
soffice --headless -env:UserInstallation="file://$PROFILE/p" \
        --convert-to pdf --outdir "$OUTDIR" \
        "$OUTDIR/THESIS_REPORT.html" >/dev/null 2>&1

rm -rf "$PROFILE"

echo
echo "Done. Files in $OUTDIR/:"
ls -lh "$OUTDIR"/THESIS_REPORT.* 2>/dev/null | awk '{print "   "$9"  ("$5")"}'
echo
echo "Open with:   xdg-open $OUTDIR/THESIS_REPORT.pdf"
