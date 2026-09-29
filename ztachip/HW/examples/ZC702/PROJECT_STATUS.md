# ZC702 Port — Project Status & Handoff Document
# Graduation Project: Running LLM on ztachip FPGA Accelerator
# Last updated: 2026-06-22 (Phase 1 COMPLETE — LLM running + characterized; Phase 2 plan added)

> NOTE: The newest progress is at the top (Phase 1 done + Phase 2 plan). Everything below
> the "ORIGINAL STATUS" divider is the historical May-2026 log, kept for the record.
> Some of it is out of date (e.g. it still says "no board yet" and once mislabeled
> the target as TinyLlama — the real target is SmolLM2-135M, and the board now runs).

---

# ===== LATEST PROGRESS (2026-06-22) =====

## Where the project stands now — PHASE 1 COMPLETE ✅
Phase 1 = "get the LLM running on the board AND characterize it." Both done:
- **1a. LLM WORKING on the ZC702 board.** SmolLM2-135M chatbot runs and answers
  on real silicon (since 2026-06-17). Restore point: git tag `phase1-llm-working-2026-06-17`.
- **1b. Characterized + bottleneck identified.** Added an on-chip PMU perf-counter
  peripheral; benchmarked THREE models over 30 prompts each and **proved the design is
  memory-bandwidth-bound** two independent ways (the data Phase 2 optimizes against).
- **1c. Kernel-level verification on silicon.** Ran a kernel self-test (`run_kernel_test.sh`)
  that checks each ztachip LLM kernel against the bit-exact reference C: **11/11 PASS, 0
  mismatches** (~38,657 element comparisons), including the INT4/INT8 `matmul` kernels that
  are infeasible to run in RTL simulation. Details: `bench/results/kernel_verification.md`.

**Phase 2 = performance optimization** (proposed, grounded in the Phase-1 numbers below).
See the "PHASE 2 PLAN" section near the end of this top block.

## How the model gets onto the board (current, working method)
- Model lives in DDR at **0x10000000**, JTAG/`xsdb`-preloaded (no Ethernet, no SD).
- Console I/O is a **DDR mailbox**, now at **0x30000000** (moved from 0x20000000 so models
  up to ~512 MB fit below the mailbox). Firmware + host TCL all use 0x30000000.
- Tooling: Vivado/Vitis **2025.2** — the `xsct` command is gone; use `Vivado/bin/xsdb`.
- One-command runner: `HW/examples/ZC702/run_model.sh <q4|q8|360m> [scope] [full|swap|resume]`.

## Three-model benchmark — final numbers (30 prompts each, on silicon)

| Model | tok/s | bytes/token | DDR read | read-stall | run-to-run sd |
|---|---|---|---|---|---|
| SmolLM2-135M **Q4** (repo default) | **4.13** | 103 MB | 431 MB/s | 42% | 0.29 |
| SmolLM2-135M **Q8** | **3.34** | 156 MB | 526 MB/s | 30% | 0.16 |
| SmolLM2-360M **Q4** | **1.90** | 248 MB | 478 MB/s | 36% | 0.04 |

## The memory-bound proof (the core graduation result)
Throughput is set by how many bytes are pulled from DDR per token, NOT by compute.
Shown two independent ways:
1. **Same network, different weight width (Q4 vs Q8):** identical math per token; Q8 carries
   1.5x the bytes and runs 1.24x slower. A compute-bound design would be equal speed.
2. **Same weight width, different model size (135M vs 360M, both Q4):** 360M carries 2.4x the
   bytes/token and runs at 0.46x the speed — throughput falls in lockstep with bytes moved.
- Delivered DDR bandwidth (`tok/s x bytes/token`) stays in a tight **426-520 MB/s** band for
  all three. The DDR read engine is busy the majority of every run (rd_active ~59-71%).
- The 360M's near-zero variance (sd 0.04) is itself a fingerprint of a hard bandwidth ceiling.
- Subtlety: bandwidth is not a perfect constant — int8's wider, regular reads stall less (30%)
  than int4's 4-bit unpacking (42%), so Q8 reaches a higher raw MB/s.

## Answer-quality finding (graded all 30 prompts vs ground truth; ✅2/🟡1/❌0, max 60)
| | 135M Q4 | 135M Q8 | 360M Q4 |
|---|---|---|---|
| Quality score /60 | 24 | 28 | **40** |
- **360M is clearly the smartest** (only model to get ∫1/(1+x²)=arctan, fission-vs-fusion,
  transformer, sync/async) — but at 2.2x the latency, and it still makes confident factual
  errors (e.g. "$133B" Marshall Plan, "RISC = Reduction in Speed"). Use for structure; verify facts.
