# Graduation Project — Master Reference
## Running the SmolLM2 Language Model on the ztachip AI Accelerator (Xilinx Zynq ZC702 FPGA)

> **Who this is for:** every team member, including those new to the project. It assumes **no
> prior knowledge** of the project and explains the hardware, the software, the build/verify
> flow, and the **meaning of every number and parameter** we report. Read it top to bottom the
> first time; afterwards use the Table of Contents and the Glossary (§12) as a lookup.
>
> **Status:** Phase 1 is **complete** — the LLM runs on the board, the compute kernels are
> verified on silicon, and the design is characterized (proven memory-bandwidth-bound).
> Phase 2 (performance optimization) is planned (§11).
>
> This file supersedes and merges the older `PROJECT_WALKTHROUGH.md`, `PROJECT_STATUS.md`, and
> `bench/results/kernel_verification.md` / `comparison.md`. Those still exist for detail.

---

## Table of Contents
1. [One-page summary](#1-one-page-summary)
2. [Background — the concepts you need](#2-background--the-concepts-you-need)
3. [The hardware: ZC702 and the Zynq chip](#3-the-hardware-zc702-and-the-zynq-chip)
4. [ztachip: the AI accelerator](#4-ztachip-the-ai-accelerator)
5. [The LLM: SmolLM2 and the transformer flow](#5-the-llm-smollm2-and-the-transformer-flow)
6. [The port: from Arty to ZC702](#6-the-port-from-arty-to-zc702)
7. [The build & bring-up flow — in the correct order](#7-the-build--bring-up-flow--in-the-correct-order)
8. [Memory map — every address explained](#8-memory-map--every-address-explained)
9. [The engineering journey — problems we solved](#9-the-engineering-journey--problems-we-solved)
10. [Performance characterization — every number explained](#10-performance-characterization--every-number-explained)
11. [Phase 2 — performance optimization plan](#11-phase-2--performance-optimization-plan)
12. [Glossary — terms and parameters](#12-glossary--terms-and-parameters)
13. [File & script reference](#13-file--script-reference)
14. [Appendix A — clocking & timing deep dive](#appendix-a--clocking--timing-deep-dive)

---

## 1. One-page summary

We took an **open-source AI accelerator chip design** (called **ztachip**), loaded it onto a
real **FPGA development board** (the **ZC702**), and made it run a real **Large Language Model**
(**SmolLM2**) — so you can type a question and the hardware generates an answer.

Three things were achieved and verified, all on real silicon:

| Achievement | What it means | The headline number |
|---|---|---|
| **It runs** | A chatbot answers prompts on the board | **4.13 tokens/second** (135M model) |
| **The kernels are correct** | Each math primitive matches a reference, on-chip | **11/11 kernels pass, 0 errors** |
| **We know its limit** | The speed is set by memory bandwidth, not math | DDR-bound at **~430–530 MB/s** |

**The one-sentence technical story:** *On this FPGA port, ztachip correctly executes every LLM
compute kernel, and the LLM's speed is limited entirely by how fast model weights stream out of
DDR memory — proven by holding the math fixed and varying only the data volume.*

The rest of this document explains each of these, and every number behind them.

---

## 2. Background — the concepts you need

If any of these terms are new, read this section first. Each is revisited in detail later.

- **FPGA (Field-Programmable Gate Array):** a chip whose digital circuit can be *reprogrammed*
  by software. You describe a circuit in a hardware language (VHDL/Verilog), the tools compile
  it into a **bitstream** (a `.bit` file), and you load that file into the FPGA — the FPGA then
  *becomes* that circuit. *Analogy: LEGO you can rebuild into any shape, vs. a fixed CPU which
  is a finished building.*
- **Bitstream (`.bit`):** the compiled hardware circuit. **Building** it (compiling from VHDL)
  takes hours in Vivado; **programming/loading** it onto the chip takes ~5 seconds. We rarely
  rebuild; we mostly just load the already-built `.bit`.
- **VexRiscv:** a small **RISC-V CPU** built *inside* the FPGA fabric. It runs our ordinary C/C++
  program (the "firmware") — loading the model, the tokenizer, control logic. It is the
  *manager*; it does not do the heavy math itself.
- **ztachip:** the **AI math accelerator** (the muscle) built inside the FPGA next to VexRiscv.
  It does the massive matrix math an AI model needs, far faster than a plain CPU.
- **Firmware:** the compiled C/C++ program that VexRiscv runs. We build it on the PC and load it
  into the board's memory.
- **LLM (Large Language Model):** an AI model that predicts text one piece at a time. Ours is
  **SmolLM2** — "Smol" = small. 135 million (or 360 million) parameters; tiny next to ChatGPT.
- **Token:** a word-piece. The model emits one token per "forward pass". *"unbelievable" might be
  3 tokens: "un", "believ", "able".*
- **Forward pass:** one complete run through the network to produce one token.
- **Quantization:** compressing each weight to fewer bits to save memory. **Q4** = 4 bits/weight
  (INT4); **Q8** = 8 bits/weight (INT8). Smaller bits = less memory = faster here, at some
  accuracy cost.
- **DDR:** the large (1 GB) but relatively slow external memory that holds the model weights.
- **JTAG:** a debug cable+protocol we use to load memory and talk to the board from the PC.
- **Memory-bound:** performance limited by memory speed, not compute speed (our key finding).

---

## 3. The hardware: ZC702 and the Zynq chip

The **ZC702** is a development board built around a **Xilinx Zynq XC7Z020** chip. The Zynq is
special: it has **two halves on one chip**.

| Half | Name | What it is | How WE use it |
|------|------|-----------|----------------|
| **PS** | Processing System | A hard, fixed **ARM Cortex-A9** dual-core CPU + the DDR memory controller | ONLY for DDR memory + clock generation |
| **PL** | Programmable Logic | The actual **FPGA fabric** (the reprogrammable part) | We put **VexRiscv + ztachip** here |

**Key design decision (state this in any presentation):** we deliberately keep our whole
accelerator (VexRiscv CPU + ztachip) inside the **PL (FPGA)**. The ARM **PS** does *not* run our
program — it acts like a "power supply + memory landlord": it boots, sets up the DDR and the
clocks, then gets out of the way. This keeps the design portable (not tied to ARM) and matches
the original ztachip design, which assumes a soft RISC-V CPU.

**Numbers that describe the chip and our usage** (from the synthesis report):

| Resource | Used | Available | Util % | Meaning |
|---|---|---|---|---|
| Slice LUTs | 47,187 | 53,200 | 88.7% | logic gates used — "how full the FPGA is" |
| Slice Registers | 57,828 | 106,400 | 54.3% | flip-flops (state storage) |
| Block RAM | 128 | 140 | 91.4% | on-chip fast memory blocks |
| DSPs | 82 | 220 | 37.3% | hardware multipliers |

*Util % near 90% (LUTs, BRAM) means the design nearly fills this small FPGA — that's why we use
the *small* ztachip configuration and a *small* LLM.*

---

## 4. ztachip: the AI accelerator

ztachip is an **open-source, multicore RISC-V AI accelerator** for edge devices. Its whole job
is the **massive multiply-add math** AI needs, faster than a plain CPU.

### 4.1 The building blocks (the architecture)

```
        DDR memory (holds the model weights: 147 MB / 200 MB / 308 MB)
              │  (AXI bus — the data highway)
   ┌──────────┴───────────────────────────────────────┐
   │                  ztachip                          │
   │   VexRiscv CPU ── runs our C++ firmware (manager) │
   │   Mcore        ── scheduler ("conductor")         │
   │   Dataplane    ── streams data+instructions        │
   │   Scratch-pad SRAM ── small, very fast memory     │
   │   Tensor Engine = many Pcores (the muscle)        │
   │       each Pcore: Scalar ALU + Vector ALU,        │
   │       multiple threads, private memory            │
   │   FPU          ── floating-point unit (vector)    │
   └───────────────────────────────────────────────────┘
```

- **VexRiscv** — the *foreman*: runs firmware, does no heavy math.
- **Mcore** — decides which math task runs next (the *conductor*).
- **Dataplane** — moves the right data to the math units at the right time (the *conveyor belt*).
- **Scratch-pad SRAM** — small fast memory next to the math units (DDR is big-but-slow; SRAM is
  small-but-fast).
- **Tensor Engine = Pcores** — the *workers*: parallel processors that do matrix-multiply (the
  core of an LLM) like a systolic array.
- **FPU** — does the floating-point parts (with a vector mode for attention).

**Why an accelerator at all?** An LLM is billions of multiply-and-adds on matrices. A plain CPU
does a few at a time; the tensor engine does many in parallel. That parallelism is ztachip's
entire reason to exist.

### 4.2 The kernels (this matters for §7's verification)

A **kernel** is one specialized math operation implemented on ztachip. The LLM is built from a
handful of them. You will see these names again in the kernel-verification step:

| Kernel | What it computes | Where it's used in the LLM |
|---|---|---|
| `matmul_q4` / `matmul_q8` | INT4 / INT8 **matrix multiply** | the bulk of every layer (Q/K/V, FFN, output) |
| `rms` | RMSNorm (a normalization) | start of each layer |
| `rope` | rotary position embedding | tells the model token *position* |
| `softmax` | turns scores into probabilities | attention + final sampling |
| `residual` | adds skip-connections | after attention and FFN |
| `SwiGLU` | the FFN activation function | feed-forward block |
| `sine` / `cosine` | trig tables | building RoPE frequencies |
| `quantize` | compress weights to INT4/INT8 | preparing data for matmul |
| `k_max` | top-K selection | sampling the next token |

---

## 5. The LLM: SmolLM2 and the transformer flow

- **SmolLM2** is a **LLaMA-style transformer** — same architecture family as Meta's LLaMA, so
  ztachip's existing LLM code (`SW/apps/llm/`) implements the standard transformer steps.
- We run two sizes: **135M** (135 million parameters) and **360M** (360 million).
- The model file uses ztachip's own format, **`.ZUF`** (converted from the standard GGUF format).

### 5.1 The model configuration parameters (what the numbers mean)

When the firmware opens a model, it reads these config values from the file. Here is what each
means and the values for our two models:

| Parameter | 135M | 360M | Meaning |
|---|---|---|---|
| `embedding_length` (dim) | 576 | 960 | width of each token's vector |
| `feed_forward_length` (hidden) | 1536 | 2560 | width inside the FFN block |
| `block_count` (layers) | 30 | 32 | number of transformer layers stacked |
| `head_count` | 9 | 15 | attention heads |
| `head_count_kv` | 3 | 5 | key/value heads (fewer = "grouped-query attention") |
| `kv_dim` | 192 | 320 | size of the key/value vectors (= head_count_kv × head_size) |
| `head_size` | 64 | 64 | size of one attention head |
| `vocab_size` | 49,152 | 49,152 | number of distinct tokens it can output |
| `context_length` | 8192 | 8192 | max tokens it can "remember" at once |

*These are read at boot; the firmware caps are `MAX_NLAYERS=32` and `MAX_LLM_SEQ_LEN=1024`, so
360M (32 layers) sits exactly at the layer limit — a reason it's the "riskiest" model to run.*

### 5.2 What "running the LLM" does (per output token)

For each token, the model does one **forward pass** through all layers. Per layer:

1. **RMSNorm** — normalize the activation vector (keep numbers sane).
2. **Q, K, V matmuls** — multiply by the Query/Key/Value weight matrices.
3. **RoPE** — add positional information.
4. **Attention** — each token "looks at" earlier tokens (softmax over scores).
5. **Output matmul** — combine the attention result.
6. **Feed-forward (FFN)** — two big matmuls + SwiGLU activation + a final matmul (the biggest
   compute chunk).
7. After all layers: a **final matmul** against the vocabulary → **logits** (a score per possible
   next token).
8. **Sampling** — pick the next token from those scores.

**Why it's memory-bound (the key insight, proven in §10):** to produce *each* token, the hardware
must read *all* the model's weights out of DDR. For the 135M Q4 model that's ~103 MB of reads
**per token**. The math units are fast; the bottleneck is **DDR bandwidth**. This is why every
optimization in Phase 2 targets memory, not more math units.

---

## 6. The port: from Arty to ZC702

ztachip's reference design targets the **Arty A7** board (a pure FPGA, no ARM). Our project
**ported** it to the **ZC702** (a Zynq, which has the ARM PS). This is the foundation step;
every later "wall" (§9) traces back to it.

| | Original: **Arty A7** | Our target: **ZC702** |
|---|---|---|
| FPGA part | `xc7a100t` (Artix-7, pure FPGA) | `xc7z020clg484-1` (Zynq-7020) |
| Hard ARM CPU? | none | yes (the PS) |
| DDR memory | external DDR3 via a soft "MIG" controller | PS owns DDR3; PL reaches it via `S_AXI_HP0` |
| Clocks | external oscillator + clock wizard | PS **FCLK** outputs (+ an MMCM we added) |
| Model load | over **Ethernet** (TFTP) | over **JTAG**, pre-loaded into DDR |

**Key insight:** the ztachip *accelerator itself* (Pcores, dataplane, FPU, VexRiscv) is **reused
essentially unchanged**. The port happens at the **platform-wrapper** layer — how the accelerator
gets DDR, clocks, and I/O. *Analogy: same engine, new car chassis — you redo the mounts, fuel
line, and wiring, but the engine block is identical.*

One config change worth knowing: **`exmem_data_width_c` was changed 128 → 64**, because the
Zynq's HP0 memory port is 64-bit (the Arty's MIG was 128-bit). This narrower memory path is part
of why bandwidth is limited — and widening it back is a Phase-2 idea (§11).

---

## 7. The build & bring-up flow — in the correct order

This is the **end-to-end procedure**, in the order it actually happens. Notice that **kernel
verification (Step 3) comes right after we program ztachip onto the FPGA, BEFORE we trust it with
the full LLM** — you verify the building blocks before relying on the whole machine.

```
 Step 0:  Build the bitstream (rarely — only if hardware changed; takes hours in Vivado)
 Step 1:  Power on + PS7 init   — ARM sets up DDR + clocks
 Step 2:  Program the FPGA      — UPLOAD ztachip (load the existing .bit; ~5 seconds, NO rebuild)
 Step 3:  VERIFY THE KERNELS    — run the on-silicon kernel self-test  ◄◄◄ (verify the hardware)
 Step 4:  Load the model        — JTAG-preload the .ZUF into DDR (slow; minutes)
 Step 5:  Load firmware + boot  — VexRiscv runs the chatbot
 Step 6:  Talk to it / benchmark — via the DDR mailbox console over JTAG
```

### Step 0 — Build the bitstream (only if hardware changed)
The `.bit` is already built and committed. You only rebuild if you change the VHDL/Verilog
(e.g., the Phase-2 memory changes). Rebuilding runs synthesis + place-and-route + timing closure
in Vivado (hours). **Day-to-day you never do this** — you just *load* the existing `.bit`.

### Step 1 — Power on + PS7 init
The ARM PS boots and runs `ps7_init` (configures the DDR controller and the clocks). After this,
DDR is alive and the PL has its clock signals.
> **IMPORTANT operational note:** the board boots our firmware reliably **only on the first
> bring-up after a power-up**. Re-running a bring-up on an already-live board re-inits the PS and
> can leave it in a stale state where the firmware silently won't boot. **Power-cycle the board
> (off ~5 s, on) before each fresh run.**

### Step 2 — Program the FPGA (upload ztachip)
We load the existing `main_zc702.bit` into the PL. This **uploads the ztachip + VexRiscv circuit**
onto the chip. It takes ~5 seconds. *(This is "programming," not "rebuilding" — no Vivado, no
hours.)* After this the accelerator hardware exists on the chip but hasn't been exercised yet.

### Step 3 — VERIFY THE KERNELS (on-silicon self-test)
**This is the first thing we do after uploading ztachip: confirm the compute hardware is correct
before trusting it with the full model.**

- **What it is:** a small "kernel-test" firmware runs each ztachip kernel and compares its output,
  element by element, against a **reference C implementation** (`SW/apps/llm/reference/llm_ref.c`)
  that we know is correct. No model is loaded — the tests generate their own input data.
- **How to run it:** power-cycle, then `bash HW/examples/ZC702/run_kernel_test.sh`. It does the
  full bring-up, loads the lean 8.8 MB test firmware over JTAG (~2.5 min), runs all kernels, and
  saves results to `bench/results/kernel_selftest.log`.
- **Why on silicon and not in simulation:** the heavy kernels — especially `matmul_q4` /
  `matmul_q8` (the INT4/INT8 matrix-multiply engine that does the bulk of every layer) — take
  **hours** in RTL simulation but **seconds** on the chip. Silicon is the only practical way to
  verify them end-to-end.

**The result — and what every number means:**

Each line reads `<KERNEL> ok=N bad=M` (or `fail=M`):
- **`ok=N`** — the number of output elements that **matched** the reference within tolerance.
- **`bad`/`fail=M`** — the number of **mismatches**. **We want this to be 0.**
- The size of `N` just reflects how big that kernel's test vector is (e.g. `sine` checks 14,400
  points; `matmul_q4` checks 1,536 output elements). A bigger `N` means a more thorough check.

| # | Kernel | Result | What it verifies |
|---|---|---|---|
| 1 | RESIDUAL | `ok=1152 bad=0` | skip-connection add |
| 2 | SWIGLU | `ok=1536 bad=0` | FFN activation |
| 3 | RMS | `ok=1152 bad=0` | RMSNorm |
| 4 | ROPE | `ok=384 bad=0` | positional encoding |
| 5 | SOFTMAX | `ok=512 bad=0` | attention probabilities |
| 6 | K_MAX | `ok=1 fail=0` | top-K sampling |
| 7 | COSINE | `ok=14400 bad=0` | RoPE trig table |
| 8 | SINE | `ok=14400 bad=0` | RoPE trig table |
| 9 | QUANTIZE | `ok=2048 bad=0` | weight compression |
| 10 | **MATMUL_Q4** | `ok=1536 fail=0` | **INT4 matrix multiply (core)** |
| 11 | **MATMUL_Q8** | `ok=1536 fail=0` | **INT8 matrix multiply (core)** |

**Outcome: 11 / 11 kernels pass, ~38,657 element comparisons, 0 mismatches.** This proves the
ztachip compute datapath is mathematically faithful to the reference on real hardware. Only after
this do we trust the chip with the full LLM.

### Step 4 — Load the model into DDR
We copy the model file (`.ZUF`) into DDR at address `0x10000000` over JTAG. This is **slow**
(~65 KB/s over the JTAG cable), so it takes minutes:

| Model | File size | Approx. JTAG load time |
|---|---|---|
| 135M Q4 | 147 MB | ~38 min |
| 135M Q8 | 200 MB | ~52 min |
| 360M Q4 | 308 MB | ~88 min |

*(Why so slow: the JTAG cable is transaction-latency limited; we tried raising its clock and
halting the ARM — neither helped. A future fix is loading from an SD card via the PS.)*

### Step 5 — Load firmware + boot
We load the firmware in **two pieces** (see §8 for why): a tiny stub at `0x4000` and the main
image at `0x100000`. We clear the mailbox, then release VexRiscv from reset. The firmware boots,
opens the model, builds the tokenizer, and prints `I am a chatbot` and a `>` prompt.

### Step 6 — Talk to it / benchmark
There is **no keyboard or screen** on the board for our CPU, so input/output travels through a
small message area in DDR called the **mailbox / console** (§8). The PC reads it over JTAG and
shows you the `>`; you type, and your text goes back through the mailbox. The benchmark
(`run_model.sh`) automates this with 30 fixed prompts.

---

## 8. Memory map — every address explained

Think of all memory as **one long street**; every byte has a house-number (a hex address). On the
Zynq the street runs `0x00000000`–`0x3FFFFFFF` (**1 GB of DDR**), but the low end is reserved.

```
  ADDRESS RANGE             WHAT LIVES THERE                       SIZE
  ─────────────────────────────────────────────────────────────────────
  0x00000000 – 0x00003FFF   PL BRAM (TCM): stack / scratch         16 KB
  0x00004000 – 0x0003FFFF   PS OCM (on-chip RAM, mapped LOW)      ~240 KB
  0x00040000 – 0x000FFFFF   ⛔ RESERVED GAP — JTAG cannot write   ~768 KB
  0x00100000 – 0x3FFFFFFF   PS DDR (the big 1 GB main memory)      ~1 GB
  ─────────────────────────────────────────────────────────────────────
  Chosen plots inside DDR:
  0x00100000   firmware main image (main.bin)   first clean address above the gap
  0x10000000   model file (.ZUF)                256 MB mark — clear of the heap
  0x30000000   mailbox / console                768 MB mark — fits big models below it
```

**Why each address (the reasons matter):**
- **`0x00004000` (boot stub):** VexRiscv's reset vector is *hardwired* to `0x4000`, so the very
  first instruction MUST live there. It's a tiny stub (`vector.bin`, 532 bytes) that jumps to the
  real program in DDR. *Analogy: the law says everyone enters by this one front door; inside is a
  sign "real office at 0x100000".*
- **`0x00040000–0x000FFFFF` (reserved gap):** the Zynq cannot write here (a side-effect of how it
  can remap OCM to address 0). This is *why* the firmware is **split** into two files that
  straddle the gap — nothing ever lands inside it.
- **`0x00100000` (firmware):** the first clean DDR address above the gap.
- **`0x10000000` (model):** parked at the 256 MB mark because the firmware **heap is ~200 MB**
  (it grows during a run); the model sits far above so the growing heap never collides with it.
- **`0x30000000` (mailbox):** moved here from `0x20000000` so that models up to ~512 MB fit in the
  region below it (needed for the 308 MB 360M model). Sub-layout: a "magic" word + ring-buffer
  pointers + two 4 KB ring buffers (one chip→PC, one PC→chip).

**The two "magic" markers** (sanity checks the host looks for over JTAG):
- model magic `0x4341545A` = ASCII `"ZTAC"` at `0x10000000` → proves the model survived in DDR
  (so we can skip a slow reload).
- mailbox magic `0x5A544348` = ASCII `"ZTCH"` at `0x30000000` → proves the firmware booted and
  the console is alive. *(A magic number = a known value at a known address; reading it back =
  a password handshake.)*

---

## 9. The engineering journey — problems we solved

This is the most valuable part for a presentation: the *story* of real engineering. Each item is
"we hit a wall → why → the fix."

### 9.1 Clocking — making the FPGA timing-clean
ztachip needs a `clk_x2` that is **exactly 2× the main clock** (data is stored in two words and
clocked out at double rate). The Zynq can only divide its 1500 MHz PLL by integers, so we chose
**93.75 MHz and 187.5 MHz** (= 1500/16 and 1500/8 — an exact 2:1 pair just below 100 MHz). We
also added an **MMCM** (a clock generator) so both clocks share one root, which let the timing
"close" cleanly (no hold violations). *Full detail in Appendix A.*
> **What "93.75 MHz" means:** the VexRiscv + ztachip run at 93.75 million cycles per second. (A
> modern GPU runs ~1000+ MHz — ~10× faster clock — which is why raw speed isn't our strong suit;
> efficiency-per-watt is.)

### 9.2 The model format — `.ZUF`
ztachip wants the model as `.ZUF`, not raw GGUF. The converter (`quant.cpp`) needs an **F16/F32
GGUF** input (not an already-quantized one) and outputs Q4 or Q8. *(An earlier broken 68 KB stub
file caused silent failures until we regenerated a valid file.)*

### 9.3 No Ethernet → load the model over JTAG
The original design downloads the model over Ethernet; we stubbed Ethernet out, so we **pre-load
the model into DDR over JTAG** instead. This is why a cold start takes ~40–90 minutes.

### 9.4 The boot chain & the "low-1 MB gap"
The Zynq reserves `0x40000–0xFFFFF`, so we **split** the firmware into a tiny vector stub at
`0x4000` (OCM) + the main image at `0x100000` (DDR), and map all OCM low. After this, the firmware
booted and read the model. *(See §8.)*

### 9.5 No usable UART → the DDR mailbox console
The ZC702 has no PL serial port we can reach, so we built a **DDR mailbox**: a pair of ring
buffers in memory that the chip writes/reads and the PC reads/writes over JTAG. That is our chat
window. We also added retry logic (`safe_mrd`/`safe_mwr`) so a flaky JTAG read doesn't kill the
session.

### 9.6 THE BIG ONE — the silent VexRiscv misaligned-load trap
The headline bug and best story:
- **Symptom:** firmware printed "Model found in DDR" then **silently froze** — no crash, no error.
- **Cause:** VexRiscv has **no hardware support for *misaligned* word loads** and traps silently
  when one happens. The C library's `strcmp` reads memory a full 32-bit word at a time for speed,
  but the model's text strings sit at **odd addresses** in DDR → unaligned word load → silent trap.
- **Fix:** replace those library string compares with **byte-by-byte compares** (always aligned)
  in the model loader and tokenizer. This single fix unblocked the entire model load and is why
  the LLM finally ran.
- **The rule we now follow:** never use a word-optimized library string function on raw model
  bytes in DDR.

### 9.7 Making it usable & measurable
- **Runaway responses:** a tiny LLM often loops; we added a **hard cap** (160 tokens) so it stops.
- **Dead on-chip timers:** the original bitstream's timers read 0 (the data never reached the
  CPU). We found and fixed a 1-line APB read bug (a "ready" signal was tied so all internal reads
  returned 0), which revived the timer **and** the new performance-monitor (PMU). With that fixed
  we can measure real on-chip activity (§10).

---

## 10. Performance characterization — every number explained

This section is the heart of the project's measurement work. **Read §10.1 first — it defines
every metric** — then the results in §10.2 onward will be fully meaningful.

### 10.1 What every metric means

| Metric | Units | Definition / how to read it |
|---|---|---|
| **tokens/second (tok/s)** | tokens ÷ second | how fast the model generates words-pieces. **Higher = faster.** Our headline speed number. |
| **mean / median** | tok/s | average and middle of the 30 runs. Median resists outliers. |
| **sd (standard deviation)** | tok/s | run-to-run *spread*. **Small sd = very consistent.** A near-zero sd is a fingerprint of a hard bottleneck. |
| **min / max** | tok/s | slowest and fastest single run. |
| **gen tokens** | tokens | how many tokens the answer contained (we cap at 160; longer prompts can hit 513 if they ramble). |
| **TTFT (time to first token)** | seconds | delay before the *first* word appears (the model must read the whole prompt first). Also called "prefill". |
| **wall time** | seconds | total time for one prompt's answer (TTFT + generation). |
| **bytes/token** | bytes (we show MB) | how many bytes of weights are read from DDR to make ONE token. **This is the "cost" of a token.** |
| **DDR read (ddr_rd_mbs)** | MB/s | the actual rate the memory read engine delivered data. |
| **rd_active** | % | fraction of time the DDR read engine was busy reading. High = the read path is the bottleneck. |
| **rd_stall** | % | fraction of time the read engine was *waiting* (idle). `rd_active + rd_stall ≈ 100%`. |
| **tok/s × bytes/token** | MB/s | a derived number = the *effective delivered bandwidth*. If this is ~constant across very different models, the design is memory-bound (see §10.3). |

> **The single most important relationship:**
> `tokens/second  =  (delivered DDR bandwidth)  ÷  (bytes per token)`
> To go faster you either raise the top (bandwidth) or shrink the bottom (bytes/token).

### 10.2 The benchmark methodology

We ran the **same 30 prompts** through each model. The 30 prompts span 6 categories (Math,
Science, Geography, History, Engineering, General) — 5 each — to avoid topic bias. Timing is the
host wall-clock (valid because a capped 160-token answer fits the 4 KB mailbox, so the firmware
never waits on the slow JTAG link → measured time ≈ real compute time). Memory traffic numbers
come from the on-chip **PMU** (performance-monitor) counters.

### 10.3 Results — the three models

| Model | What differs | tok/s (mean) | median | sd | TTFT | bytes/token | DDR read | rd_active | rd_stall |
|---|---|---|---|---|---|---|---|---|---|
| **135M Q4** *(repo default)* | baseline | **4.13** | 4.21 | 0.29 | 5.2 s | 103 MB | 431 MB/s | 59% | 42% |
| **135M Q8** | same model, 8-bit weights | **3.34** | 3.38 | 0.16 | 6.7 s | 156 MB | 526 MB/s | 71% | 30% |
| **360M Q4** | bigger model, 4-bit weights | **1.90** | 1.89 | 0.04 | 12.0 s | 248 MB | 478 MB/s | 65% | 36% |

**How to read this table:**
- **Q4 is fastest** (4.13) because it reads the fewest bytes/token (103 MB).
- **Q8 is slower** (3.34) than Q4 *even though it's the same network* — only the weights are wider
  (8-bit vs 4-bit), so it moves ~1.5× the bytes.
- **360M is slowest** (1.90) because it's a bigger model → 248 MB/token.
- **360M's sd is tiny (0.04)** — every run is nearly identical. That extreme consistency is itself
  evidence of a hard memory ceiling (nothing left to vary).

### 10.4 The memory-bound proof (the core result)

The design is **memory-bound**: its speed is set by how many bytes are pulled from DDR per token,
not by how fast the math runs. We proved it **two independent ways**:

**Proof A — same network, different weight width (Q4 vs Q8).** These run the *identical* math; the
only change is Q8's weights are 8-bit (≈1.5× the bytes). Result: Q8 is **1.24× slower**. If the
chip were *compute*-bound they'd run at the *same* speed. They don't → memory is the limit.

**Proof B — same weight width, different model size (135M vs 360M, both Q4).** The 360M carries
**2.4× the bytes/token** and runs at **0.46× the speed** — speed falls almost exactly in step with
bytes moved.

**The clincher:** multiply `tok/s × bytes/token` for all three and you get a **flat 426–520 MB/s**:

| Model | tok/s × bytes/token (effective bandwidth) |
|---|---|
| 135M Q4 | 4.13 × 103 = **426 MB/s** |
| 135M Q8 | 3.34 × 156 = **520 MB/s** |
| 360M Q4 | 1.90 × 248 = **472 MB/s** |

Three very different models all hit the same memory ceiling. *(It's not a perfectly fixed constant:
Q8's wider, more regular reads stall less (30%) than Q4's 4-bit unpacking (42%), so Q8 squeezes
out a bit more raw bandwidth.)*

> **What this means for headroom:** delivered ~430–530 MB/s is only ~57–71% of even the 64-bit
> memory port's own ceiling (~750 MB/s at 93.75 MHz), and ~10% of the DDR3 chips' raw ~4 GB/s. So
> the bottleneck is the **on-chip memory path**, not the DRAM — which is exactly what Phase 2
> attacks (§11).

### 10.5 Answer quality (a secondary finding)

We graded all 30 answers from each model against the correct facts (2 pts good / 1 partial / 0
wrong, max 60):

| Model | Quality score / 60 | Notes |
|---|---|---|
| 135M Q4 | 24 | weakest; falls into repeat-loops |
| 135M Q8 | 28 | ≈ Q4 — *same network*, so this small gap is luck, not real |
| **360M Q4** | **40** | clearly best; only model to get the integral, fission-vs-fusion, etc. |

**Important nuance:** Q8 vs Q4 quality difference is **noise** (same network) — which is precisely
why we use that pair for the *speed* experiment, never a quality claim. Real quality comes from
*more parameters* (360M), at the cost of 2.2× the time per answer. And even 360M makes confident
factual errors — use a tiny model for structure/explanation, verify all facts.

### 10.6 External reference — Jetson TX1 (a teammate's GPU run)

| Platform | Model | tok/s |
|---|---|---|
| Jetson TX1 (GPU) | SmolLM2-135M Q4 | 14.92 |
| **ztachip ZC702 (FPGA)** | SmolLM2-135M Q4 | **4.13** |

The Jetson is ~3.6× faster — expected, since its GPU runs ~10× our clock and has far more memory
bandwidth. **The point of our project is not raw speed; it's efficiency on a low-end FPGA** — the
meaningful comparison is tokens-per-second-per-watt, which requires the power measurement that is
the one remaining open item (§11).

---

## 11. Phase 2 — performance optimization plan

Phase 1 (everything above) is done. **Phase 2 = make ztachip faster**, guided by the §10 numbers.

Because the design is memory-bound, we improve `tok/s` by **raising delivered bandwidth** or
**cutting bytes/token** — *not* by adding math units (they already idle 30–42% of the time).

### Track A — Raise delivered bandwidth (biggest lever; needs a bitstream rebuild)
- **A1. Run the memory port faster.** Today it runs at the 93.75 MHz main clock; the Zynq HP ports
  can run ~150–200 MHz → roughly **doubles** the ceiling. (Re-opens timing closure — Appendix A.)
- **A2. Widen the memory path 64 → 128 bits** (use 2 of the Zynq's 4 HP ports) → 2× bytes/cycle.
- **A3. Cut the 30–42% read stall** (more in-flight reads, deeper prefetch FIFO, longer bursts).

### Track B — Shrink bytes/token (firmware; fast to try)
- **B1. Compress the KV-cache (FP16 → INT8)** — halves the "conversation memory" traffic.
- **B2. Keep reused weights on-chip** (in scratch-pad SRAM) instead of re-reading them every token.
- **B3. Sub-4-bit / mixed quantization** on insensitive layers (trades quality — measure it).

### Track C — Overlap math and memory (bitstream)
- **C1. Prefetch the next layer's weights while computing the current one** (double-buffering) —
  directly turns the measured idle time into work.

### Track D — Keep measuring
- **D1. Per-kernel profiling** (which kernel dominates).
- **D2. PMBus rail power** → the **tokens-per-second-per-watt** headline + a roofline. *(Open item.)*

**Recommended order & target:** `D1 → A1 → A3 → C1 → A2 → B`. A1+A3+C1 could plausibly take
135M-Q4 from **4.13 → ~7–9 tok/s with no quality loss** (estimate, not yet measured). For *bigger*
models: raise the layer/sequence caps, manage the KV-cache, bounded by the 1 GB DDR ceiling.

---

## 12. Glossary — terms and parameters

**Hardware / platform**
- **FPGA** — a chip whose digital circuit you can reprogram.
- **PS / PL** — Zynq's hard ARM CPU side / the reprogrammable FPGA side.
- **ZC702 / XC7Z020** — our board / its Zynq chip.
- **Bitstream (.bit)** — the compiled circuit you load into the FPGA.
- **VexRiscv** — the small soft RISC-V CPU running our firmware.
- **ztachip** — the AI math accelerator (Pcores + FPU + dataplane).
- **Pcore** — one parallel math core in ztachip's tensor engine.
- **DDR** — the big (1 GB) but slow external memory holding the model.
- **OCM / TCM / BRAM** — small fast on-chip memories (boot stub / scratch).
- **JTAG / xsdb** — the debug cable + tool to load memory from the PC. (`xsdb` is the 2025.2 tool;
  the old name `xsct` no longer exists.)
- **MMCM** — a clock generator we added to make both clocks share one root.
- **AXI / HP0** — the data bus standard / the 64-bit Zynq port ztachip uses to reach DDR.
- **PMU** — performance-monitor unit; on-chip counters that measure DDR traffic, etc.

**Model / LLM**
- **Token** — a word-piece; the model emits one per forward pass.
- **Forward pass** — one full run through the network to produce one token.
- **Quantization (Q4/Q8 = INT4/INT8)** — 4-bit vs 8-bit weight compression.
- **Transformer / LLaMA-style** — the architecture family of SmolLM2.
- **Matmul / Attention / RMSNorm / RoPE / SwiGLU / softmax** — the kernels (§4.2).
- **Logits** — the per-token scores produced before sampling.
- **KV-cache** — stored keys/values of past tokens (grows with conversation length).

**Key numbers at a glance**
- **93.75 / 187.5 MHz** — the main clock and its exact 2× partner (= 1500/16 and 1500/8).
- **0x4000 / 0x100000 / 0x10000000 / 0x30000000** — boot stub / firmware / model / mailbox addresses.
- **147 / 200 / 308 MB** — file sizes of 135M-Q4 / 135M-Q8 / 360M-Q4 models.
- **4.13 / 3.34 / 1.90 tok/s** — measured speeds of those three models.
- **103 / 156 / 248 MB** — bytes read per token for those three.
- **~430–520 MB/s** — the memory bandwidth ceiling the design hits.
- **11/11, bad=0** — kernels verified on silicon, zero mismatches.
- **~38,657** — total element comparisons in the kernel self-test.
- **`ok=N` / `bad=N`** — matched / mismatched elements in a kernel test (want `bad=0`).
- **rd_active / rd_stall** — % of time the DDR read engine is busy / waiting.
- **sd** — run-to-run standard deviation (small = consistent = memory-bound signature).
- **TTFT** — time to first token (prompt-reading delay).

---

## 13. File & script reference

All paths under `HW/examples/ZC702/` unless noted. **Run shell scripts as `bash <path>`.**

| Script / file | What it does |
|---|---|
| `run_kernel_test.sh` | **Step 3** — on-silicon kernel self-test (no model). Output → `bench/results/kernel_selftest.log`. |
| `board_kernel_test.tcl` | the xsdb script behind the kernel test (bring-up + load test fw + capture). |
| `fw_kerneltest/` | the kernel-test firmware (built with `make ... KERNEL_TEST=yes`). |
| `fw_llm/` | the saved chatbot firmware (so the test build never clobbers it). |
| `run_board_day.sh` / `board_day_run.tcl` | full cold bring-up: program bitstream + load model + firmware + open the chat console. |
| `run_resume_fw.sh` / `board_resume_fw.tcl` | re-load firmware + open console when the model is already in DDR (skips the slow model reload). |
| `run_model.sh <q4\|q8\|360m>` | benchmark ONE model (30 prompts) → `bench/results/results_<tag>.csv`. |
| `bench/summarize.py` | aggregate all `results_*.csv` → `bench/results/comparison.md`. |
| `bench/results/kernel_verification.md` | the kernel-test write-up. |
| `bench/results/comparison.md` | the three-model benchmark report. |
| `SW/rebuild_fw.sh` (in `SW/`) | rebuild the chatbot firmware → `build/vector.bin` + `build/main.bin`. |
| `SW/src/main.cpp` | firmware entry; build modes selected by `LLM_TEST` / `KERNEL_TEST` / `UNIT_TEST`. |
| `models/*.ZUF` | the model files (Q4 / Q8 / 360M). |

**Build modes (in `SW/makefile`):** `LLM_TEST=yes` → chatbot (default); `KERNEL_TEST=yes` → the
lean kernel self-test; `UNIT_TEST=yes` → full vision+LLM test suite (large, slow — not used here).

**Golden rule for board runs:** **power-cycle the board before each fresh bring-up.**

---

## Appendix A — clocking & timing deep dive

*(For the hardware-curious; skippable on a first read.)*

### A.1 Why the clock is pinned to 93.75 / 187.5 MHz
ztachip needs `clk_x2 = exactly 2 × clk_main`. Zynq FCLKs are `1500 MHz PLL ÷ integer`, so:
```
  93.75 = 1500/16 ,  187.5 = 1500/8   (ratio exactly 2:1 by integer divisors)
  90 MHz → 1500/90 = 16.667 (non-integer) → impossible; the chip snaps to 93.75.
```
93.75 is the highest exact-2:1 pair just below 100 MHz (a small timing cushion).

### A.2 The two clocks → one MMCM
Originally the two clocks came from two *separate* PS outputs (independent roots), which caused
**3 hold-timing violations**. We fed **one** PS clock into an **MMCM** that generates both — now
they share a common root, the timing tool can cancel double-counted pessimism ("CRPR"), and after
a small jitter-constraint tweak the design closed cleanly: **WNS 0.000 ns, WHS +0.009 ns**.

### A.3 What "timing closed" means
- **Setup/Hold slack** — margins that say data arrives neither too late (setup) nor too early
  (hold) for each flip-flop. **Positive slack = OK.** Our final hold slack is +0.009 ns (just
  passing) and setup slack 0.000 ns (exactly meeting) — i.e., the circuit is reliable at 93.75 MHz.
- **A key subtlety:** the hold problem was caused *entirely by clock uncertainty*, not by slow
  logic — which is why the fix was a common clock root (MMCM) + jitter tuning, **not** slowing the
  clock. (Hold violations can't be fixed by slowing down, because hold is checked on the same
  clock edge at both flip-flops.)

> When Phase 2 raises the memory-port clock (A1 in §11), this timing-closure work re-opens — budget
> for it.

---

*End of master reference. Source documents (kept for detail): `PROJECT_WALKTHROUGH.md`,
`PROJECT_STATUS.md`, `bench/results/kernel_verification.md`, `bench/results/comparison.md`.*
*Questions: Eslam Elsayed — eslam.elwehedy0@gmail.com.*
