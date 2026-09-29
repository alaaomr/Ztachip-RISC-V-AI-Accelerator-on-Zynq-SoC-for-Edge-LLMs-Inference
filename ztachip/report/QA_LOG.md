# 📒 Q&A LOG — Thesis Study Sessions

> **Marker file.** Every question you ask me during study + my full answer gets recorded here,
> in Q&A form with all details, so you can revise before the defense.
> Newest entries are appended at the bottom.

---

## Q1 — 2026-06-24 — Explain the ZYNQ7 Processing System block ("Architectural Pivot" slide)

**Image:** Vivado IP Integrator view of `processing_system7_0` (the ZYNQ7 Processing System IP),
with three red highlight boxes (`S_AXI_HP0` on the left, `DDR` top-right, the `FCLK` group
bottom-right) and a green box around `FCLK_CLK0` + `FCLK_CLK1`.

### Big picture — what this block *is*
This single block is the **PS (Processing System)** — the hard ARM half of the Zynq-7000 chip.
Everything our custom logic (ztachip + VexRiscv) needs from the silicon comes out of this block:
**the DDR memory interface and the clocks.** The PL (programmable logic / FPGA fabric) talks to
it through the ports on its edges. In Vivado, this IP is the *software-configured face* of the
fixed ARM subsystem.

> The slide title "Architectural Pivot" = we moved the design **from the Arty A7** (soft MIG DDR
> controller + Clock Wizard, all built in the fabric) **to the ZC702**, where the **PS gives us
> DDR and clocks for free** as hard silicon. This block is the heart of that pivot.

### LEFT side — ports the PL drives *into* the PS (slave / input ports)
| Port | Meaning |
|---|---|
| **`S_AXI_HP0`** (red box) | **High-Performance AXI slave port.** 64-bit. The **PL is the master**, the PS is the slave. This is the **road from ztachip/VexRiscv to DDR** — it routes through the PS's *PL-to-Memory interconnect* straight into the DDR controller (bypasses the ARM cache, non-coherent = fast). `exmem_data_width_c = 64` in the RTL matches this. |
| `S_AXI_HP0_FIFO_CTRL` | Optional sideband signals reporting the HP port's internal FIFO fill level. We don't need it. |
| `S_AXI_HP0` (the `+`) | The `+` is a **collapsed interface bundle** — click to expand and you see the 5 AXI channels (AR, R, AW, W, B). |
| **`S_AXI_HP0_ACLK`** | **The clock for the HP0 port.** Critical: whatever clock you wire here defines the clock domain of the AXI transfers. **We feed it our `clk_main` (93.75 MHz)**, so AXI runs synchronous to ztachip. The PS then handles the crossing to the DDR's own clock *internally*. |

The little **arrow/pentagon shapes** are interface *pins*. The arrow direction shows the
**master→slave (initiator) relationship — NOT the data direction.** Read data still comes *back*
out of the PS to the PL on the R channel even though the arrow "points in."

### RIGHT side — ports the PS drives *out* to the PL / outside world (output ports)
| Port | Meaning |
|---|---|
| **`DDR`** (red box) | The **external DDR3 memory interface** — these wires leave the chip and go to the physical DDR chips on the ZC702 board. The multi-line bundle = address/data/control/strobe. This is *hard silicon*: the DDR controller + PHY live in the PS. |
| `FIXED_IO` | The fixed-function I/O: **MIO pins, JTAG, boot mode, clock/reset** — the dedicated PS pins that can't be re-assigned. |
| `USBIND_0` | USB PHY interface — unused by us. |
| `TTC0_WAVE0/1/2_OUT` | Outputs of **Triple Timer Counter 0** — unused by us. |
| **`FCLK_CLK0..3`** (red box) | The **four fabric clocks** the PS generates from its PLLs and hands to the PL. These are our clock supply. |
| **`FCLK_CLK0` + `FCLK_CLK1`** (green box) | **The two we actually use.** `FCLK_CLK0 → clk_main (93.75 MHz)`, `FCLK_CLK1 → clk_x2 (187.5 MHz)`. (In the real design `FCLK0` feeds an **MMCM** that regenerates the exact 2:1 pair — see the hold-timing slides.) `FCLK2/FCLK3` are left unused. |
| **`FCLK_RESET0_N`** | **Fabric reset** from PS to PL, **active-low** (the `_N`, shown by the bubble `○`). Releases the PL logic out of reset after the PS boots. |