- **Q8 ≈ Q4 in quality (28 vs 24) and that gap is noise** — they are the *same network*, so the
  Q4↔Q8 pair is purely the speed/memory experiment, never a quality claim.

## External reference (teammate's Jetson TX1, same prompts/definition)
- Jetson TX1 SmolLM2-135M Q4_K_M ≈ **14.9 tok/s** vs our **4.13 tok/s** (~3.6x faster — far higher
  LPDDR4 bandwidth). The meaningful comparison is tok/s-per-watt; power measurement is the one
  remaining open item (currently paused — blocked on power-source/PMBus readout details).

## Where the data + scripts live
- Results: `HW/examples/ZC702/bench/results/` — `results_<tag>.csv`, `raw_runs_<tag>.txt`,
  `outputs_<tag>.json`, `console_<tag>.log`, and the aggregated `comparison.md`.
- Summarizer: `HW/examples/ZC702/bench/summarize.py` (globs all `results_*.csv`).
- Model ZUFs: `models/SMOLLM2_Q4.ZUF` (147 MB, == on-chip), `SMOLLM2_Q8.ZUF` (200 MB),
  `SMOLLM2_360M_Q4.ZUF` (308 MB). Build helpers: `prep_models.sh`, `make_q4_zuf.sh`.
- Full backup of this session: `backups/session_2026-06-22_3model/` (results + scripts + firmware).
- Firmware mailbox change: `SW/src/soc.cpp` `#define MBX_BASE 0x30000000u` (rebuilt via `SW/rebuild_fw.sh`).

## Known limits / open items
- **JTAG model load is slow (~65 KB/s, cable-latency-bound):** 360M's 308 MB takes ~88 min.
  Not fixable in software (clock bump to 12 MHz and halting the A9 both tried, neither helped).
  A real fix would be SD-card load via the PS — a separate effort.
- **Qwen still can't run:** the ZUF converter hardcodes `llama.*` metadata keys (Qwen uses
  `qwen2.*`), the firmware lacks QKV bias, and ~500 MB collides with the memory map. Multi-day port.
- **Power/energy numbers:** still to be measured (see Jetson note above).

---

# ===== PHASE 2 PLAN — Performance Optimization (proposed) =====

## Guiding equation (from Phase-1 measurements)
    tok/s  =  delivered_DDR_bandwidth  /  bytes_per_token
Phase 1 measured both terms. The design is **memory-bound**, so we improve tok/s by
**raising the numerator** (bandwidth) and **cutting the denominator** (bytes/token) —
NOT by adding compute (Pcores already idle 30–42% of the time).

## The headroom, in numbers (why this is worth doing)
- Delivered DDR read: **431 MB/s (Q4) … 530 MB/s (Q8 peak)**.
- 64-bit HP0 path ceiling @ 93.75 MHz clk_main: 8 B × 93.75 MHz = **~750 MB/s** → we're at 57–71%.
- DDR3 chips' raw capability: **~4+ GB/s** → we use ~10–13% of the actual DRAM.
- Read-engine stall: **42% (Q4) / 30% (Q8) / 36% (360M)** = direct idle-time meter.
=> The bottleneck is the **on-chip AXI/DMA memory path**, not the DRAM. Big, cheap headroom.

## Track A — Raise delivered DDR bandwidth (BIGGEST lever; needs bitstream rebuild)
- **A1. Speed up / decouple the HP0 (AXI-HP) memory clock.** Today the DDR path runs at the
  93.75 MHz main clock (750 MB/s ceiling). Zynq HP ports run ~150–200 MHz; clocking the
  DMA/HP0 domain at 187.5 MHz ~doubles the ceiling to ~1.5 GB/s. *Re-opens timing closure
  (recall the MMCM / hold-slack work) — budget for it.* Est. **~1.5–2× tok/s.**
- **A2. Widen the memory datapath 64→128-bit.** Original Arty design used
  `exmem_data_width_c=128`; we cut it to 64 for one HP port. Restore 128-bit via TWO HP ports
  (Zynq has 4) or an AXI width-converter → 2× bytes/cycle. Combined with A1 → ~4× raw ceiling.
  Files: `HW/src/config.vhd` (`exmem_data_width_c`), `HW/src/ztachip_pkg.vhd`
  (`ddr_vector_depth_c`), the PS block design (add HP1), `main_zc702.v` wiring.
