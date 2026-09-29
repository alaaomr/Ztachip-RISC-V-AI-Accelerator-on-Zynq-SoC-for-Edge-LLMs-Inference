# Graduation Project — Full Walkthrough
### Running the SmolLM2-135M Language Model on the ztachip AI Accelerator (Xilinx Zynq ZC702 FPGA)

> This document explains the **whole project from the beginning** in plain language,
> for the presentation and documentation. Read it top to bottom — each section builds
> on the previous one. Analogies are included on purpose.

---

## 0. The one-sentence summary

> We took an open-source AI accelerator chip design (**ztachip**), put it onto a real
> FPGA development board (**ZC702**), and made it run a real Large Language Model
> (**SmolLM2-135M**) so that you can type a question and the hardware answers — at
> about **4.5 words-pieces (tokens) per second**.

That's **Phase 1**, and it's **COMPLETE**: we not only made the LLM run, we also *measured*
it — an on-chip performance monitor + a three-model benchmark that **proved the design is
limited by memory bandwidth, not by math** (the characterization data is in **§10.5**).
**Phase 2** is the *next* effort: use those measurements to make ztachip **faster** and able
to run **bigger** models — the concrete, numbers-driven plan is in **§10**.

---

## 1. The big picture — what are we even building?

Think of the project as **three layers stacked on top of each other**:

```
   ┌─────────────────────────────────────────────┐
   │  THE LLM  (SmolLM2-135M)                      │  ← the "brain": answers questions
   ├─────────────────────────────────────────────┤
   │  THE ACCELERATOR  (ztachip + VexRiscv CPU)   │  ← the "engine": does the math fast
   ├─────────────────────────────────────────────┤
   │  THE BOARD  (Xilinx Zynq ZC702 FPGA)         │  ← the "metal": real silicon
   └─────────────────────────────────────────────┘
```

- **The board** is the physical hardware (an FPGA — a chip whose digital circuit can be
  reprogrammed).
- **The accelerator** is the digital circuit we load *into* the FPGA. It is a small
  RISC-V CPU (called **VexRiscv**) plus a powerful math engine (**ztachip**).
- **The LLM** is the software/AI model that runs *on* that accelerator.

**Analogy:** The board is the *car body*, ztachip is the *engine*, and the LLM is the
*driver* who decides where to go. We had to build/fix all three to take a single drive.

---

## 2. What is an FPGA, and what is the ZC702?

An **FPGA** (Field-Programmable Gate Array) is a chip full of tiny logic blocks and wires
that you can *rewire by software*. You describe a digital circuit in a hardware language
(VHDL/Verilog), the tools "compile" it into a **bitstream** (a `.bit` file), and you load
that bitstream into the FPGA. The FPGA then *becomes* that circuit.

**Analogy:** A normal CPU is like a finished building you can only walk through. An FPGA
is like LEGO — you can build *any* building you want, then take it apart and build a
different one.

The **ZC702** is a development board built around a **Xilinx Zynq XC7Z020** chip. The Zynq
is special: it has **two halves on one chip**:

| Half | Name | What it is | Our use of it |
|------|------|-----------|----------------|
| **PS** | Processing System | A hard, fixed **ARM Cortex-A9** dual-core CPU + DDR memory controller | We use it ONLY to give us DDR memory + clocks |
| **PL** | Programmable Logic | The actual **FPGA fabric** (the reprogrammable part) | We put **VexRiscv + ztachip** here |

**Key design decision:** We deliberately keep our whole accelerator (VexRiscv CPU +
ztachip) inside the **PL (FPGA)**. The ARM **PS** is *not* running our program — it just
acts like a "power supply + memory landlord": it boots, sets up the DDR memory and the
clock signals, and then gets out of the way. This keeps the design portable (it isn't
tied to ARM) and matches the original ztachip design, which assumes a soft RISC-V CPU.

---

## 2.5 The starting point: porting ztachip from Arty (Artix-7) to ZC702 (Zynq)

ztachip's reference design (the **GHRD** = Generic Hardware Reference Design, in
`HW/examples/GHRD/`) targets the **Arty A7** board. Your project PORTED it to the **ZC702**.
This is the FOUNDATION step — every later "wall" (§7) traces back to it.

| | Original: **Arty A7** | Target: **ZC702** |
|---|---|---|
| FPGA part | `xc7a100t` (Artix-7, pure FPGA) | `xc7z020clg484-1` (Zynq-7020) |
| Hard ARM CPU? | ❌ none | ✅ the PS |
| DDR | external DDR3 via Xilinx **MIG** soft controller | PS owns DDR3; PL reaches it via **S_AXI_HP0** |
| Clocks | external oscillator + `clk_wiz` | **PS FCLK** outputs |
| Model load | **Ethernet** (TFTP) | **JTAG** preload into DDR |

**Key insight (say this in the defense):** the ztachip *accelerator itself* (Pcores,
dataplane, FPU, VexRiscv, `soc_base`) is **reused essentially unchanged**. The port happens
at the **platform-wrapper** layer — how the accelerator gets DDR, clocks, and I/O. Analogy:
same engine, new car chassis — you redo the mounts (PS7), fuel line (DDR via AXI-HP), wiring
(FCLKs), and dashboard (I/O), but the engine block is identical.

**Actual modifications (from `main_zc702.v`):**
```
  ARTY (GHRD)                       →   ZC702
  1. ext DDR3 pins + Xilinx MIG     →   REMOVED — PS manages DDR3; PL uses S_AXI_HP0 (64-bit)
  2. ext oscillator + clk_wiz       →   REMOVED — PS FCLKs drive PL (MMCM added back, Wall 1)
  3. axi_ethernetlite + eth pins    →   STUBBED — model now JTAG-preloaded (Wall 3)
  4. VGA Pmod + OV7670 camera       →   STUBBED — no Pmods on ZC702 (need FMC card)
  5. main.v / main.xdc (Arty)       →   main_zc702.v / main_zc702.xdc (Zynq pinout)
  6. create_project.tcl + mig.prj   →   create_project_zc702.tcl + zynq_ps_bd.tcl (PS7 BD)
  7. part xc7a100t                  →   part xc7z020
```

**Gains:** 1 GB DDR, PS handles DDR PHY/clocking for free, freed FPGA fabric (no MIG/clk_wiz/
Ethernet IP in the PL). **Consequences (root of every wall):** PS-owned DDR → JTAG preload
(Walls 3,4); integer-divided FCLKs → 93.75 MHz + MMCM (Wall 1); DDR via PS → reserved low-1MB
gap + OCM-low (Wall 4); VexRiscv-on-Zynq → the misaligned-load trap surfaced (Wall 5).

```
  ARTY (original)                 ZC702 (port)
  ext DDR3 ─MIG─┐                 Zynq PS7: DDR3 + FCLKs ──┐
  osc ─ clk_wiz─┤   ═══►          ┌── MMCM ──┐  S_AXI_HP0  │
  Ethernet ─────┤  (same engine,  ▼          ▼  + FCLKs    │
   soc_base     │   new mounts)   soc_base (ztachip+VexRiscv)  ← UNCHANGED
  (ztachip+Vex) ┘                 eth/vga/camera = stubbed
```

---

## 3. What is ztachip? (the accelerator)

ztachip is an **open-source, multicore, RISC-V AI accelerator** meant for edge devices.
Its whole job is to do the **massive amount of multiply-add math** that AI models need,
much faster than a plain CPU (the project claims 20–50× speedups on vision/AI tasks).

### 3.1 The building blocks (this is the architecture slide)