### The green annotation on the slide — *why FCLK1 must be exactly 2×*
> "ztachip requires the dataplane double-rate clock **clk_x2 to be exactly twice** the main clock
> frequency, because parts of the dataplane emit **two words per main-clock cycle**."

This is the whole reason the clocking matters: the ztachip dataplane is built to push **two data
words every `clk_main` tick**, so it needs a clock running at **double rate, phase-locked** to the
main clock. "Exactly 2×, phase-aligned" is *not optional* — if the ratio drifts or the edges aren't
aligned, the double-rate handoff corrupts data. That requirement is exactly what forced the
**single-MMCM-root fix** (so the 2:1 is exact and the edges line up → hold met, WHS +0.009).

### How it all connects (the data + clock loop)
```
        ┌─────────────── PS (this block) ───────────────┐
 PL ───►│ S_AXI_HP0 ─► PL-to-Mem interconnect ─► DDR ctrl│─► DDR chips
(ztachip│                                               │
 +Vex)  │ FCLK_CLK0 ─┐                                   │
   ▲    │ FCLK_CLK1 ─┴─► (to PL)                          │
   │    └───────────────────────────────────────────────┘
   │           ▲                    │
   └─ clk_main, clk_x2 ◄── MMCM ◄── FCLK0   (clocks feed the PL, incl. S_AXI_HP0_ACLK)
```
- **Clocks flow PS → PL:** `FCLK0` → MMCM → `clk_main` + `clk_x2` → drive ztachip, VexRiscv, *and*
  loop back to `S_AXI_HP0_ACLK`.
- **Data flows PL ⇄ DDR:** ztachip masters `S_AXI_HP0` to read/write model weights & activations in
  DDR; the PS interconnect + DDR controller do the actual memory access and clock-domain crossing.

### The one-sentence defense answer
> "The ZYNQ7 PS block is the hard ARM subsystem; in our pivot to the ZC702 it supplies the **DDR
> interface** (via `S_AXI_HP0`, PL-mastered, 64-bit, non-coherent) and the **fabric clocks**
> (`FCLK0/1` → MMCM → exact 2:1 `clk_main`/`clk_x2`), which is everything ztachip needs from the
> silicon — so we deleted the soft MIG and Clock Wizard we had on the Arty."

---

## Q2 — 2026-06-24 — What is the "dataplane"?

**Dataplane** = the part of a hardware accelerator that does the **actual data crunching** — the
wide parallel compute fabric that streams tensors through and multiplies/accumulates them. It is the
opposite of the **control plane**, which only *decides what to do* and *issues commands*.

### In ztachip specifically
| | **Control plane** | **Dataplane** |
|---|---|---|
| Who | VexRiscv CPU (+ small control logic) | the wide array of compute cores (PCOREs / vector MAC units) |
| Job | fetch instructions, set up tensor ops, move pointers, sequence the work | the heavy lifting: matrix-multiply, convolution, the math of every LLM layer |
| Style | scalar, one-thing-at-a-time | massively parallel, streaming many elements per cycle |
| Analogy | the **manager** giving orders | the **factory floor** doing the work |

When the LLM runs a layer (e.g. `matmul_q4` for SmolLM2), the **control plane sets it up** and the
**dataplane streams weights × activations** through its multiplier array to produce the results.

