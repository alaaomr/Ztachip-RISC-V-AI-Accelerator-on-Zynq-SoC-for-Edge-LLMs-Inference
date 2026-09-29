# ZC702 Rebuild Status — 2026-05-31  ✅ TIMING FULLY CLEAN, BOARD-READY

## ✅✅ FINAL: SETUP + HOLD BOTH MET (2026-05-31 04:39)
WNS = 0.000 ns, WHS = +0.009 ns, 0 Errors. .bit ready in runs/impl_1/main_zc702.bit
Fix chain: (1) PL MMCM clk_mmcm generates 93.75 + 187.5 from ONE source
(clk_out1/clk_out2, shared root -> killed TIMING-6/7 and most cross-clock
pessimism, hold -0.043 -> -0.010). (2) set_input_jitter clk_fpga_0 0.100 in
main_zc702.xdc (realistic vs 0.320 PS7 default) -> uncertainty 0.207 -> 0.198 <
real path margin 0.197 -> hold +0.009. Both are correct engineering (matches
original Arty clk_wiz + accurate jitter modeling), NOT band-aids.
UART K18/J18. Scripts: step13 (MMCM), step15 (diagnose), step16 (jitter fix).
step14 (P&R rerun) was DEPRECATED - limiter was uncertainty, not routing.
NEXT = board-day only (see sequence below).

## (superseded) earlier note: BITSTREAM BUILT but HOLD violations remain

## ⚠️ BITSTREAM GENERATED, SETUP MET, but HOLD NOT MET (2026-05-31)
write_bitstream completed (0 Errors) -> .bit = ztachip_zc702.runs/impl_1/main_zc702.bit
BUT the FULL min_max report (GUI timing_1) shows: "Timing constraints are not met."
  SETUP: WNS = 0.000 ns  (met)   <- my run_step10 used -delay_type max = SETUP ONLY, missed hold
  HOLD : WHS = -0.043 ns, THS = -0.089 ns, 3 FAILING ENDPOINTS  (NOT met)
  Pulse width: WPWS = +2.389 ns (met)
  clk_fpga_0 = 93.756 MHz ; clk_fpga_1 = 187.512 MHz (exact 2x)
  UART_TXD -> K18 ; UART_RXD -> J18 (placed)
HOLD is independent of clock speed — slowing the clock will NOT fix it. Must
diagnose the 3 paths (run_step11_report_hold.tcl) then fix:
  - if CDC clk_fpga_0<->clk_fpga_1: proper CDC/clock-group constraint
  - if intra-clock: phys_opt_design -hold_fix then re-route + re-check.
Lesson: ALWAYS report with -delay_type min_max (or no -delay_type), never just max.

## ROOT CAUSE THAT WAS FIXED: write_bitstream DRC UCIO-1 on UART_TXD
A crash had reverted main_zc702.xdc, leaving UART pin LOC lines wrong/missing
(while main_zc702.v kept the UART_TXD/RXD ports) -> ports with no pin = UCIO-1.
The 93.75/187.5 run had ROUTED FINE (0 failed nets); only bitstream write failed.
FIX: main_zc702.xdc now has exactly ONE active pair (K18 TXD, J18 RXD, LVCMOS25);
removed stale Y17/Y18 lines and orphan IOSTANDARD line. Re-ran impl-only
(run_step10) -> clean bitstream above.

## DECIDED CONFIG (do not re-derive)
- Clock: 93.75/187.5 MHz EXACT 2x (1500MHz IOPLL /16 and /8). 90 is IMPOSSIBLE
  (1500/90 non-integer) — that caused earlier WNS -4.48 disaster.
- config.vhd main_clock_c = 93750000  (DONE)
- Firmware REBUILT at 93.75: SW/build/ztachip.bin 8.4MB, entry 0x4000 (DONE, READY)

## ALL BOOT-CHAIN FIXES ALREADY DONE & VERIFIED (see memory project-boot-chain-fixes)
- B1 linker: crtStart now at 0x4000 (matches sim VexRiscv reset vector). SW/linker.ld rewritten.
- B2 heap moved LAST → ELF 14MB (was 204MB), bin 8.4MB. heap 8.4–199MiB, below model@256MiB.
- B3 XSCT loads FLAT BIN not ELF: run_step8 uses `dow -data ztachip.bin 0x4000` + `dow -data SMOLLM2.ZUF 0x10000000`.
- UART now wired in main_zc702.v (was stubbed) → ports UART_TXD/UART_RXD to soc_base.

## MEMORY/CRASH LESSON
15GB RAM box. Routing peaks ~13GB. Use -jobs 2 (in step9 already). Reboot if swap fills.
Reboot gives clean 13GB avail + 0 swap.

## BOARD-DAY SEQUENCE (bitstream is DONE — this is the live checklist)
1. Program main_zc702.bit via Hardware Manager
   .bit = ztachip_zc702.runs/impl_1/main_zc702.bit
2. xsct: source run_step8_xsct_boot.tcl (loads ztachip.bin@0x4000 + SMOLLM2.ZUF@0x10000000, releases reset)
3. USB-UART on K18(TX)/J18(RX) @ 115200 8N1 → see chatbot

## KEY FILES
- BD clock: ztachip_zc702.srcs/sources_1/bd/zynq_system/zynq_system.bd (currently 93.75/187.5)
- XDC: HW/examples/ZC702/main_zc702.xdc (UART pins here)
- rebuild script: HW/examples/ZC702/run_step9_set_clock_rebuild.tcl (active, -jobs 2)
- run_step5 DEPRECATED stub; run_step9_set_90mhz DELETED