```
        DDR memory (holds the model weights, 141 MB)
              │  (AXI bus)
   ┌──────────┴───────────────────────────────────────┐
   │                  ztachip                          │
   │                                                   │
   │   VexRiscv CPU ── runs our C++ program            │
   │        │                                          │
   │     Mcore  ── the "scheduler/conductor"           │
   │        │                                          │
   │   Dataplane (dp) ── streams data + instructions   │
   │        │                                          │
   │   Scratch-Pad SRAM ── fast on-chip memory         │
   │        │                                          │
   │   Tensor Engine = 28 × Pcores                     │
   │     (each Pcore: Scalar ALU + Vector ALU,         │
   │      16 threads, private memory)                  │
   │        │                                          │
   │   FPU ── floating-point unit (vector mode)        │
   └───────────────────────────────────────────────────┘
```

Plain-language version of each block:

- **VexRiscv CPU** — a small RISC-V processor (the `rv32im` instruction set). It runs our
  ordinary C/C++ firmware: loading the model, the tokenizer, the control logic. It is the
  *manager* — it does not do the heavy math itself.
- **Mcore (scheduling processor)** — decides *which* math task runs next and hands it to
  the data plane. Think *conductor of an orchestra*.
- **Dataplane (dp)** — moves the right data and instructions to the tensor engine at the
  right time. Think *conveyor belt feeding the workers*.
- **Scratch-pad SRAM** — small, very fast memory right next to the math units (DDR is big
  but slow; SRAM is small but fast).
- **Tensor Engine = 28 Pcores** — the muscle. 28 little processors, each with a scalar and
  a vector ALU and 16 threads, that can act like a **systolic array** (a grid that does
  in-memory matrix math). This is where matrix-multiply (the core of an LLM) happens.
- **FPU** — does the floating-point parts. Recent ztachip work added a **vector mode** so
  the FPU processes a whole vector of floats at once — important for the attention step.

**Analogy:** VexRiscv is the *foreman* with a clipboard. The 28 Pcores are the *28
workers* on the assembly line. The Mcore + Dataplane are the *conveyor belts and shift
schedule* that keep all 28 workers fed so none of them sit idle.

### 3.2 Why an accelerator at all?

An LLM is basically **billions of multiply-and-add operations on matrices**. A plain CPU
does a few at a time. The tensor engine does many in parallel. That parallelism is the
entire reason ztachip exists.

---

## 4. What is SmolLM2-135M? (the LLM)

- It is a **small** large-language-model: **135 million parameters** (weights). For
  comparison, ChatGPT-class models are *thousands* of times bigger.
- "Small" matters because our FPGA is tiny compared to a datacenter GPU. 135M weights, when
  **quantized** (compressed to ~4 bits each), fit into the board's **1 GB DDR** memory.
- It is a **LLaMA-style transformer**: the same architecture family as Meta's LLaMA. So the
  code in `SW/apps/llm/` implements the standard transformer steps.
- **Important fact for the presentation:** ztachip's example originally targeted this LLM
  and expects the model in a custom file format called **`.ZUF`** (`SMOLLM2.ZUF`). Our
  model file is **141 MB** and lives in `models/SMOLLM2.ZUF`.

### 4.1 What "running the LLM" actually does (the transformer flow)

When you type a question, the model produces the answer **one token at a time** (a token ≈
a word-piece). Each token requires one full pass through the network, called a **forward
pass**. Our forward pass lives in `SW/apps/llm/llm.cpp::forward()` and does, per layer
(SmolLM2 has 30 layers):

1. **RMSNorm** — normalize the activation vector (keeps numbers in a sane range).
2. **QKV matmuls** — multiply by the Query, Key, Value weight matrices (`wq`, `wk`, `wv`).
3. **RoPE** — rotary position encoding (tells the model *where* each token sits).
4. **Attention** — each token "looks at" previous tokens (softmax over scores).
5. **Output matmul** (`wo`) — combine the attention result.
6. **Feed-forward (FFN)** — two big matmuls (`w1`,`w3`) + SiLU activation + a final matmul
   (`w2`). This is the biggest compute chunk.
7. After all layers: a **final matmul** against the vocabulary (`wcls`) → **logits** (a
   score for every possible next token).
8. **Sampling** — pick the next token from those scores (softmax + probability sampling).

The heavy steps (`matmul`, `rope`, `softmax`) are the **kernels** that run on the ztachip
tensor engine (`SW/apps/llm/kernels/`). There is also a **reference** plain-C++ version
(`SW/apps/llm/reference/llm_ref.c`) used to check the accelerated version is *correct*.

**Why it's slow / memory-bound (key Phase-2 insight):** To generate *each* token, the
hardware must read *all* the model weights out of DDR. 135M weights × ~0.5 byte ≈ ~67 MB
streamed **per token**. The math units are fast; the bottleneck is the *DDR memory
bandwidth*. This is why every token takes ~222 ms and why Phase-2 optimizations focus on
memory (smaller quantization, prefetching, wider memory bus), not on adding more math.

---

## 5. The software stack (what runs where)

```
SW/
├── apps/llm/              ← the LLM application
│   ├── llm.cpp/.h         ← transformer forward pass, sampling, the main brain
│   ├── tokenizer.cpp/.h   ← turns text <-> tokens (numbers the model understands)
│   ├── gguf/              ← model file loaders
│   │   ├── gguf.cpp       ← reads standard GGUF format
│   │   ├── zuf.cpp        ← reads our custom .ZUF format (key/value lookup in DDR)
│   │   └── quant.cpp      ← host tool: compress (quantize) the model weights
│   ├── kernels/           ← ztachip-accelerated math (matmul, rope, softmax) — llm.m/.p
│   └── reference/         ← plain-C++ golden version, to verify correctness
├── base/                  ← C runtime, ztachip libraries, SoC drivers (soc.cpp/.h)
├── compiler/              ← ztachip's own DSL compiler (compiles the .m/.p kernels)
├── linker.ld              ← memory layout for the firmware
└── rebuild_fw.sh          ← our script: builds firmware into vector.bin + main.bin
```

The compiled program (the **firmware**) is what the VexRiscv CPU runs.

---

## 6. The end-to-end flow on board day (how a question gets answered)

This is the **demo/flow slide**. Step by step, from power-on to an answer:

```
1. Power on ZC702.  ARM PS boots, sets up DDR + clocks (ps7_init).
       │
2. From the PC over JTAG (xsdb), we hold the VexRiscv CPU in reset.
       │
3. We load the 141 MB model (SMOLLM2.ZUF) into DDR @ 0x10000000.   ← only on a cold start
       │
4. We load the firmware in TWO pieces (see §7.4):
       vector.bin → 0x00004000 (OCM),   main.bin → 0x00100000 (DDR)
       │
5. We clear the "mailbox" console area in DDR, then RELEASE VexRiscv from reset.
       │
6. VexRiscv boots our firmware → opens the model → builds the tokenizer → prints
       "I am a chatbot" and a ">" prompt into the DDR mailbox.
       │
7. The PC (xsdb script) reads the mailbox over JTAG and shows ">" to you.
       You type a question; it goes back through the mailbox into the firmware.
       │
8. The firmware runs forward() once per output token, streaming weights from DDR
       through ztachip, and writes each answer token into the mailbox.
       │
9. The PC prints the answer, then prints a [HOST PERF] line with tokens/sec.
```

There is **no keyboard/screen on the board** for us (see §7.5 — the UART pins aren't
usable on this board), so input/output travels through a small **message area in DDR**
that both sides read/write. We call it the **DDR mailbox / console**.

---

## 6.5 DDR & the memory map — why those specific addresses

Think of all memory as **one long street**; every byte has a house number (a hex
address). On the Zynq the street runs `0x00000000`–`0x3FFFFFFF` (**1 GB DDR**), but the
low end is reserved for special regions, including a "do-not-build" gap. Our `linker.ld`
documents the carve-up:

```
  ADDRESS RANGE             WHAT LIVES THERE                         SIZE
  ─────────────────────────────────────────────────────────────────────────
  0x00000000 – 0x00003FFF   PL BRAM (TCM): stack / scratch           16 KB
  0x00004000 – 0x0003FFFF   PS OCM (on-chip RAM, mapped LOW)        ~240 KB
  0x00040000 – 0x000FFFFF   ⛔ RESERVED GAP — JTAG cannot write     ~768 KB
  0x00100000 – 0x3FFFFFFF   PS DDR (big 1 GB main memory)            ~1 GB
  ─────────────────────────────────────────────────────────────────────────
  Chosen plots inside DDR:
  0x00100000   firmware main.bin     (first clean address above the gap)
  0x10000000   model SMOLLM2.ZUF     (256 MB mark — clear of the heap)
  0x20000000   mailbox console       (512 MB mark — clear of everything)
```

**Why each address:**
- **`0x00004000` (boot stub, OCM):** VexRiscv's reset vector is *hardwired* to `0x4000`,
  so the first instruction MUST live there. It's a tiny stub (`vector.bin`) that jumps to
  the real program in DDR. Analogy: the law says everyone enters through this one front
  door; inside is a sign "real office at 0x100000."
- **`0x00040000–0x000FFFFF` (reserved gap):** JTAG/ARM cannot write here. This is exactly
  WHY the firmware is split into two files that *straddle* the gap (`vector.bin`@0x4000 +
  `main.bin`@0x100000) — nothing ever lands inside it.
- **`0x00100000` (main firmware):** first clean DDR address above the gap.
- **`0x10000000` (model):** parked at the 256 MB mark because the firmware **heap is ~200
  MB** (`_heap_size` in linker.ld); the model sits far above so the growing heap never
  collides with it.
- **`0x20000000` (mailbox):** 512 MB mark, separate plot so nothing overwrites the console.
  Sub-layout: magic@+0, OUTHEAD@+0x40, OUTTAIL@+0x80, INHEAD@+0xC0, INTAIL@+0x100,
  OUTBUF@+0x1000 (4 KB ring chip→PC), INBUF@+0x2000 (4 KB ring PC→chip).

**Two magic markers** (sanity checks): model magic `0x4341545A` = `'ZTAC'` at 0x10000000
(proves the model survived in DDR → can skip the 40-min reload); mailbox magic
`0x5A544348` = `'ZTCH'` at 0x20000000 (proves firmware booted + opened the console).

**Two masters, one street:** the JTAG/ARM debugger writes memory while *loading*; the
VexRiscv CPU reads it while *running* (via its `S_AXI_HP0` port). For both to see the same
bytes at low addresses, OCM must be **mapped LOW** (scripts poke `OCM_CFG` @0xF8000910) —
otherwise the byte the PC wrote to 0x4000 and the byte VexRiscv reads from 0x4000 would be
different physical memory.

**Phase-2 tie-in:** the 141 MB model lives in *slow DDR* (too big for fast on-chip SRAM),
and every token streams the whole model from there → that location is *why* the system is
memory-bound (§4.1).

---

## 6.6 Common questions (FAQ)

**Q1. Why not put ALL the firmware above the reserved gap (skip the split)?**
Because VexRiscv's reset vector is *hardwired* to `0x00004000` (below the gap) — the CPU's
first instruction MUST live there. But `0x4000` is in OCM, which is only ~240 KB, far too
small for the 8.4 MB firmware. So: a tiny stub at `0x4000` that jumps to DDR, and the full
firmware at `0x100000`. The split is the only layout that satisfies both constraints.

**Q2. What's the ROLE of the reserved gap if nobody can write to it?**
It's not ours to use — it's a side effect of the Zynq's design. The chip can "remap" OCM
to appear at address `0x0` (some boot modes need code at 0). To allow that, the low 1 MB is
carved up specially: OCM at the bottom, the DDR underneath is shadowed/unreachable, and the
leftover middle (`0x40000–0xFFFFF`) is backed by neither → a hole where writes don't stick.
Analogy: a building's reserved "ductwork floor" — it serves the building's systems, but you
can't rent an office there. We just route firmware around it.

**Q3. What is the "heap" and why 200 MB?**
The heap is the pool of memory a running program uses for dynamic allocation (`malloc`/`new`)
— activations, the KV-cache (grows with sequence length), RoPE tables, logits, etc. It's
reserved generously (200 MB) so the model never runs out mid-answer. Two subtleties: (1)
it's `NOLOAD` — just *reserved address space*, not 200 MB actually downloaded over JTAG (so
it costs nothing to load; `main.bin` is only 8.4 MB); (2) it's placed last/highest and stays
below the model at `0x10000000`, so it can grow without colliding with the model.

**Q4. How do the two "magic words" (ZTAC / ZTCH) verify the model/firmware exist?**
A magic number = a known value at a known address. Letters are stored as ASCII bytes; read
as one little-endian 32-bit word, `Z T A C` → `0x4341545A`, `Z T C H` → `0x5A544348`. The
model file starts with `"ZTAC…"`, so reading `0x4341545A` at `0x10000000` proves the model
survived in DDR (else: reload). The firmware *writes* `ZTCH` to `0x20000000` once its console
is ready, so the PC polling that address knows the firmware booted. It's a password-at-a-
known-spot handshake (a ~1-in-4-billion chance of a false positive — reliable in practice).

**Q5. Should we change the reset vector `0x4000` → `0x100000` to drop the split?**
It would be CLEANER (one binary, no stub, no OCM remap, no gap-straddling) — but it's a
*hardware* change (regenerate VexRiscv + rebuild bitstream + re-verify timing), and it does
**NOT** help run larger models (the model lives at `0x10000000` regardless; the reset vector
only sets where *firmware* boots). Recommendation: keep the split now (works, free); fold the
reset-vector change into the Phase-2 bitstream rebuild (which happens anyway for the PMU).
- Files to edit: `HW/riscv/xilinx_jtag/riscv.scala` (`resetVector=0x00100000l`, regenerate
  `riscv.v`; or patch the `pcReg` reset constant in `riscv.v` ~line 5114) → `SW/linker.ld`
  (single region @0x100000) → `SW/rebuild_fw.sh` (single binary) → `board_resume_fw.tcl` +
  `board_day_run.tcl` (load one binary, delete the `vector.bin` load + the `OCM_CFG` remap).
- Flow: edit reset vector → simplify linker → simplify build script → simplify board scripts
  → re-synthesize bitstream + check timing → reload + test.
- NOTE the committed files are inconsistent (scala=0x0, riscv.v pcReg=0x80000000, sim=0x4000,
  board behaves as 0x4000) — the authoritative source is the VexRiscv `.scala` → bitstream.

**Q6. What ACTUALLY needs to change to run a LARGER model?** (separate from Q5)
| Goal | Where | Current value |
|------|-------|---------------|
| More working memory | `SW/linker.ld` | `_heap_size = 200000000` (keep below model base) |
| Model location / room | board `.tcl`, `llm.cpp` | base `0x10000000`, within 1 GB DDR |
| More layers | `SW/apps/llm/llm.h` | `MAX_NLAYERS 32` |
| Longer context | `SW/apps/llm/llm.h` | `MAX_LLM_SEQ_LEN 1024` (grows KV-cache → more heap) |
| More memory bandwidth | `HW/src/ztachip_pkg.vhd`, `config.vhd` | `ddr_vector_depth_c` (64/128-bit bus), `exmem_data_width_c` |
| Hard ceiling | — | 1 GB DDR → ~a few-hundred-M params even quantized |

