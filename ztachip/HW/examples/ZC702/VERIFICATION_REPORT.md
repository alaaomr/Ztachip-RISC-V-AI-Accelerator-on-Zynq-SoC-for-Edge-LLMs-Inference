# ZC702 Port — Pre-Board Verification Report
# By: Claude (verification pass) for Eslam Elsayed
# Date: 2026-05-30
# Scope: Static design review of every modified/created block + review of
#        existing simulation and implementation evidence.
#
# GOAL: Catch problems on the PC BEFORE we ever flash the board.

---

## TL;DR (read this first)

I reviewed every block. The **connectivity (RISC-V <-> ztachip <-> DDR via PS HP0,
PS clocks, stubs) is wired correctly**. BUT I found **3 blockers** that will cause
the board to misbehave if you flash it today. None are hard to fix.

Think of it like a car: the engine and wiring are connected correctly, but
(1) the gearbox ratio is wrong, (2) the speedometer is calibrated for the wrong
speed, and (3) the version of the car sitting in the garage is last week's
broken prototype, not the fixed one.

| # | Blocker | Severity | Fix effort |
|---|---------|----------|-----------|
| B1 | Timing fix breaks the clk_x2 = 2x clk_main rule | CRITICAL | 1 line |
| B2 | main_clock_c still says 125 MHz (clock is now 100) | HIGH | 1 line |
| B3 | The .bit on disk is the STALE failing 125 MHz build | HIGH | rebuild |

---

## BLOCKER B1 — The timing fix breaks the 2x clock relationship (CRITICAL)

**What the RTL demands.** In `HW/src/soc/soc_base.vhd:1338`:
> `-- clk_x2_main has to be exactly double of clk_main with edges aligned.`

ztachip uses this fast clock (`clk_x2_main`) inside **almost every memory in the
chip** — register files, RAMs (`ram2r1w`, `ramw`, `ramw2`), pcore, dp, tcm.
The "memory optimization" in `config.vhd` (min_mem_depth_c=512) stores two words
in one block and reads them out using TWO ticks of the x2 clock per ONE tick of
the main clock. That trick only works if x2 is EXACTLY 2x the main clock.

**What the timing fix does wrong.**
- Original (works):  clk_main = 125, clk_x2 = 250  -> 250 = 2 x 125  CORRECT
- After `run_step5_fix_timing.tcl`: it drops **FCLK0 -> 100** but leaves
  **FCLK1 = 250**. Now 250 is NOT 2 x 100 (it should be 200).

So the fix would let the design build cleanly and even pass timing — then produce
**wrong math results on the real board**, because every dual-pumped memory is now
clocked at the wrong ratio. This is the kind of bug that passes synthesis and
fools you on the bench.

**The fix.** Drop BOTH clocks proportionally:
- FCLK0: 125 -> **100 MHz**
- FCLK1: 250 -> **200 MHz**  (keeps the exact 2x relationship)

This needs to change in TWO places:
- `zynq_ps_bd.tcl` line 59: `PCW_FPGA1_PERIPHERAL_FREQMHZ {250}` -> `{200}`
- `run_step5_fix_timing.tcl`: add a `set_property` for `PCW_FPGA1_PERIPHERAL_FREQMHZ {200}`

(100/200 also relaxes timing more than 100/250, so it helps close WNS too.)

---

## BLOCKER B2 — main_clock_c is still 125 MHz but the clock is now 100 (HIGH)

`HW/src/config.vhd:55`: `constant main_clock_c := 125000000;`

This constant is baked into RTL math in two peripherals:
- `HW/src/soc/peripherals/uart.vhd:49` -> `TICKS_PER_BIT = main_clock_c / BAUD_RATE`
- `HW/src/soc/peripherals/time.vhd:41` -> `clock_divider_c = main_clock_c / 1000`

If the real clock is 100 MHz but the RTL still computes dividers as if it were
125 MHz, then:
- The millisecond timer runs **25% slow** (every "1 ms" is really 1.25 ms).
- The UART baud rate is **25% off** -> the serial console will be **garbled /
  unusable**. UART is stubbed today, but you WILL need it for the chat() demo
  (Level 6) to type prompts and read the model's replies. So this WILL bite you.

**The fix.** When you commit to 100 MHz, set:
`constant main_clock_c := 100000000;`

(If instead you decide to keep 125/250 and close timing another way, leave this
at 125. The rule is simply: **main_clock_c must equal the real FCLK0 frequency.**)

---

## BLOCKER B3 — The bitstream on disk is the stale, FAILING 125 MHz build (HIGH)

I read the actual routed timing report that produced the current `.bit`:
`ztachip_zc702.runs/impl_1/main_zc702_timing_summary_routed.rpt`

- `clk_fpga_0` period = **8.000 ns = 125 MHz** (NOT 100)
- **WNS = -1.445 ns**, "Timing constraints are not met."