### Why it ties to the clock story
The ztachip **dataplane** is built to push **two data words every `clk_main` cycle**
(double throughput), so it needs a **double-rate** clock → `clk_x2 = 187.5 MHz`. That requirement:
- forced `clk_x2` to be **exactly 2×** and phase-locked,
- which forced the **single-MMCM-root** fix,
- which is why the **hold timing** mattered (final WHS +0.009).

> One-line: **the dataplane is ztachip's compute engine — the part that actually does the LLM's
> matrix math — and its double-rate design is the reason the whole clocking / hold-timing chapter
> exists.**

---

## Q3 — 2026-06-24 — Brief of the essential blocks in the Zynq PS internal block diagram

**Image:** Vivado "Zynq Block Design" configuration view (full PS internals), with two red boxes on
the bottom edge: **`32b GP AXI Slave Ports`** and **`High Performance AXI 32b/64b Slave Ports`**.

### APU — Application Processor Unit (the ARM brain)
- **2× ARM Cortex-A9 CPU** — the hard processors. In our design they are **idle/passive** (just boot
  and preload the model over JTAG).
- **Snoop Control Unit (SCU)** + **512 KB L2 Cache** — cache coherency; sit on the CPU→memory path.
- **GIC** — Generic Interrupt Controller.
- **OCM Interconnect + 256 KB SRAM** — on-chip SRAM; we use a slice for the **boot vector stub @0x4000**.

### Interconnect (AXI traffic router)
- **Central Interconnect** — main switch between masters (CPU, DMA, PL) and slaves (peripherals, OCM, DDR).
- **Programmable Logic to Memory Interconnect** — dedicated fast path **PL → DDR**, bypassing CPU/cache. **Our road.**

### Memory Interfaces
- **DDR2/3, LPDDR2 Controller** — hard DDR controller + PHY → external DDR chips. **Model + activations live here.**

### PS ↔ PL AXI ports (bottom edge — the bridges)
| Port | Direction | Our use |
|---|---|---|
| 32b GP AXI **Master** Ports | PS → PL | minor |
| **32b GP AXI Slave Ports** (red) | PL → PS | PL → PS peripherals/registers, 32-bit, slow |
| **High-Performance AXI 32b/64b Slave Ports** (red) | PL → PS | **★ `S_AXI_HP0` — 64-bit PL→DDR highway** |
| 64b AXI **ACP** Slave (top-right) | PL → PS, coherent | via SCU/L2 — unused (non-coherent HP is faster) |

### Support blocks
- **Clock Generation** — PLLs producing **FCLK_CLK0..3** (→ MMCM → clk_main/clk_x2).
- **Resets** — generates `FCLK_RESET0_N`.
- **I/O Peripherals + I/O MUX (MIO)** — UART/USB/ENET/SD/SPI/I2C/GPIO to pins (Bank0 MIO[15:0],
  Bank1 MIO[53:16]). UART/ENET exist but console I/O goes via the **DDR mailbox over JTAG** instead.
- **DMA8 / DAP / DEVC / CoreSight / XADC / AES-SHA** — DMA, debug, device config, trace, analog, crypto — **unused**.

### The 3 blocks that ARE our design
1. **High-Performance AXI Slave (red)** = `S_AXI_HP0` — PL→DDR data.
2. **PL-to-Memory Interconnect → DDR Controller** — completes the path to memory.
3. **Clock Generation → FCLK** — supplies the clocks.

> **One-liner:** Of this whole PS, our design only needs the **HP AXI slave port → PL-to-Memory
> interconnect → DDR controller** (data) and the **Clock Generation → FCLKs** (clocks). The two ARM
> CPUs, the cache, and all peripherals sit idle.

---

## Q4 — 2026-06-24 — Brief of the essential blocks in the official Xilinx Zynq-7000 diagram

**Image:** Official Xilinx Zynq-7000 architecture diagram (teal top = PS, yellow bottom = PL),
red boxes around **Multiport DRAM Controller (DDR3/DDR3L/DDR2)** and **High-Performance AXI Ports**.