**Q7. Why not use a UART for the console instead of the DDR mailbox? What would we gain?**
ztachip HAS a UART block (`HW/src/soc/peripherals/uart.vhd`) — the issue is physical pins,
not logic: (1) the ZC702's convenient USB-serial console is wired to the ARM **PS**, not our
VexRiscv in the **PL**; (2) the PL-routable UART pins come out only on the **FMC connector**
(needs a breakout card/wiring); (3) the clean alternative — routing PL UART out via **EMIO →
PS MIO** — needs a bitstream rebuild. Since the JTAG cable was already connected to load the
141 MB model, reusing it for a mailbox console cost **zero extra hardware**. A real UART would
mainly *simplify software* (drop the ring/magic/retry code), *free the JTAG debugger*, and
remove the "Invalid context" flakiness — a cleanup, **not** a performance gain (UART ~115200
baud is also slow). Good Phase-2 add-on (wire it via EMIO during the PMU rebuild).

**Q8. How does the DDR mailbox work and what are its constraints?**
With no usable UART, the chip and PC talk through shared DDR at `0x20000000`: two **ring
buffers** (OUT chip→PC = the answer, IN PC→chip = your typing), each 4 KB, with head/tail
pointers and a `'ZTCH'` "alive" marker (layout in §6.5). A ring buffer = a fixed circular
array; the writer advances `head`, the reader advances `tail`, wrapping at the end; new data
exists when `head ≠ tail`. **Constraints:** (1) the ring is only 4096 B, so if the firmware
writes faster than the PC drains it, the firmware **blocks** (`(head−OUTTAIL) ≥ RING`). (2)
This is exactly why host wall-clock timing is VALID: a capped 160-token answer (~640 B) fits
in 4 KB, so the firmware never fills the ring, never blocks on slow JTAG → **host elapsed ≈
real compute time**. The 160-tok cap + 4 KB ring are a matched pair. (3) Stale state: clear
magic+pointers before releasing the CPU. (4) JTAG hiccups: `safe_mrd`/`safe_mwr` retry.

**Q9. The "dead timer" — what exactly is dead, and which CPU?**
Distinguish two different things: a **clock SIGNAL** (`clk_main`/`clk_x2` from the MMCM, the
heartbeat — these WORK, that's why the chip runs) vs a **timer/COUNTER** (a register that
counts heartbeats so software can read elapsed time — these are broken). The CPU that would
read them is **VexRiscv** (PL), the worker; the ARM (PS) never touches them. Both counters
tick internally but neither can be READ: the APB timer's read-back (`prdata`) never reaches
VexRiscv (returns 0), and the RISC-V `mcycle` CSR was never wired into the CSR read mux
(returns 0). Analogy: the clock's pendulum swings fine; the readable face is unplugged. So we
fall back to host wall-clock timing (§8); per-block cycle profiling needs a bitstream rebuild
(the Phase-2 PMU).

---

## 7. The engineering journey — the problems we solved (the "story" slides)

This is the most valuable part for a presentation: it's the *story* of real engineering.
Each item below is "we hit a wall → here's why → here's the fix."

### 7.1 Bitstream & clocking — making the FPGA timing-clean
- ztachip's reference design targets a different board (Arty). We created a new Vivado
  project for the ZC702 (`create_project_zc702.tcl`) and a Zynq block design
  (`zynq_ps_bd.tcl`) so the ARM PS feeds DDR + clocks to the PL.
- **Clock bug:** the design needs a `clk_x2` that is exactly **2×** the main clock. The
  config had them wrong. We fixed the PS clock (`FCLK1`) and `main_clock_c`, and used an
  **MMCM + jitter refinement** so timing fully closed: **WNS 0.000, WHS +0.009** at
  **93.75 / 187.5 MHz**. "Timing closed" = the circuit is reliable at that speed.

### 7.2 The model format — SMOLLM2.ZUF
- chat.cpp/ztachip expects the model as **`.ZUF`**, not raw GGUF.
- At one point the `.ZUF` file was a broken 68 KB stub. We learned the converter needs an
  **F16/F32 GGUF** input (not an already-Q4_K_M quantized one), and **regenerated a valid
  141 MB `SMOLLM2.ZUF`**.

### 7.3 No Ethernet → load the model over JTAG
- The original design downloads the model over **Ethernet**. On our ZC702 port the
  Ethernet is **stubbed** (not wired up). So the TFTP model-loader is dead.
- **Fix:** we **pre-load the model into DDR over JTAG** using Xilinx's `xsdb` debugger
  from the PC. (Note: on 2025.2 the command is **`xsdb`**, not the old `xsct`.) This is
  what `run_board_day.sh` does — and it's why a cold start takes ~40 minutes (pushing
  141 MB over JTAG is slow).

### 7.4 The boot chain & the "low-1MB gap"
- The firmware ELF was initially huge and laid out wrong. We fixed the reset vector and
  linker script, shrinking a 204 MB ELF down to a 14 MB load.
- **The Zynq trap:** addresses **0x40000–0xFFFFF** are *reserved* on the Zynq — you can't
  put code there. So we **split** the firmware: a tiny **vector stub at 0x4000 in OCM**
  (on-chip RAM, mapped low) + the **main image at 0x100000 in DDR**. We also map all OCM
  blocks low to remove a hole. This is the `vector.bin` + `main.bin` split you see in the
  scripts. After this, the firmware **booted** and started reading the model.

### 7.5 No usable UART → the DDR mailbox console
- The ZC702 has no PL UART header we can reach (the UART pins are on the FMC connector).
  So there's no simple serial terminal for our PL CPU.
- **Fix:** we built a **DDR mailbox** at `0x20000000` — a ring-buffer "chat window" in
  memory (magic `'ZTCH'`, with OUT/IN head/tail pointers and 4 KB ring buffers). The
  firmware writes output there; the PC reads it over JTAG, and vice-versa. That's our
  console.
- **Two robustness bugs we fixed in the console scripts:**
  - **Stale mailbox race:** on a board that stayed powered, the *previous* run's data is
    still in DDR; the PC would latch onto stale pointers and the console looked dead. Fix:
    **clear the mailbox magic + pointers before releasing the CPU.**
  - **"Invalid context" crash:** xsdb's ARM debug connection goes stale under constant
    polling and a raw memory read throws and kills the script. Fix: **`safe_mrd`/`safe_mwr`
    wrappers** that catch the error, re-select + re-halt the ARM core, and retry.

### 7.6 THE BIG ONE — the silent VexRiscv misaligned-load trap
This is the headline bug and the best story in the project.

- **Symptom:** the firmware printed "Model found in DDR" and then **silently stopped** —
  no crash, no error, no output. Just frozen. It happened the instant it tried to read the
  first config value (`llama.embedding_length`).
- **Investigation:** we added trace prints and narrowed it to `findKey()` inside the `.ZUF`
  loader — specifically the line that does `strcmp(key, ele.key)`.
- **Root cause:** the VexRiscv CPU (`rv32im`) has **no hardware support for *misaligned*
  word loads**, and when one happens it **traps silently** (there's no handler installed,
  so the CPU just stops). The C library's `strcmp` (and `-O3`-inlined string compares)
  reads memory **a full 32-bit word at a time** for speed. But the model's text strings
  (keys, vocabulary, merge rules) sit at **odd/unaligned addresses** in DDR
  (e.g. `0x10000031`). So `strcmp` issued an unaligned word load → silent trap → frozen CPU.
- **Fix:** replace those library string compares with **byte-by-byte compares** (one byte at
  a time is always aligned). We did this in:
  - `gguf/zuf.cpp::findKey()` (the model key lookup), and
  - `tokenizer.cpp` (a helper `zstrcmp`, replacing all 7 `strcmp` calls).
