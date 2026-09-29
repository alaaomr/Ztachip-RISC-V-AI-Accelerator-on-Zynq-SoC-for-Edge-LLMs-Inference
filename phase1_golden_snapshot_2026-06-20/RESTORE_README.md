# Phase-1 GOLDEN snapshot — 2026-06-20 (pre-Phase-2 restore point)

Frozen copy of the **working** SmolLM2-135M-on-ZC702 state, taken **before** Phase-2 begins
(PMU bitstream rebuild + reset-vector/clock/firmware changes). If Phase-2 breaks something,
restore from here. Working baseline: **~4.5 tok/s, ~222 ms/token**, VexRiscv @ 93.75 MHz.

Related: git tag `phase1-llm-working-2026-06-17`, the older `../backups/` folder, and
`../ztachip/CHECKPOINT.md` / `PROJECT_WALKTHROUGH.md`.

---

## Contents

```
bitstream/
  main_zc702_GOLDEN.bit              ← THE working, timing-clean bitstream (WNS 0 / WHS +0.009)
  main_zc702_mmcm_hold10ps.bit.bak   ← intermediate: MMCM added, before jitter fix (hold -10ps)
  main_zc702_setupOK_holdfail.bit.bak← intermediate: setup OK but hold failing (pre-MMCM)
firmware/
  main.bin     ← main firmware image  → loads to DDR  @ 0x00100000
  vector.bin   ← boot vector stub     → loads to OCM  @ 0x00004000
  ztachip.elf  ← full ELF (reference / re-split source; not loaded directly)
scripts/        ← all board + build scripts as of this snapshot (board_*, run_*, rebuild_fw.sh, ...)
rtl_config/     ← PRISTINE copies of the files Phase-2 is most likely to EDIT:
  config.vhd            (main_clock_c = 93750000)
  ztachip_pkg.vhd       (ddr_vector_depth_c / bus width)
  main_zc702.v          (top: PS7 + MMCM + soc_base wiring)
  main_zc702.xdc        (ZC702 pinout + jitter constraint)
  riscv_xilinx_jtag.scala (VexRiscv config incl. resetVector)
  linker.ld             (memory map / heap / vector split)
SHA256SUMS.txt  ← integrity hashes for every file above
```

## NOT included here (large / static — documented instead)
- **Model** `ztachip/models/SMOLLM2.ZUF` (141 MB) — UNCHANGED by Phase-2, still on disk.
  - sha256: `55a39e1cfada7c8977467064bb09b0c15ed612a76d4c9f15b5a074c21a691bf6`
  - If ever lost: regenerate from `models/SmolLM2-135M-Instruct-f16.gguf` via `SW/apps/llm/gguf/quant`.
- Full source tree — in git (tag above) and `../backups/ztachip_phase1_source_2026-06-17.tar.gz`.
- 2 GB Vivado project — regenerate via `scripts/create_project_zc702.tcl`.

## Verify integrity (any time)
```
cd phase1_golden_snapshot_2026-06-20
sha256sum -c SHA256SUMS.txt
```
Key hashes: GOLDEN.bit `410ec014…b940c`, main.bin `4af80a44…bbedc`, vector.bin `001ac5a8…ca1f`.
(GOLDEN.bit is byte-identical to `../backups/main_zc702.bit`.)

---

## How to RESTORE this working state (after a Phase-2 experiment)

**A. Just the firmware (board still powered, model still in DDR):**
1. `cp firmware/main.bin firmware/vector.bin  ../ztachip/SW/build/`
2. `bash ../ztachip/HW/examples/ZC702/run_resume_fw.sh`

**B. Full board day (board was off / DDR wiped):**
1. `cp firmware/main.bin firmware/vector.bin  ../ztachip/SW/build/`
2. ensure `ztachip/models/SMOLLM2.ZUF` is present (hash above)
3. `bash ../ztachip/HW/examples/ZC702/run_board_day.sh`   (~40 min, reloads model)

**C. Restore the golden BITSTREAM (if a Phase-2 rebuild went bad):**
- copy `bitstream/main_zc702_GOLDEN.bit` back over
  `ztachip/HW/examples/ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit`
  (or point the board script's program_hw step at the GOLDEN file directly).

**D. Restore a pristine RTL/config file (if a Phase-2 edit must be reverted):**
- copy the relevant file from `rtl_config/` back to its original location, e.g.
  `cp rtl_config/linker.ld ../ztachip/SW/linker.ld`
  `cp rtl_config/config.vhd ../ztachip/HW/src/config.vhd`
  `cp rtl_config/riscv_xilinx_jtag.scala ../ztachip/HW/riscv/xilinx_jtag/riscv.scala`

---

## Phase-2 change log (fill in as you go)
| Date | File changed | What | Bitstream rebuilt? | Result |
|------|--------------|------|--------------------|--------|
| 2026-06-20 | +pmu.vhd, ztachip_pkg.vhd, soc_base.vhd, create_project_zc702.tcl, soc.h | Added PMU perf-counter peripheral (APB id 7), final = 4 core counters (CYCLES/RD_BEATS/RD_STALL/RD_ACTIVE) | YES, built | ✅ TIMING CLOSED WNS 0.000 / WHS +0.027 @93.75MHz. Bitstream: bitstream/main_zc702_PMU.bit (sha256 85813b6f). Sim + GHDL verified. |
| | | | | |
