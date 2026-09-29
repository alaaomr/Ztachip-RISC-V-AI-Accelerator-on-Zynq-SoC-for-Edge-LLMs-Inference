# PMU (Performance Monitoring Unit) — build, verify & use notes

Phase-2 on-silicon profiling for ztachip on the ZC702. Added **2026-06-20**.
GHDL elaboration of `soc_base` with these changes: **PASSED (0 errors)**.

## What problem it solves
- The APB TIMER reads 0 in this build (its `prdata` is driven onto a shared tri-state
  `'Z'` bus that doesn't exist in FPGA fabric), and VexRiscv `mcycle` isn't wired to the CSR
  read port. The PMU gives a **working free-running cycle counter** + **DDR-traffic / stall
  counters**, on a **dedicated read path** so it never touches the fragile shared bus.
- Taps the ztachip **DDR data-AXI bus** (weight streaming = the memory-bound bottleneck) and
  the **control-AXI** command issue — all at `soc_base` level, so **no edits inside the
  ztachip core** (protects timing closure).

## ⚠️ PMBus power = NO bitstream change
Power is read OUTSIDE the bitstream: TI **Fusion Digital Power GUI** via a USB-PMBus dongle
(independent of the Zynq), or PS/ARM I2C read of the UCD9248 rails. Do NOT put power logic in
the rebuild. (Optional later: a 1-bit GPIO "inference-active" marker to time-align the
external power log.) The rebuild is **PMU only**.

## Files changed (the complete set)
| File | Change |
|------|--------|
| `HW/src/soc/peripherals/pmu.vhd` | **NEW** — the PMU peripheral (cycle + DDR + stall counters) |
| `HW/src/ztachip_pkg.vhd` | added `apb_pmu_id_c=7` + register-offset constants; added `component PMU` |
| `HW/src/soc/soc_base.vhd` | `pmu_prdata`/`pmu_pready` signals; OR'd `pmu_pready` into `apb_pready`; added `pmu_prdata` to the `apb_prdata` mux; instantiated `PMU_inst` tapping `ZTA_DATA_*` + `ZTA_CONTROL_*` |
| `HW/examples/ZC702/create_project_zc702.tcl` | `read_vhdl .../peripherals/pmu.vhd` |
| `SW/src/soc.h` | `APB_PMU_*` register map + `PmuClear()/PmuLatch()/PmuRd()` |

No bridge change needed — `axi_apb_bridge` already decodes `apb_penable(paddr[19:16])`, so id 7
is selected automatically.

## Register map (APB id 7, base byte 0x70000)
| Byte | Firmware macro | Meaning |
|------|----------------|---------|
| 0x00 | `APB_PMU_CTRL` (W) | bit0=clear live counters, bit1=latch live→shadow |
| 0x04 | `APB_PMU_CYCLES` | free-running cycle counter (the timer fix) |
| 0x08 | `APB_PMU_RDBEAT` | DDR read data beats (bandwidth) |
| 0x0C | `APB_PMU_RDXACT` | DDR read bursts |
| 0x10 | `APB_PMU_WRBEAT` | DDR write data beats |
| 0x14 | `APB_PMU_WRXACT` | DDR write bursts |
| 0x18 | `APB_PMU_RDSTALL` | read starvation cycles (`rready & ¬rvalid`) — memory-bound proof |
| 0x1C | `APB_PMU_ARSTALL` | read-addr stall cycles |
| 0x20 | `APB_PMU_RDACTIVE` | DDR read busy cycles |
| 0x24 | `APB_PMU_CMDXACT` | tensor commands issued |

## STEP 1 — Verify in SIMULATION before the long synth (cheap gate)
Already done once: GHDL elaboration of `soc_base` passes. To re-run the structural check:
```
cd ztachip/tools/ghdl && bash convert.sh      # imports all RTL + elaborates soc_base
```
For a functional sim that exercises the counters, build the sim firmware with a PMU read
(see STEP 3 snippet) and run the existing Vivado xsim flow (`run_sim_build.sh` + tb_main),
then confirm `APB_PMU_CYCLES` reads non-zero and increases.

## STEP 2 — Rebuild the bitstream (~1–2 h, Vivado only, NO board)
⚠️ Do NOT regenerate the project from `create_project_zc702.tcl` — it does NOT recreate the
clk_mmcm IP / jitter constraint (those were separate step13/step16), so a fresh project would
LOSE timing closure. Instead REUSE the existing project. Use the provided script:
```
bash HW/examples/ZC702/run_pmu_bitstream.sh
```
It opens `ztachip_zc702.xpr`, adds `pmu.vhd` (the only new file; edits to soc_base.vhd /
ztachip_pkg.vhd are auto-picked-up), forces re-synth, runs impl + write_bitstream, and prints
the WNS/WHS timing result. CONFIRM it says "TIMING CLOSED" (WNS ≥ 0, WHS ≥ 0). The PMU is
small and on `clk_main`, so it should not disturb timing. Functional sim already PASSED
(`tools/ghdl/tb_pmu.vhd`). Golden restore point: `../phase1_golden_snapshot_2026-06-20/`.
(If `vivado` isn't found, source its `settings64.sh` first — the script tries common paths.)

## STEP 3 — Use it from firmware (rebuild_fw.sh only, no synth)
Read the cycle counter (proves the dead timer is fixed):
```c
unsigned c0 = PmuRd(APB_PMU_CYCLES);
// ... work ...
PmuLatch();                       // coherent snapshot
unsigned c1 = PmuRd(APB_PMU_CYCLES);
printf("cycles=%u\r\n", c1 - c0);
```
Per-kernel profiling pattern (wrap a matmul / attention call in forward()):
```c
PmuClear();                                   // start region
matmul(...);                                  // the kernel under test
PmuLatch();                                   // freeze a coherent snapshot
printf("[PMU] kern=matmul cyc=%u rdbeat=%u rdstall=%u rdact=%u cmd=%u\r\n",
       PmuRd(APB_PMU_CYCLES), PmuRd(APB_PMU_RDBEAT), PmuRd(APB_PMU_RDSTALL),
       PmuRd(APB_PMU_RDACTIVE), PmuRd(APB_PMU_CMDXACT));
```
Interpretation: `rdbeat × bus_bytes / cycles` = DDR read bandwidth; high `rdstall`/`cycles`
ratio = memory-bound confirmation; `rdactive/cycles` = DDR-read duty cycle.

## STEP 4 — Pair with power (external, no bitstream)
Log per-rail Watts via TI Fusion GUI (VCCINT=PL compute, PS rails, DDR rail) during a fixed
prompt; combine with PMU cycles + token count → tokens/sec/Watt and a measured roofline.
```