### MPCore — ARM compute core (center)
- **2× ARM Cortex-A9** with **NEON SIMD + FPU** — hard CPUs (**idle** in our design).
- **Snoop Control Unit** — coherency between the two cores.
- **512 KB L2 Cache** + **256 KB On-Chip Memory (OCM)** — OCM holds our **boot vector stub**.
- **GIC, JTAG & Trace, Configuration, Timers, DMA** — interrupts, debug, boot config, timers, DMA.

### Memory (red)
- **Multiport DRAM Controller (DDR3/DDR3L/DDR2)** — hard controller + PHY → external DDR. "Multiport"
  = multiple masters (CPU, PL, DMA) share it via arbitrated ports. **Our model lives here.**

### Interconnect
- **AMBA® Interconnect** (teal bars) — AXI switching fabric (AMBA = bus family, AXI = protocol).

### Other PS storage / IO
- **Flash Controller (NOR/NAND/SRAM/Quad SPI)** — external boot/code flash.
- **I/O peripherals (left):** 2× SPI, I2C, CAN, UART, GPIO, SDIO, USB, GigE → **Processor I/O Mux** →
  pins (+ **EMIO** to PL). UART/GigE present but console goes via DDR mailbox over JTAG.

### PS ↔ PL bridges
| Port | Our use |
|---|---|
| General-Purpose AXI Ports | 32-bit, low speed — minor |
| ACP (coherent, via SCU/L2) | unused |
| **High-Performance AXI Ports** (red) | **★ `S_AXI_HP0` — 64-bit PL→DDR highway** |
| Security AES/SHA/RSA | unused |

### Programmable Logic (yellow)
- **System Gates, DSP, RAM** — fabric where **ztachip + VexRiscv** are built.
- **XADC, PCIe Gen2, Serial Transceivers, Multi-Standard I/Os** — unused.

### Our path on this diagram
```
ztachip (PL) ─► High-Performance AXI Ports (red) ─► AMBA Interconnect
            ─► Multiport DRAM Controller (red) ─► DDR chips
Clocks: PS clock-gen ─► FCLK ─► MMCM ─► clk_main / clk_x2 ─► ztachip
```

> **One-liner:** Same story as the Vivado view — we use only the **High-Performance AXI port → AMBA
> interconnect → Multiport DRAM controller** for data, plus PS clocks; the dual Cortex-A9 MPCore and
> every peripheral sit idle.

---

## Q5 — 2026-06-24 — Explain every detail of Figure 4.5 (Phase-3 partitioning), incl. `xsdb`

**Image:** Our own Figure 4.5 — Host PC | PS (passive) | PL (active).

### Host PC — `xsdb` over USB-JTAG
- **Host PC** = laptop; not part of the running system, only does **bring-up** then steps away.
- **`xsdb`** = **Xilinx System Debugger** (CLI TCL). On our 2025.2 box there is no `xsct`; `xsdb` *is*
  the tool (same TCL), at `Vivado/bin/xsdb`.
- At bring-up `xsdb`: connect → run `ps7_init` → program bitstream → **preload model into DDR** →
  download firmware (`vector.bin`@0x4000 + `main.bin`@0x100000) → set PC + resume → **read mailbox
  @0x30000000**.
- **`USB-JTAG`** = physical debug cable PC→ZC702; **JTAG** = debug protocol giving `xsdb` access to
  memory + CPU control. The `JTAG` arrow = the one-time host involvement.

### PS (Processing System) — *passive* (resources, no compute)
- **`ps7_init` — clocks, DDR, MIO** — Vivado-generated PS init routine: programs **PLLs** (clocks),
  **calibrates DDR controller/PHY**, sets **MIO pin mux**. `xsdb` runs it FIRST; without it DDR +
  clocks are dead.