- **The rule we now follow:** *never use a libc word-optimized string function on raw model
  bytes in DDR.* This single fix unblocked the entire model load + all 30 layers and is why
  the LLM finally ran. (`memcpy`/`strlen` had survived because they use byte loads or align
  first — that's why the bug was so sneaky.)

### 7.7 Making it usable & measurable
- **Runaway responses:** a small LLM often "doesn't know when to stop" and loops. We added
  a **hard cap** (`maxTokenResponse × 4` = 160 tokens) so it always stops.
- **Timing:** we wanted tokens/second. But we discovered the **on-chip timers are dead in
  this bitstream** (see §8). So we measure on the **PC wall clock** instead — valid because
  a short answer fits the 4 KB ring, so the firmware never waits on the slow JTAG link, so
  PC-elapsed ≈ actual compute time. This prints the `[HOST PERF]` line.

---

## 8. Known limitation: the on-chip timers are dead (sets up Phase 2)

We *want* cycle-accurate, per-block hardware measurements. But in **this** bitstream:
- The **APB timer** peripheral (`HW/src/soc/peripherals/time.vhd`) reads **0** — its data
  isn't reaching the CPU in the ZC702 integration.
- The VexRiscv **`mcycle`** cycle counter increments internally but is **not wired into the
  CPU's CSR read path** (`riscv.v`), so reading it returns 0.

So right now we can only measure **whole-response** time from the host, not *inside* the
chip. Fixing this needs a **bitstream rebuild** — which is exactly the first task of
Phase 2.

---

## 9. Current result (Phase 1 — DONE ✅)

Phase 1 had **three parts**, all complete: **(A)** make the LLM run, **(B)** measure it and
find the bottleneck, and **(C)** verify the compute kernels on real hardware. The
characterization numbers (B) are in **§10.5**; the kernel verification (C) is just below.

**Part A — it runs:**
- **SmolLM2-135M runs on the ZC702 and answers prompts.**
- **4.13 tokens/second** on the 30-prompt benchmark (early ad-hoc runs showed ~4.5),
  with very low run-to-run variance.
- VexRiscv @ **93.75 MHz** + ztachip tensor engine, model JTAG-preloaded into DDR.
- A **restore point** is saved so we can always return to this working state:
  - git tag **`phase1-llm-working-2026-06-17`**
  - off-repo backup in `backups/` (source tarball + `main.bin` + `vector.bin` +
    `main_zc702.bit`)
  - documented in `CHECKPOINT.md`.

**Part B — it's characterized:** on-chip PMU + 3-model benchmark **proved memory-bound**
(§10.5). This is the close-out of Phase 1 and the foundation for the Phase-2 plan (§10).

**Part C — the kernels are verified on silicon:** we ran a kernel self-test that checks each
ztachip compute kernel against the bit-exact reference C implementation, on the chip itself.
**11 of 11 kernels passed with zero mismatches** (~38,657 element comparisons):

| Kernel | Result | | Kernel | Result |
|---|---|---|---|---|
| residual | `bad=0` ✅ | | sine | `bad=0` ✅ |
| SwiGLU | `bad=0` ✅ | | quantize | `bad=0` ✅ |
| rms (RMSNorm) | `bad=0` ✅ | | **matmul_q4** | `fail=0` ✅ |
| rope | `bad=0` ✅ | | **matmul_q8** | `fail=0` ✅ |
| softmax | `bad=0` ✅ | | k_max | `fail=0` ✅ |
| cosine | `bad=0` ✅ | | | |

**Why this matters for the defense:** the two `matmul` kernels (the INT4/INT8 matrix-multiply
engine — the bulk of every transformer layer) take *hours* in RTL simulation but run in
*seconds* on the chip, so silicon is the only practical way to verify them. Getting `bad=0`
on all of them proves the ztachip hardware datapath is mathematically faithful to the
reference — independent, kernel-level evidence on top of the system-level proof that the
chatbot answers correctly. Reproduce with `bash HW/examples/ZC702/run_kernel_test.sh`; full
write-up in `HW/examples/ZC702/bench/results/kernel_verification.md`.

---

## 10. Phase 2 plan — make ztachip FASTER (numbers-driven, the "future work" slide)

Phase 1 told us *exactly* what to fix. The speed of the chip obeys one simple equation:

```
            delivered DDR bandwidth          (how fast we pull weights from memory)
  tok/s  =  ───────────────────────
                bytes per token              (how many weight-bytes each token needs)
```

Phase 1 **measured both numbers** (§10.5): bandwidth pinned at ~430–530 MB/s, bytes/token
= 103 MB for Q4. Because the chip is **memory-bound**, we make it faster by **raising the top**
(bandwidth) or **shrinking the bottom** (bytes) — **NOT** by adding math units (they already
sit idle 30–42% of every run). **Analogy:** the workers are fast; widen and speed up the
*conveyor belt*, don't hire more workers.

### Why there's lots of room (the headroom, in measured numbers)
- We deliver **431–530 MB/s** of DDR reads.
- The 64-bit memory port at 93.75 MHz can do **~750 MB/s** → we're only at 57–71% of even that.
- The DDR3 chips themselves can do **~4+ GB/s** → we use roughly **one-tenth** of the real memory.
- The read engine **stalls 30–42%** of the time (it's *waiting*, not reading).

**=> The bottleneck is the on-chip memory *path* (the AXI/DMA plumbing), not the DRAM.** That's
good news: the fix is plumbing we control, with a lot of headroom.

### Track A — Raise delivered bandwidth (biggest lever; needs a bitstream rebuild)
- **A1. Run the memory port faster.** Today the DDR/AXI-HP path runs at the 93.75 MHz main
  clock. The Zynq's HP ports can run ~150–200 MHz; clocking it at 187.5 MHz roughly **doubles**
  the ceiling. (Re-opens the timing-closure work from §7.1 — budget for the MMCM/jitter dance.)
  *Estimated ~1.5–2× faster.*
- **A2. Make the memory path twice as wide (64 → 128 bits).** The original Arty design was
  128-bit; we narrowed it to 64 for one HP port. Use two of the Zynq's four HP ports (or an
  AXI width-converter) to move 2× the bytes per clock. With A1, ~4× the raw ceiling.
- **A3. Stop the read engine from waiting (cut the 30–42% stall).** Allow more in-flight reads
  + a deeper prefetch buffer + longer bursts so it isn't idling on memory latency. The measured
  stall % is literally the size of this prize. *Estimated +20–40%.*

### Track B — Shrink bytes-per-token (firmware, fast to try)
- **B1. Compress the KV-cache (FP16 → INT8).** Halves the "memory of the conversation" traffic,
  which grows with how long the chat is.
- **B2. Keep reused weights on-chip** (RMSNorm weights, the current token's embedding row) in the
  fast scratch-pad SRAM instead of re-reading them from DDR every single token.
- **B3. Go below 4 bits on the layers that can take it.** The Q4-vs-Q8 result proved bytes and
  time move together, so every byte saved is speed gained — at some cost to answer quality, which
  we can *measure* with the Phase-1 30-prompt quality scoreboard.

### Track C — Do math and memory at the same time (bitstream)
- **C1. Prefetch the next layer's weights while computing the current one** (double-buffering).
  This directly turns the measured 30–42% idle time into useful work — best bang-for-buck after A1.
- **C2. Only after A+C** will compute start to matter; *then* raising the main clock or adding
  Pcores finally helps. (It wouldn't help today — we're memory-bound.)

### Track D — Keep measuring (the PMU from Phase 1 already exists)
- **D1. Per-kernel profiling** so we see whether matmul, attention, or norm dominates — and prove
  each change actually helped.
- **D2. Real power (PMBus rails)** → the headline **tokens-per-second-per-watt** number and a
  measured roofline. (This is the one Phase-1 item still open; needs no bitstream.)

### Recommended order & target
```
  D1 (profile) → A1 (faster port) → A3 (stop stalls) → C1 (prefetch) → A2 (wider port) → B (fewer bytes)
```
A1 + A3 + C1 alone could plausibly take 135M-Q4 from **4.13 → ~7–9 tok/s with no loss of answer
quality**; A2 pushes further; Track B trades quality for more. Re-measure after every step.

### For *bigger* models (the other Phase-2 goal)
Raise the layer / sequence-length caps (`llm.h`), keep reworking the DDR memory map (we already
moved the mailbox to 0x30000000 for the 360M), and compress the KV-cache (B1) — all bounded by
the **1 GB DDR ceiling** (~a few-hundred-million params, quantized).

### Cost / risk
- **A1, A2, A3, C1** change hardware → **bitstream rebuild + re-close timing** (the 93.75 MHz
  hold-slack story from Appendix A comes back when the memory clock rises).
- **B1, B2, B3, D1** are **firmware only** → fast to iterate, no bitstream.
- After every change, re-check correctness against the reference (`llm_ref.c`) and the 30-prompt
  quality scoreboard, so a speed win never silently breaks the answers.

---

## 10.5 Phase-1 characterization data — the memory-bound result (DONE ✅, 2026-06-22)

> This is the **close-out measurement of Phase 1** (it's what the Phase-2 plan in §10 is built
> on). We built the PMU (the on-chip performance monitor) and ran a real experiment to answer
> one question: **what is actually slowing the chip down — the math, or the memory?**
> The answer is **memory**, and we proved it two independent ways.

### The experiment
We ran the **same 30 questions** (6 categories: Math, Science, Geography, History,
Engineering, General) through **three different models** and measured, on-silicon, the
speed (tokens/sec) and the memory traffic (bytes read from DDR per token):

| Model | What's different | tokens/sec | bytes read per token | DDR read rate |
|---|---|---|---|---|
| SmolLM2-135M **Q4** (repo default) | the baseline | **4.13** | 103 MB | 431 MB/s |
| SmolLM2-135M **Q8** | same brain, 8-bit weights | **3.34** | 156 MB | 526 MB/s |
| SmolLM2-360M **Q4** | bigger brain, 4-bit weights | **1.90** | 248 MB | 478 MB/s |

### The proof it's "memory-bound" (the core Phase-1 characterization result)
**Memory-bound** means the speed is set by *how fast we can pull weights out of DDR*, not by
*how fast the math runs*. **Analogy:** the workers (math units) are fast, but the
conveyor belt (memory) can only deliver parts so quickly — adding more workers wouldn't help.

We showed it two ways that back each other up:

1. **Same brain, fatter weights (Q4 vs Q8).** These are the *identical* network doing the
   *identical* math — the only change is each weight is 8 bits instead of 4, so there's ~1.5×
   more to read. Result: Q8 is **1.24× slower**. If math were the bottleneck they'd run at the
   *same* speed. They don't → it's the memory.
2. **Same weights, bigger brain (135M vs 360M).** The 360M model carries **2.4× the bytes per
   token** and runs at **0.46× the speed** — speed drops almost exactly in step with bytes
   moved.

And the clincher: multiply *speed × bytes-per-token* for all three and you get a **flat
426–520 MB/s** — they're all hitting the same memory ceiling. The biggest model's run-to-run
variation was almost zero (±2%), which is exactly what a hard bandwidth ceiling looks like.

### Bonus finding — bigger model = smarter answers (but still not trustworthy)
We graded all 30 answers from each model against the correct facts (2 pts good / 1 partial /
0 wrong, max 60):

| | 135M Q4 | 135M Q8 | 360M Q4 |
|---|---|---|---|
| Quality score / 60 | 24 | 28 | **40** |

- **360M is clearly the smartest** — it was the only model to correctly answer the integral
  ∫1/(1+x²)=arctan, fission-vs-fusion, the transformer, and sync-vs-async logic — but it costs
  **2.2× the time per answer**, and it *still* makes confident mistakes (it claimed the Marshall
  Plan was "$133 billion" and that "RISC = Reduction in Speed"). Lesson: use a small model for
  *structure and explanation*, but verify every fact and number.
- **Q8 ≈ Q4 in quality (28 vs 24), and that small gap is just luck**, because they are literally
  the same network — which is *why* the Q4-vs-Q8 pair is a clean speed/memory experiment and
  never a quality claim.

### What this means for the project story
- **Don't add more math units to go faster** — they'd sit idle. To speed up the *same* model,
  attack memory: lower-bit quantization, weight prefetch/double-buffering, or a wider DDR bus.
- **To run a *bigger/smarter* model, you pay in speed**, and the cost is set by memory traffic.
- This is the experimental backbone for the efficiency (**tokens/sec per watt**) argument: on a
  93.75 MHz FPGA we lose on raw speed but the compute itself is tiny — most of the energy is
  memory movement (power measurement is the one remaining open item, §13).

### Note: the mailbox moved for the big model
The 360M model is **308 MB**. The console mailbox used to sit at `0x20000000` (the 512 MB
mark), which left only 256 MB for the model. To fit the bigger model we **moved the mailbox to
`0x30000000`** (the 768 MB mark), giving the model region 512 MB. This was a firmware + host
change only (no bitstream rebuild). So §6.5's `0x20000000` is now `0x30000000` for all current
runs.

### Where the data lives
`HW/examples/ZC702/bench/` — `run_model.sh` (runs one model), `summarize.py` (builds the
comparison), and `results/` (per-model CSV, raw outputs, JSON, console logs, and the aggregated
`comparison.md`). Full session backup: `backups/session_2026-06-22_3model/`.

---

## 11. Glossary (quick reference for the audience)

| Term | Plain meaning |
|------|----------------|
| **FPGA** | A chip whose digital circuit you can reprogram |
| **PS / PL** | Zynq's hard ARM CPU side / the reprogrammable FPGA side |
| **Bitstream (.bit)** | The compiled circuit you load into the FPGA |
| **VexRiscv** | The small soft RISC-V CPU running our firmware |
| **ztachip** | The AI math accelerator (28 Pcores + FPU + dataplane) |
| **Pcore** | One of 28 parallel math cores in the tensor engine |
| **DDR** | The big (1 GB) but slow external memory holding the model |
| **OCM** | On-Chip Memory — small but fast, used for the boot vector |
| **JTAG / xsdb** | The debug cable + tool we use to load memory from the PC |
| **Token** | A word-piece; the model emits one per forward pass |
| **Forward pass** | One full run through the network to produce one token |
| **Quantization** | Compressing weights (e.g. to 4 bits) to save memory |
| **Matmul** | Matrix multiply — the dominant LLM computation |
| **Attention** | The step where a token "looks at" earlier tokens |
| **Mailbox** | Our DDR-based console for chatting with the board |
| **Memory-bound** | Limited by memory speed, not math speed |
| **Quantization (INT4/INT8)** | 4-bit vs 8-bit weight compression |

---

## 12. Suggested presentation outline (slides)

1. Title + one-sentence summary (§0)
2. The three layers (§1)
3. What's an FPGA / the ZC702 Zynq PS+PL (§2)
4. ztachip architecture diagram (§3.1)
5. SmolLM2 + the transformer flow (§4)
6. End-to-end board-day flow (§6)
7. **The journey** — 3–4 problem/fix slides (§7), with §7.6 as the dramatic centerpiece
8. Result: it works, 4.5 tok/s, with a demo (§9)
9. Phase-2 plan (§10)
10. Glossary backup slide (§11)

---

## 13. Comparative baseline — same model on other hardware

A teammate benchmarked the **same SmolLM2-135M (Q4_K_M)** on an **NVIDIA Jetson TX1** (and an
NVIDIA **T4** set, numbers TBD), giving a real cross-platform comparison.

### Teammate methodology (Jetson TX1, llama.cpp on GPU)
30 prompts × 6 categories (MATH/SCI/GEO/HIST/ENG/GEN) × **5 repeats = 150 runs/model**.
Per-run: `gen_tokens`, `wall_time_s`, `tps` (= gen_tokens/wall_time), timestamps; plus full
prompt+output JSON and a `tegrastats` telemetry log.

### Throughput results (mean tok/s)
| Platform | Model | Quant | Clock | Mean tok/s | Notes |
|----------|-------|-------|-------|-----------|-------|
| Jetson TX1 (256-core Maxwell GPU) | SmolLM2-135M-Instruct | Q4_K_M | ~1 GHz | **14.92** | range 7.8–18.2 |
| Jetson TX1 | SmolLM2-135M-Base | fp | ~1 GHz | 13.46 | |
| Jetson TX1 | Qwen2.5-0.5B-Instruct | Q4_K_M | ~1 GHz | 5.42 | ~25 s wall |
| **ztachip ZC702** (FPGA, VexRiscv+28 Pcores) | **SmolLM2-135M** | **Q4** | **93.75 MHz** | **4.13** | 30-prompt suite, on-silicon PMU (§10.5) |
| ztachip ZC702 | SmolLM2-135M | Q8 | 93.75 MHz | 3.34 | §10.5 |
| ztachip ZC702 | SmolLM2-360M | Q4 | 93.75 MHz | 1.90 | §10.5 |
| NVIDIA T4 (datacenter GPU) | SmolLM2-135M | Q4 | ~1.6 GHz | _TBD_ | upper-bound ref |

Raw: Jetson ≈ **3.3× faster** than ztachip. EXPECTED — GPU @ ~1 GHz vs FPGA @ 93.75 MHz.
The project's value is **efficiency (tok/s/W) on low-end FPGA**, NOT raw speed.

### Do the parameters match ours?
| Parameter | Jetson | ztachip | Match |
|-----------|--------|---------|-------|
| tokens/sec (gen/wall) | ✅ | ✅ same definition | ✅ apples-to-apples |
| wall time / gen tokens / ms-tok | ✅ | ✅ | ✅ |
| prefill vs decode split | ❌ total only | ✅ `[PERF]` | we have more |
| variance method | ✅ 30×5 by category | ⚠️ 3 ad-hoc runs | adopt theirs |
| **real power (W)** | ❌ tegrastats = util+temp, NO watts | ⏳ PMBus (Phase 2) | ❌ neither yet |
| utilization | ✅ GPU% (GR3D) | ⏳ Pcore% (PMU) | parallel, diff units |
| per-kernel cycles | ❌ | ⏳ PMU | we'll have more |

### Power methodology (why it's the headline, and the PS question)
Power is THE metric for this project — on raw tok/s ztachip loses; on **tok/s/W** a 93.75 MHz
FPGA can win. On the ZC702, PMBus reads SEPARATE Zynq rails, so we can break power down:
- **VCCINT** = PL fabric (ztachip + 28 Pcores + VexRiscv) = the actual compute.
- **VCCPINT/VCCPAUX** = PS (ARM + DDR controller) — not computing, but keeps DDR+clocks alive
  (required), so its power is part of the real system cost.
- **DDR rail** = the DDR3 memory — large for us because decode is memory-bound.

Report BOTH: (1) **system power** (PL+PS+DDR) for a fair comparison vs the Jetson/T4 (also full
chips); (2) **per-rail breakdown** as our advantage — "compute (VCCINT) is tiny, most energy is
DDR" → physical proof of memory-bound. The PS power is NOT a contaminant; include it.

### TODO to make the comparison scientific
1. ✅ DONE — ran the SAME 30-prompt suite on ztachip (Q4/Q8/360M); tps table in §10.5.
2. Real power BOTH sides (ztachip PMBus; TX1 INA3221 via sysfs) → tok/s/W headline. ← only open item
3. ZC702 per-rail power breakdown (proves memory-bound + cheap compute). ← needs #2
4. Add the T4 row as a datacenter upper-bound reference.
5. ✅ DONE — answer-QUALITY comparison graded across all 30 prompts (§10.5).

---

## Appendix A — Wall 1 deep dive: clocking, MMCM & STA pessimism

### A.1 Why the clock is pinned to 93.75 / 187.5 MHz
ztachip needs `clk_x2 = exactly 2 × clk_main` (data stored in 2 words, clocked out at
double rate). Zynq FCLKs can only be `1500 MHz PLL ÷ integer`:
```
  FCLK = 1500 MHz / N   (N integer)   and   clk_x2 = 2 × clk_main  (exact)
  ⇒  93.75 = 1500/16 ,  187.5 = 1500/8   (N=16, N=8 → ratio exactly 2:1)
  90 MHz → 1500/90 = 16.667 (non-integer) → impossible.
  93.75 is the highest exact 2:1-capable pair just below 100 MHz (timing cushion).
```
(In the BD we *request* 90/180; the Zynq rounds up to the achievable 93.75/187.5.)

### A.2 The two modifications — clock-tree before/after

BEFORE — two separate PS FCLKs feed ztachip (independent roots):
```
   1500 MHz IO-PLL
        ├─ ÷16 ─► FCLK_CLK0 (93.75) ─► clk_main      ┐ two INDEPENDENT clock roots
        └─ ÷8  ─► FCLK_CLK1 (187.5) ─► clk_x2_main   ┘ (split hidden inside PS7)
              cross-clock paths 93.75→187.5  ⚠ 3 HOLD VIOLATIONS (timing NOT closed)
```

AFTER — one PS FCLK → MMCM generates both (common root):
```
   1500 MHz IO-PLL ─ ÷16 ─► FCLK_CLK0 (93.75)  [ONE clock out of the PS]
        │  + jitter constraint refined 0.320 → 0.100 ns
        ▼
     ┌────────── MMCM (Clocking Wizard) — ONE common root ──────────┐
     │   clk_out1 = 93.75 MHz          clk_out2 = 187.5 (×2 exact)  │
     └────────┬───────────────────────────────┬─────────────────────┘
            clk_main                       clk_x2_main
              └──── cross-clock paths ─────────┘
              ✓ common root → clock-pessimism removal → WNS 0.000 / WHS +0.009
```

### A.3 How Vivado treats each clock (STA view)

Key terms: the **common path** = the clock segment SHARED by both clocks (uncertainty
there cancels). The **tails** = the unique segments AFTER the split, from the split node to
each flop's own clock pin (only their uncertainty counts). **CRPR** (Clock Reconvergence
Pessimism Removal, a.k.a. CPPR) = the credit Vivado adds back for double-counted pessimism
on the common path.

CASE 1 — BEFORE (two FCLK pins, no common node, FULL pessimism):
```
   FCLK0 pin            FCLK1 pin           (split hidden in PS7; fabric sees 2 doors)
      │                    │
  CLOCK PATH A         CLOCK PATH B
  (whole path ✗        (whole path ✗
   assume SLOW)         assume FAST)        ← worst case on BOTH full paths
      ▼                    ▼
   ┌──────┐            ┌──────┐
   │ FF1  │ launch     │ FF2  │ capture
   └──┬───┘            └───▲──┘
      │  Q ─► logic ─► D   │   (data path)
      └────────────────────┘
   No shared node → CRPR ≈ 0 → full uncertainty → 3 HOLD VIOLATIONS → FAIL
```

CASE 2 — AFTER (one MMCM, visible common node, pessimism removed):
```
            FCLK0 pin (one)
               │
       ┌───────▼────────┐
       │  COMMON PATH    │  ◄ shared (FCLK route + MMCM input); uncertainty CANCELS
       │  ✓ CRPR credit  │
       └───────┬────────┘
            [ MMCM ]
       ┌───────┴────────┐
   clk_out1 (93.75)  clk_out2 (187.5)
       │                 │
    TAIL A (short)    TAIL B (short)   ◄ only these ✗ count
       ▼                 ▼
   ┌──────┐          ┌──────┐
   │ FF1  │ launch   │ FF2  │ capture
   └──┬───┘          └───▲──┘
      │  Q ─► logic ─► D  │
      └───────────────────┘
   Shared node → big CRPR → only tail uncertainty counts → HOLD CLOSES → PASS
```

### A.4 The equations (slide-ready)
```
  Setup slack = Data Required Time − Data Arrival Time
  Hold  slack = Data Arrival Time − Data Required Time

  (hold) Data Arrival  = T_launch_clk + T_cq + T_logic(min)
         Data Required = T_capture_clk + T_hold + T_uncertainty − CRPR
   ⇒ bigger CRPR (common path) RAISES hold slack.

  Clock uncertainty combines jitter/phase in quadrature (root-sum-square):
     T_uncertainty = √(PE² + DJ² + SJ²)
                   = √(0.120² + 0.159² + 0.071²) ≈ 0.207 ns   (real numbers)

  Worst hold path:
     real margin            = +0.197 ns
     uncertainty (default)  =  0.207 ns  → hold = 0.197−0.207 = −0.010 ns  ✗ FAIL
     after jitter refine (DJ 0.320→0.100)→ uncertainty < 0.197 → +0.009 ns  ✓ PASS
```
Takeaway for the defense: the hold failure was caused ENTIRELY by clock uncertainty (not a
real logic-delay problem). We fixed it by giving the clocks a common root (MMCM → CRPR
credit) and refining jitter — NOT by slowing the design.

### A.5b Hold slack explained term-by-term
A **hold violation** = new data races through the logic and arrives at the capture flop
*too early*, changing its input during the hold window so it latches new (corrupt) data
instead of the old value. Hold is checked on the **SAME clock edge** at both flops.
```
  Hold slack = Data Arrival Time − Data Required Time

  Data Arrival  = T_launch_clk + T_cq(min)  + T_logic(min)      ← fastest delays
  Data Required = T_capture_clk + T_hold + T_uncertainty − CRPR

  ⇒ Hold slack = T_cq(min) + T_logic(min) − T_hold − skew − T_uncertainty + CRPR
                 └────────── "real" data margin ──────────┘
     where  skew = T_capture_clk − T_launch_clk
```
Term meanings: `T_launch_clk`/`T_capture_clk` = clock insertion delay to each flop;
`T_cq(min)` = fastest launch clock-to-Q; `T_logic(min)` = fastest logic path; `T_hold` =
capture flop requirement; `T_uncertainty` = jitter+phase (stricter); `CRPR` = common-path
credit (looser).

TWO KEY INSIGHTS:
1. The clock PERIOD does NOT appear (same-edge check) ⇒ **hold CANNOT be fixed by slowing
   the clock.** This is why the fix was MMCM (CRPR) + jitter, never a frequency cut.
2. Positive **skew** subtracts directly from hold slack; two unrelated FCLK trees have large
   uncertain skew → fail; the MMCM common root shrinks effective skew + adds CRPR → pass.

Illustrative numbers (≈ the real path): real margin = 0.10+0.08−0.05−0.04 = +0.19 ns;
uncertainty 0.207 ns → slack −0.017 ns (FAIL); after jitter refine uncertainty ~0.18 →
+0.01 ns (PASS). (Real project: +0.197 margin, −0.010 → +0.009.)

### A.5 Resources
- "setup and hold time explained"; "static timing analysis slack WNS WHS"
- "clock reconvergence pessimism removal CRPR" / "common clock path pessimism"
- Xilinx UG949 (UltraFast Design Methodology) — timing-closure / clocking section
- Xilinx "Clocking Wizard / MMCM" product guide (what an MMCM does)

### A.6 There were TWO distinct timing fixes (don't blur them)
People confuse these — they solved DIFFERENT problems, and the integer-divisor one came
FIRST, before the MMCM:
```
  1. Wrong pair (e.g. 100/200): 200 = 1500/7.5 is NOT an integer divisor → it snaps to
     187.5/214.3, so clk_x2 ≠ exactly 2×clk_main → ratio UNDEFINED, x2 logic samples wrong.
       FIX #1 (NO MMCM): choose 93.75/187.5 = 1500/16 & 1500/8 → exact 2:1 by integers.
  2. Exact 2:1 but two SEPARATE FCLK pins → 3 HOLD violations (no common root).
       FIX #2 (MMCM): one source → both clocks → common root → CRPR credit → hold OK.
  3. Residual −10 ps hold from clock uncertainty (jitter).
       FIX #3 (constraint only): set_input_jitter 0.320 → 0.100 ns → WNS 0.000 / WHS +0.009.
```
| Fix | Problem solved | MMCM? |
|-----|----------------|-------|
| #1 integer-divisor freq (93.75/187.5) | `clk_x2` not *exactly* 2×`clk_main` (undefined ratio) | No |
| #2 MMCM common root | exact ratio, but hold violations from independent roots | Yes |
| #3 jitter refinement | last −10 ps of hold (clock uncertainty) | constraint only |

### A.7 Zynq FCLK frequency grid — what you actually get
A Zynq FCLK is `FCLK = PLL_freq ÷ (DIVISOR0 × DIVISOR1)`, both 6-bit INTEGER dividers
(1–63), no fractional divider. So only a DISCRETE grid of frequencies exists. When you type
a target (`PCW_FPGA0_PERIPHERAL_FREQMHZ`), Vivado SNAPS it to the nearest `PLL/(d0·d1)` and
reports the ACTUAL: `actual = PLL / round(PLL/target)`.
```
  target 100 → 1500/15  = 100.00  ✅ exact      target 90  → 1500/16 = 93.75  (snapped up)
  target 125 → 1500/12  = 125.00  ✅ exact      target 110 → 1500/14 = 107.14 (snapped)
```
So typing 90/180 actually ran the chip at 93.75/187.5. CONSEQUENCES: (1) software must use
the ACTUAL value — `config.vhd/main_clock_c` MUST equal the real FCLK0, else UART baud is
garbled and timers are off; (2) in the old two-FCLK design each clock snaps independently, so
an exact 2× ratio was only obtained by *choosing* a pair that both snap cleanly to 1500/16 &
1500/8. The MMCM has a richer `×M/D` (incl. fractional) divider → finer resolution AND a ratio
exact by construction (both outputs derived from one M/D base).

### A.8 "How are they two independent roots if both come from the 1500 MHz PLL?"
Electrically they do share the PLL — but that split happens INSIDE the PS7 hard block, which
Vivado does not time-analyze internally. Vivado's fabric STA sees only the two OUTPUT pins
(FCLK0, FCLK1) as two separate entry points, and their fabric clock trees never touch → no
common node it can credit. The MMCM moves the split INTO the fabric, at a node Vivado can
trace → common node → CRPR. **How does Vivado KNOW one vs two sources?** Not from frequency or
declarations — it physically traces the routed clock-tree netlist from each source pin to
each flop's clock pin and checks whether the launch and capture clock paths pass through the
SAME physical node. Shared node → remove double-counted pessimism (CRPR) up to it; no shared
node → full pessimism. It's purely the wiring topology Vivado can see.
```
```