- **A3. Cut the 30–42% read stall.** More AXI outstanding read transactions + deeper read
  prefetch FIFO + longer/aligned bursts so the engine doesn't wait on DDR latency. The
  measured stall % is the headroom meter. Est. **+20–40%.**

## Track B — Cut bytes per token (the denominator; mostly firmware)
- **B1. Quantize the KV-cache (FP16 → INT8).** Halves KV traffic, which grows with context
  length. Files: `SW/apps/llm/llm.cpp` (key/value cache alloc + attention read path).
- **B2. Cache reused tensors in scratch-pad SRAM** (RMSNorm weights, the active embedding row)
  so they aren't re-streamed from DDR every token.
- **B3. Sub-4-bit / mixed quantization on insensitive layers.** Q4→Q8 proved bytes↔time is
  linear, so any byte cut is a direct speed gain — trades answer quality (measure with the
  Phase-1 30-prompt quality harness). Files: `SW/apps/llm/gguf/quant.cpp`, `zuf.*`, kernels.

## Track C — Overlap compute with memory (turn measured stalls into work; bitstream)
- **C1. Double-buffer / prefetch next layer's weights** while computing the current layer —
  directly converts the 30–42% stall fraction into throughput. Highest value-per-effort after A1.
- **C2. Only AFTER A+C lift bandwidth**, compute may co-limit → THEN raising `clk_main` and/or
  adding Pcores finally pays off. (Pointless today: we're memory-bound.)

## Track D — Keep measuring (PMU already exists from Phase 1)
- **D1. Per-kernel cycle profiling** in `forward()` (matmul vs attention vs rmsnorm) to see
  which layers dominate and to validate each change quantitatively.
- **D2. PMBus rail power** (VCCINT=PL compute, VCCPINT/AUX=PS, DDR rail) → **tok/s per watt**
  headline + a measured roofline. (Currently the one open Phase-1 item; no bitstream needed.)

## Recommended order (cheapest-and-most-informative first)
    D1 (profile) → A1 (HP clock) → A3 (stalls/bursts) → C1 (prefetch) → A2 (128-bit) → B (bytes)
Plausible target: A1+A3+C1 take 135M-Q4 from **4.13 → ~7–9 tok/s** with NO quality change;
A2 pushes further; Track B trades quality for more. Each step re-measured with the Phase-1 harness.

## Cost / risk notes
- A1, A2, A3, C1 = RTL/clocking changes → **bitstream rebuild + timing closure** (the 93.75 MHz
  hold-slack saga reopens when the HP clock rises — plan the MMCM/jitter work).
- B1, B2, B3, D1 = firmware-only (fast iterate, no bitstream).
- Validate correctness after every change against `SW/apps/llm/reference/llm_ref.c` and the
  30-prompt quality scoreboard so speed gains never silently break answers.

---

# ===== ORIGINAL STATUS (2026-05-29, historical) =====

---

## Project Goal
Port the ztachip AI accelerator from Arty A7-100T to Xilinx Zynq ZC702 (XC7Z020CLG484-1),
then run a quantized LLM (TinyLlama 1.1B in GGUF format) on it as a graduation project.

---

## Team & Context
- Board: Xilinx Zynq ZC702 (XC7Z020CLG484-1)
- Tool:  Vivado 2025.2
- OS:    Ubuntu 24.04
- Repo:  ~/Desktop/AIDAChip_Workshop_01/ztachip/
- User level: Beginner (explain things simply)

---

## Architecture Decision (IMPORTANT)
We chose: **Keep VexRiscv in PL** (not ARM PS as controller)

This means:
- The ARM PS is used ONLY for: DDR3 memory + clock generation
- VexRiscv (soft RISC-V CPU inside FPGA fabric) controls ztachip
- All existing RISC-V software runs UNCHANGED
- M_AXI_GP0 is DISABLED (ARM does not talk to PL)
- S_AXI_HP0 is the only PS-PL connection (64-bit AXI3, ztachip DMA to DDR3)

Gemini suggested a different approach (ARM controls ztachip via M_AXI_GP0).
We are NOT using that approach. Stick with VexRiscv in PL.

---

## Key Hardware Changes Made

### 1. HW/src/config.vhd — MODIFIED
Changed exmem_data_width_c from 128 to 64:
  - Original (Arty A7): exmem_data_width_c = 128 (MIG DDR controller is 128-bit)
  - ZC702 change:       exmem_data_width_c = 64  (HP0 port is 64-bit max)
  - pid_gen_max_c = 4 (small version, already set, no change needed)

### 2. HW/examples/ZC702/main_zc702.v — CREATED (new top-level)
Replaces the original main.v. Key connections:
  - Instantiates zynq_system_wrapper (PS block design)
  - Instantiates soc_base (VexRiscv + ztachip)
  - SDRAM_arlen[3:0] connected to HP0 (safe truncation, max burst=9 < AXI3 limit of 16)
  - All clocks come from PS FCLK (no external oscillator, no clk_wiz)
  - UART, VGA, Camera, LEDs are stubbed (tied off) for minimal port

### 3. HW/examples/ZC702/zynq_ps_bd.tcl — CREATED
Creates Zynq PS7 block design with:
  - FCLK_CLK0 = 125 MHz (clk_main)
  - FCLK_CLK1 = 250 MHz (clk_x2_main)
  - FCLK_CLK2 =  24 MHz (clk_camera)
  - FCLK_CLK3 =  25 MHz (clk_vga)
  - FCLK_RESET0_N = active-low reset
  - S_AXI_HP0 = 64-bit AXI3 slave (ztachip DMA → PS DDR3)
  - PCW_USE_M_AXI_GP0 = 0 (disabled — critical!)
  - assign_bd_address for HP0_DDR_LOWOCM (0x00000000 to 0x3FFFFFFF, 1GB)

### 4. HW/examples/ZC702/main_zc702.xdc — CREATED
Minimal constraints. PS DDR3/MIO pins NOT here (BD handles them automatically).

### 5. HW/examples/ZC702/create_project_zc702.tcl — CREATED
Vivado project creation script. Creates project, adds all RTL files,
creates FP32 IPs, sources zynq_ps_bd.tcl, generates BD wrapper.

---

## Script Files

| Script | How to Run | Purpose |
|--------|-----------|---------|
| run_sim_build.sh | bash ~/Desktop/.../ZC702/run_sim_build.sh (terminal) | Build RISC-V simulation firmware (.hex) |
| run_sim_vivado.tcl | source ~/Desktop/.../ZC702/run_sim_vivado.tcl (Vivado Tcl) | Setup + launch Vivado simulation |
| run_step2.tcl | source ~/Desktop/.../ZC702/run_step2.tcl (Vivado Tcl) | Create/recreate Vivado project |
| run_step3_synth.tcl | source ~/Desktop/.../ZC702/run_step3_synth.tcl (Vivado Tcl) | Run synthesis + report utilization |
| run_step4_impl.tcl | source ~/Desktop/.../ZC702/run_step4_impl.tcl (Vivado Tcl) | Run implementation + bitstream |
| run_step5_fix_timing.tcl | source ~/Desktop/.../ZC702/run_step5_fix_timing.tcl (Vivado Tcl) | Fix timing: reduce FCLK0 to 100 MHz |

Full path prefix: ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/

---

## Target LLM (CORRECTED)

Model: **SmolLM2-135M-Instruct** (NOT TinyLlama 1.1B — earlier notes were wrong).
Format: SMOLLM2.ZUF (~67 MB Q4 quantized).
Reason: `SW/src/chat.cpp:84` calls `ai.Open("SMOLLM2.ZUF")`. The whole ztachip LLM
software stack (kernels, tokenizer, gguf reader) was designed for this model.

---

## Current Progress

| Step | Description | Status |
|------|-------------|--------|
| 1 | Modify config.vhd (exmem_data_width_c=64) | DONE |
| 2 | Create Vivado project + Block Design | DONE |
| 3 | Synthesis | DONE — 88.70% LUTs, 91.43% BRAM, 37.27% DSP |
| 4 | Implementation (place + route + bitstream) | DONE — bitstream generated (WNS=-1.449ns timing violation) |
| 5 | Fix timing (WNS=-1.449ns at 125MHz) | PENDING — run run_step5_fix_timing.tcl when board arrives |
| SIM-A | Vision-kernel simulation (kernel_test_exe) | DONE — led_out counted 0→8, RISC-V+DMA+PCORE+AXI verified |
| SIM-B | LLM kernel simulation firmware | DONE — ztachip_sim.hex built with 8 LLM tests (718 KB / 1 MB sim RAM) |
| SIM-C | Run LLM kernel simulation in Vivado | IN PROGRESS — sine kernel is heavy (15 cmds), tests run lightest first |
| 6 | Program ZC702 board with .bit file | PENDING (no board yet) |
| 7 | Quantize SmolLM2-135M → SMOLLM2.ZUF | PENDING |
| 8 | Build JTAG/XSCT loader (Ethernet stub workaround) | PENDING (CRITICAL BLOCKER for board demo) |
| 9 | Full LLM chatbot inference on board | PENDING (graduation demo) |

---

## Synthesis Results (Step 3 — Completed)
Device: xc7z020clg484-1

| Resource | Used | Available | Util% | Note |
|----------|------|-----------|-------|------|
| Slice LUTs | 47,187 | 53,200 | 88.70% | Tight but OK, typically drops after impl |
| Slice Registers | 57,828 | 106,400 | 54.35% | Comfortable |
| Block RAM Tile | 128 | 140 | 91.43% | Tight but OK |
| DSPs | 82 | 220 | 37.27% | Plenty of room |
| BSCANE2 | 1 | 4 | 25% | VexRiscv JTAG working correctly |
| PS7 | 1 | 1 | 100% | Zynq PS instantiated correctly |
| float_addsub | 9 instances | | | FP32 IPs working |
| float_mul | 4 instances | | | FP32 IPs working |
| Black Boxes | 0 | | | All modules found — no missing files |

---

## Implementation Results (Step 4 — DONE)
- WNS (Worst Negative Slack): **-1.449 ns** at 125 MHz (FAILED — needs fix)
- Solution: drop FCLK0 from 125 MHz to 100 MHz (script: run_step5_fix_timing.tcl)
- Estimated WNS after fix: +0.551 ns (PASS)
- Bitstream location: ztachip_zc702.runs/impl_1/main_zc702.bit

---

## Simulation Status (Levels 2 — IN PROGRESS, evening of 2026-05-29)

**Vision-kernel sim (proof of basic infra):** DONE.
  - led_out counted up 0,1,2,3,...,8 in ~1.5 ms of sim time
  - Proves: RISC-V boots, ztachip kernels run, DMA + AXI work end-to-end

**LLM-kernel sim (proof of LLM math correctness):** firmware built, sim running.
  - Sim memory bumped 128 KB → 1 MB (mem64.vhd RAM_SIZE: 16000 → 131072)
  - Heap bumped 4 KB → 512 KB (sim/linker.ld)
  - test_llm.cpp guarded with `#ifndef SIMULATION` to skip heavy tests:
    - SKIPPED in sim: dot_product, dot_product2, quantize, matmul_q4, matmul_q8
    - These need GGUF class (not linked) or 3.5 MB heap (impractical in xsim)
  - sine/cosine outer loops reduced from 50 iters → 2 iters in SIMULATION mode
  - 8 LLM kernels reordered LIGHTEST → HEAVIEST so feedback comes fast

Current LLM sim test sequence (file: SW/sim/test_llm_main.cpp):
  led_out=1: ztaInit done       (a few seconds real time)
  led_out=2: residual PASSED    (~1 min)   ← 5 tensor go-commands
  led_out=3: SwiGLU PASSED      (~2 min)   ← 7
  led_out=4: rms PASSED         (~4 min)   ← 10
  led_out=5: rope PASSED        (~7 min)   ← 14
  led_out=6: softmax PASSED     (~10 min)  ← 15
  led_out=7: k_max PASSED       (~15 min)
  led_out=8: cosine PASSED      (~25 min)  ← 15 × 2 iters
  led_out=9: sine PASSED        (~40 min)  ← 15 × 2 iters

**Pragmatic stop point:** led_out = 4 or 5 is enough to declare Level 2 verified.
The heavy kernels run in milliseconds on the real board (Level 3).

---

## LLM Plan (Graduation Project Goal)

ztachip already has a COMPLETE LLM software stack built in:
  SW/apps/llm/llm.cpp        — LLaMA inference engine (class llama)
  SW/apps/llm/tokenizer.cpp  — Text tokenizer
  SW/apps/llm/gguf/gguf.cpp  — GGUF file format reader
  SW/src/test_llm.cpp        — LLM kernel verification tests (14 tests)

Target model: **SmolLM2-135M-Instruct** (Q4 ZUF format)
  - Size: ~67 MB — fits easily in ZC702's 1 GB DDR3
  - Format: ZUF (ztachip's own quantized format, converted from GGUF)
  - chat.cpp opens it as "SMOLLM2.ZUF"
  - Format: GGUF (download from HuggingFace)
  - Task: Text generation / Q&A

6-level verification strategy:
  Level 1: Host PC reference (run llm_ref.c on Ubuntu — no FPGA)
  Level 2: Vivado RTL sim of LLM kernels (current focus — proves math is bit-exact)
  Level 3: Same kernels on real ZC702 board (after timing fix, when board arrives)
  Level 4: Quantize SmolLM2-135M → SMOLLM2.ZUF on host PC
  Level 5: Replace Ethernet TFTP loader with JTAG/XSCT loader (BLOCKER for board)
  Level 6: Full chat() demo on board — graduation deliverable

---

## Critical Blocker for Board Demo: Model Loader Transport

Original ztachip downloads SMOLLM2.ZUF via TFTP from 10.10.10.10 over Ethernet
(see SW/apps/llm/gguf/zuf.cpp ZUF::Open → NetTftpDownload).

**On our ZC702 port, Ethernet is stubbed out** (no axi_ethernetlite, APB stub).
So the TFTP path will fail.

Replacement plan (chosen approach): **JTAG / XSCT pre-load**
  1. Modify ZUF::Open to skip TFTP and read from fixed DDR pointer (e.g. 0x10000000)
  2. Pre-load 67 MB SMOLLM2.ZUF into that DDR address via Vivado HW server / XSCT
  3. Boot VexRiscv; chat() calls modified Open, reads model from memory.
  4. Transfer time: ~1-2 min over JTAG (vs ~80 min over UART).

Alternative considered + rejected: SD card (needs PS Linux), re-enable Ethernet
via GEM (huge scope change).

---

## Key Technical Facts (Important for Next Session)

1. AXI3 vs AXI4: HP0 is AXI3 (4-bit ARLEN). ztachip max burst=9. Safe, no converter needed.
2. Single clock domain: SDRAM_clk = clk_main = S_AXI_HP0_ACLK = 125 MHz (drop to 100 for timing)
3. Memory map: TCM at 0x00000000-0x00003FFF (BRAM), DDR at 0x00004000+
4. SW unchanged: config.h has NUM_PCORE=4, linker.ld DDR at 0x00004000 — no changes needed
5. No ethlite: APB stub — PREADY=1, PRDATA=0, PSLVERROR=0
6. Sim memory expanded: mem64.vhd RAM_SIZE=131072 (1 MB), sim/linker.ld LENGTH=1024k
7. tb_main.vhd wraps main.vhd with a 250 MHz clock generator (sim top is tb_main, not main)

---

## How to Continue in a New Claude Session

Start the new chat with the exact prompt in:
  ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/NEXT_SESSION_PROMPT.txt

---

## Errors We Fixed (Don't Repeat These!)

1. BD validation error: M_AXI_GP0_ACLK unconnected
   Fix: Added PCW_USE_M_AXI_GP0 {0} to zynq_ps_bd.tcl

2. BD critical warning: HP0 DDR address not assigned
   Fix: Added assign_bd_address [get_bd_addr_segs {...HP0_DDR_LOWOCM}]

3. Project already exists error
   Fix: Added -force flag to create_project in create_project_zc702.tcl

4. main.vhd `clk` port unconnected in sim → all signals U
   Fix: Created tb_main.vhd wrapper that generates 250 MHz clock

5. makefile.sim referenced src/soc.c but file is src/soc.cpp
   Fix: run_sim_build.sh auto-corrects via sed

6. LLM tests overflowed 128 KB sim RAM by 56 KB
   Fix: Bumped sim RAM to 1 MB (mem64.vhd RAM_SIZE + sim/linker.ld LENGTH)

7. test_llm.cpp link error: undefined reference to GGUF class methods
   Fix: Wrapped GGUF-using tests (quantize, matmul_q4/q8) in #ifndef SIMULATION

8. sine/cosine had 50-iteration outer loops → 30+ min in xsim
   Fix: Reduced to 2 iterations under #ifdef SIMULATION

9. Wrong target model documented (TinyLlama → SmolLM2-135M)
   Fix: chat.cpp:84 hardcodes "SMOLLM2.ZUF" — that's our target

---

## Contact / Feedback
Project by: Eslam Elsayed (eslam.elwehedy0@gmail.com)
Workshop: AIDAChip GenAI Workshop for Silicon Engineers
Feedback: hello@aidachip.com