But the *source* block design has already been edited to 100 MHz (confirmed in the
`.xci`, `.hwh` and generated HDL). **So the bitstream and the sources disagree.**
The `main_zc702.bit` currently sitting in `impl_1/` is last week's broken 125 MHz
prototype. If you flash it, you flash the failing design.

**The fix.** After applying B1 + B2, re-run implementation to bitstream from
scratch (reset_run impl_1 then launch to write_bitstream), and confirm the new
report shows period = 10 ns and WNS >= 0 before flashing.

---

## RISK R1 — A small HOLD violation that frequency reduction will NOT fix

Same timing report:
- **WHS = -0.008 ns** (hold), 1 failing endpoint, on a `clk_fpga_0 <-> clk_fpga_1`
  crossing.

Important concept for you: lowering the clock frequency only fixes **setup** (WNS)
violations. **Hold** violations (WHS) are independent of frequency — they will
still be there at 100 MHz. It is tiny (8 picoseconds) and will very likely clear
once the design is re-placed/re-routed at the corrected 100/200 ratio, but you
**must check WHS >= 0 in the new report**, not just WNS.

## RISK R2 — Real cross-clock paths exist between the 125 and 250 domains

The report shows timed paths `clk_fpga_0 -> clk_fpga_1` and back. These are fine
*as long as* the two clocks stay phase-aligned at an integer 2:1 ratio (they come
from the same PS PLL, so they are). This is another reason B1 matters: 100/250 is
a 2.5:1 ratio = no longer integer-aligned = these paths get harder and may fail.
100/200 keeps them clean.

---

## What PASSED verification (the good news)

These blocks I checked line-by-line and they are correct:

1. **Top-level wiring `main_zc702.v` <-> `soc_base` entity.** Every port name,
   width, and direction matches the VHDL entity. No dangling/mismatched signals.
2. **AXI HP0 datapath (RISC-V/ztachip DMA -> PS DDR3).**
   - 64-bit `rdata`/`wdata`/`wstrb[7:0]` match `exmem_data_width_c=64`.
   - ARLEN/AWLEN 8-bit -> 4-bit truncation `[3:0]` is SAFE: ztachip max burst = 9,
     AXI3 limit = 16, so the upper 4 bits are always 0. Verified.
   - AXI3 housekeeping tied correctly: `arcache/awcache=0011`, `arid/awid/wid=0`,
     `arlock/arprot/arqos=0`, `bid/rid` ignored. Correct.
3. **`config.vhd exmem_data_width_c=64`** propagates cleanly. `axi_merge_read/write`
   have explicit `IF 64 = exmem_data_width_c` "no-resize" branches, so 64-bit is a
   first-class supported configuration, not a hack.
4. **Block design** (`zynq_ps_bd.tcl`): HP0 = 64-bit AXI3, `PCW_USE_M_AXI_GP0=0`
   (ARM correctly cannot poke ztachip), DDR address segment assigned. Correct.
5. **Peripheral stubs** are tied to safe idle values: APB `PREADY=1`/`PRDATA=0`,
   `UART_RXD=1` (idle high), camera/VGA/pushbutton tied to 0. APB `PENABLE` width
   (16) matches `apb_max_devices_c=16`. Correct.
6. **Synthesis**: 0 black boxes — every module was found, no missing files.

---

## What CANNOT be verified without the board (residual risk to accept)

- Real DDR3 read/write traffic through HP0 at runtime (sim used a model RAM).
- VexRiscv booting from real PS DDR3.
- Real UART console round-trip.
- JTAG/XSCT model preload (Level 5) — not written yet.
These are inherent to "no board on hand" and are expected open items.

---

## Documentation inconsistencies to clean up (not bugs, but confusing)

- `PROJECT_STATUS.md` line ~9 still says "TinyLlama 1.1B" in the goal; the rest of
  the doc correctly says SmolLM2-135M.
- `zynq_ps_bd.tcl` header comment says "FCLK_CLK0 : 125 MHz" but the actual config
  on line 58 is 100. `main_zc702.v` header comments also still say 125.
- `PROJECT_STATUS.md` says "timing fix PENDING / WNS=-1.449" but the source BD was
  already moved to 100 MHz. The status is stale relative to the files.

---

## Recommended order of operations before board upload

1. Decide target frequency: **100/200 MHz** (recommended) or keep 125/250.
2. Apply B1 (FCLK1 -> 200 in both tcl files) and B2 (main_clock_c -> 100e6).
3. Re-run synthesis + implementation to bitstream (clean rebuild).
4. Confirm in the NEW routed report: period = 10 ns, **WNS >= 0 AND WHS >= 0**.
5. Re-run the LLM kernel sim once at the corrected clocks (cheap insurance).
6. Only then flash the board (Level 3).

— end of report —