- **`FCLK 93.75 MHz`** — fabric clock from the PS PLL = the **single clock root**.
- **`DDR Controller — 1 GB, 64-bit`** — hard controller + 1 GB DDR; 64-bit matches
  `exmem_data_width_c=64`. **Model weights + activations live here.**

### PL (Programmable Logic) — *active* (all computation)
- **`MMCM — 93.75 & 187.5 MHz`** — takes the ONE FCLK root, regenerates both clocks phase-locked,
  exact 2:1 → the **hold-timing fix**.
- **`VexRiscv — rv32im control CPU`** — soft control CPU. `rv32im` = RISC-V 32-bit, **I** = base
  integer, **M** = mul/div (no FP → that's why ztachip has its own FPU). Role = **control plane**
  (sets up ops, mailbox/console, sequences layers).
- **`ztachip tensor engine — Pcores + FPU + dataplane`** — accelerator. **Pcores** = parallel
  processing/MAC cores; **FPU** = floating-point unit; **dataplane** = wide compute fabric streaming
  two words/cycle (the double-rate requirement). This is the **data plane** doing the matrix math.

### Arrows
| Arrow | Meaning |
|---|---|
| Host → PS: `JTAG` | bring-up only (bitstream, model, firmware, mailbox read) |
| FCLK → MMCM: `1 clock root` | single source → exact 2:1 → hold met |
| MMCM → VexRiscv: `clk` | clock to the CPU |
| VexRiscv → ztachip: `control` | control plane → data plane commands |
| DDR ↔ ztachip: `S_AXI_HP0 (64-bit)` | data highway; ztachip masters it to R/W DDR (double-headed = read+write) |

> **One-liner:** PS = clocks + DDR only (passive); all compute = PL (VexRiscv + ztachip); host = JTAG
> bring-up only. The whole architecture pivot in one figure.

---

## Q6 — 2026-06-24 — Explain every row of Table 4.2 (Arty A7 → ZC702 re-mapping)

**Image:** Table 4.2 — before (Arty A7) → after (ZC702), 7 rows.

| Row | Arty A7 | ZC702 | Function / why changed |
|---|---|---|---|
| **FPGA device** | XC7A100T (Artix-7), fabric only | XC7Z020 (Zynq-7000), fabric **+** hard ARM PS | Zynq gives hard DDR ctrl + PLLs for free — enabler for every other row |
| **Memory controller** | Soft **MIG** (DDR ctrl built in fabric, costs LUTs/timing) | **Hard PS DDR controller via `S_AXI_HP0`** | Translates AXI → DDR commands. Hard = no fabric cost, faster, pre-verified. *Deletion of MIG.* |
| **Memory data width** | 128-bit (MIG wide bus) | **64-bit (`exmem_data_width_c=64`)** | Bits/beat. HP port is physically 64-bit, so RTL constant retuned 128→64; bandwidth math uses 64-bit beats |
| **Clock source** | Oscillator + Clk. Wizard (soft PLL) | **One PS FCLK → MMCM (2:1)** | Generate clocks. Single root → exact phase-locked 2× (93.75/187.5) for ztachip dataplane. *= the hold-timing chapter, WHS +0.009* |
| **Model transport** | Ethernet (**TFTP**) | **JTAG pre-load into DDR** | Get ~141 MB model into DDR. Ethernet was stubbed/dead on the ZC702 port → pivoted to JTAG pre-load (model-loader blocker fix) |
| **Console I/O** | UART (serial terminal) | **DDR mailbox ring buffer over JTAG** (@0x30000000, `ZTCH` magic, 2 rings) | Chatbot keyboard+screen. No usable PL UART header on ZC702 → built DDR mailbox read over JTAG |
| **Active processor** | VexRiscv (only CPU) | **VexRiscv (ARM passive)** | Control plane driving ztachip. Kept VexRiscv → one unchanged control stack; ARM only supplies DDR+clocks |

### The pattern
- Device / Memory ctrl / Clock → **soft fabric → hard PS** (offload).
- Model transport / Console → **broken PS port → JTAG workaround**.
- Processor → **unchanged** (VexRiscv kept, ARM idle).

> **One-liner:** Every row = "stop building it in fabric, lean on the hard PS" — except where the PS
> port was broken (Ethernet, UART), routed around over JTAG. Constant = VexRiscv + ztachip, untouched.

---

## Q7 — 2026-06-24 — Two slides: "Clock Architecture Correction" + "Why the Hold Violation Arose?"

### PART A — Clock Architecture Correction (why 93.75 MHz exactly, not 90 / 100)

**Physical source (Fig 1-13):** ZC702 board has **U65 = SiT8103 MEMS oscillator @ 33.33333 MHz**
(VCC1V8 supply, R322 4.7k OE pull-up, C449 decap, R403 24.9Ω series termination) → **PS CLK**.
The PS input is **hardware-fixed at 33.333 MHz** — cannot change.

**Vivado Advanced Clocking:** Input 33.333333 MHz, CPU ratio 6:2:1. Each PLL multiplies the input:
| PLL | Mult | Freq |
|---|---|---|
| ARM PLL | ×40 | 1333.333 MHz |
| DDR PLL | ×32 | 1066.667 MHz |
| **IO PLL** | **×45** | **1500.000 MHz** (fixed) |

Formula: **Out = In × Mult / (Div₁·Div₂)**, rule: **divisors must be INTEGER**.
PL fabric clocks (all from IO PLL = 1500): FCLK0 = 1500/(4·4) = **93.75**, FCLK1 = 1500/(4·2) = **187.5**,
FCLK2 = 23.81, FCLK3 = 25.0.

**The doubled constraint:** fabric clock must be `1500/integer` **AND** its 2× must also be `1500/integer`.
| Q | Verdict | Reason |
|---|---|---|
| 90 MHz? | ❌ | `1500/90 = 50/3` not integer (fails on f) |
| 100 MHz? | ❌ | `1500/100 = 15` ✓ but 2×=200, `1500/200 = 15/2` not integer (fails on 2f) |
| **93.75 MHz?** | ✅ | `1500/16 = 93.75` ✓ AND `1500/8 = 187.5` ✓ (both integer) |

> **Why 93.75:** highest clean freq near the ~100 MHz target where BOTH `f` and `2f` are exact integer
> divisions of the 1500 MHz IO-PLL. The double-rate dataplane requirement kills the round numbers.

### PART B — Why the Hold Violation Arose (root cause → MMCM → CRPR)

**Failing report (real "before" numbers):** Setup **WNS = 0.000** (ok); **Hold WHS = −0.043 ns**,
**THS = −0.089 ns**, **3 failing endpoints** / 100289; WPWS = 2.389. Banner: "Timing constraints are
not met." → **the real pre-fix hold slack is −0.043 ns.**

**Cause:** `FCLK0 (93.75)` and `FCLK1 (187.5)` came from **two independent PLL roots** → launch and
capture clocks had **NO common clock path** → **CRPR cannot credit** shared-path pessimism → tool
keeps all pessimism → **hold fails**.
- CRPR mechanism: when launch+capture clocks share a path before the branch point, STA credits the
  pessimism on that shared segment back. Independent roots = no shared segment = no credit.

**Fix:** insert a **single MMCM** so `FCLK → MMCM → 93.75 + 187.5` — now there is a **common root**
before the split → **CRPR applies** → pessimism credited → **timing closes (WHS = +0.009)**.
- Two block designs shown: left (two independent roots → fails) vs right (MMCM → Ztachip → "No Hold
  Time Violation").

> **Root-cause chain:** independent FCLK roots → no common clock path → CRPR can't credit → WHS −0.043
> (fail). Single MMCM root → shared path → CRPR applies → WHS +0.009 (closes). This slide unifies the
> MMCM fix + CRPR + hold diagrams with the *real failing report*.

---
