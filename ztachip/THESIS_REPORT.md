# Mapping and Execution of the ztachip AI Accelerator on the Xilinx Zynq‑7000 (ZC702) for On‑Device Large Language Model Inference

---

**A Graduation Project Report**

Submitted in partial fulfilment of the requirements for the degree of
Bachelor of Science in Electronics / Computer Engineering

**Author:** Eslam Elsayed
**Contact:** eslam.elwehedy0@gmail.com

**Supervisor:** _____________________
**Department:** _____________________
**University:** _____________________
**Academic Year:** 2025 – 2026

---

## Declaration

I declare that this report and the work presented in it are my own and have been generated as
the result of my own original work, except where explicit reference is made to the work of
others. The hardware design (ztachip) and the language model (SmolLM2) are open‑source artefacts
used under their respective licences; all porting, integration, verification, instrumentation,
and analysis work described herein is the author's contribution.

---

## Abstract

This project investigates the feasibility of executing a transformer‑based Large Language Model
(LLM) on a low‑cost Field‑Programmable Gate Array (FPGA) by mapping the open‑source **ztachip**
AI accelerator onto a **Xilinx Zynq‑7000 (XC7Z020, ZC702)** development platform. The original
ztachip reference design targets an Artix‑7 board with an external memory controller and an
Ethernet model‑transport path; neither is present in the chosen Zynq configuration. The work
therefore re‑hosts the accelerator at the platform‑wrapper level: the soft **VexRiscv** RISC‑V
processor and the ztachip tensor engine are retained in the Programmable Logic (PL), while the
hard ARM Processing System (PS) is restricted to supplying DDR memory and clock generation. A
single‑root clocking scheme (93.75 MHz / 187.5 MHz via an MMCM) was introduced to achieve timing
closure, a two‑stage firmware boot was devised to navigate the Zynq low‑memory reserved region,
a JTAG/DDR mailbox console replaced the absent serial interface, and a class of silent
processor traps caused by misaligned memory accesses was identified and eliminated.

The integrated system successfully executes the **SmolLM2‑135M** and **SmolLM2‑360M** instruction
models. Functional correctness was established at the kernel level by an on‑silicon self‑test in
which each ztachip compute primitive was compared against a bit‑exact reference implementation:
**11 of 11 kernels passed with zero mismatches** across approximately 38,657 element‑level
comparisons, including the INT4/INT8 matrix‑multiply kernels that are intractable to verify in
RTL simulation. A performance‑monitoring unit was added to the design and used to characterise
three model configurations over a fixed 30‑prompt workload. The measurements demonstrate, through
two independent experiments, that the system is **memory‑bandwidth‑bound**: holding the network
fixed while widening the weights (Q4→Q8) and holding the weight width fixed while enlarging the
network (135M→360M) both reduce throughput in proportion to the volume of data transferred per
token, at a sustained effective bandwidth of 426–520 MB/s. The implications for future
optimisation are analysed, and a prioritised improvement plan is proposed.

**Keywords:** FPGA, Zynq‑7000, RISC‑V, ztachip, AI accelerator, Large Language Model, transformer,
quantisation, memory‑bound, edge inference.

---

## Table of Contents

1. Introduction
2. Background and Related Work
3. System Architecture and Design
4. Implementation and Bring‑up Methodology
5. Functional Verification
6. Performance Characterisation and Results
7. Proposed Optimisations (Future Work)
8. Conclusion
- References
- Appendix A: Timing‑Closure Analysis
- Appendix B: Reproduction Procedures
- Appendix C: Consolidated Memory Map

## List of Tables
- Table 2.1: FPGA resource utilisation of the integrated design
- Table 2.2: SmolLM2 model configuration parameters
- Table 3.1: Platform mapping from Arty A7 to ZC702
- Table 4.1: JTAG model‑load times by configuration
- Table 5.1: On‑silicon kernel verification results
- Table 6.1: Definitions of reported performance metrics
- Table 6.2: Three‑model throughput and memory‑traffic results
- Table 6.3: Effective bandwidth (memory‑bound evidence)
- Table 6.4: Output‑quality scores
- Table 7.1: Proposed optimisation tracks

## List of Abbreviations
ALU — Arithmetic Logic Unit; AXI — Advanced eXtensible Interface; BRAM — Block RAM; CRPR — Clock
Reconvergence Pessimism Removal; DDR — Double Data Rate (memory); DMA — Direct Memory Access;
FPGA — Field‑Programmable Gate Array; FFN — Feed‑Forward Network; GGUF — GPT‑Generated Unified
Format; HP — High‑Performance (AXI port); KV — Key/Value; LLM — Large Language Model; LUT —
Look‑Up Table; MMCM — Mixed‑Mode Clock Manager; OCM — On‑Chip Memory; PL — Programmable Logic;
PMU — Performance‑Monitoring Unit; PS — Processing System; RoPE — Rotary Position Embedding;
RMSNorm — Root‑Mean‑Square Normalisation; TTFT — Time To First Token; WNS/WHS — Worst Negative/
Hold Slack; ZUF — ztachip Unified Format.

---

# Chapter 1 — Introduction

## 1.1 Background and Motivation

Large Language Models have rapidly become central to natural‑language applications, but their
deployment is dominated by power‑intensive graphics processing units (GPUs) in data‑centre
environments. There is growing interest in **edge inference** — executing models locally on
constrained hardware — for reasons of latency, privacy, cost, and energy. FPGAs are an attractive
substrate for such work because their datapaths can be specialised to the regular,
multiply‑accumulate‑dominated computation of neural networks, and because their per‑inference
energy can be competitive at low clock frequencies.

This project examines that proposition concretely. It takes an existing open‑source AI
accelerator, **ztachip**, and an existing small language model, **SmolLM2**, and asks: *can they
be made to run together on an inexpensive, resource‑constrained FPGA development board, and what
limits their performance once they do?* Answering this required not only systems‑integration
engineering but also rigorous functional verification and quantitative performance analysis.

## 1.2 Problem Statement

The ztachip reference design is configured for an Artix‑7 (Arty A7) platform that provides an
external DDR3 memory controller and an Ethernet interface for model transport. The selected target,
the Xilinx Zynq‑7000 (XC7Z020) on the ZC702 board, differs fundamentally: memory and clocking are
owned by a hard ARM Processing System, and the chosen minimal configuration exposes neither a soft
memory controller nor a usable Ethernet or serial path to the Programmable Logic. Mapping ztachip
onto this platform therefore demands a re‑hosting of the accelerator's environment, a new
mechanism for delivering the model into memory, a new host‑device communication channel, and the
resolution of platform‑specific hardware and software faults — all while preserving the
accelerator core unchanged so that the existing software stack continues to function.

## 1.3 Objectives

1. Port the ztachip accelerator and its VexRiscv host processor onto the ZC702 platform with
   the ARM PS restricted to memory and clock provision.
2. Achieve static‑timing closure for the integrated design.
3. Establish a reliable means of loading the model into DDR memory and of communicating with the
   running system in the absence of conventional I/O.
4. Bring up end‑to‑end LLM inference (SmolLM2) on the board.
5. Verify the correctness of the accelerator's compute kernels on real hardware.
6. Instrument the design and characterise its performance, identifying the dominant bottleneck.
7. Propose a substantiated optimisation plan.

## 1.4 Scope and Limitations

The work concerns functional bring‑up, correctness verification, and performance
characterisation. It does **not** include: (i) direct measurement of electrical power, which
remains an open item requiring rail‑level instrumentation; (ii) modification of the ztachip
compute core, which is deliberately retained unchanged; or (iii) support for non‑LLaMA‑family
models such as Qwen, whose metadata schema and attention structure are incompatible with the
current converter and firmware. Performance projections for the proposed optimisations (Chapter 7)
are analytical estimates, not measured results.

## 1.5 Contributions

The principal contributions of this project are:

- A complete platform re‑hosting of ztachip from Artix‑7 to Zynq‑7000, with the PS confined to
  memory and clock roles (Chapter 3).
- A single‑root clocking solution that achieves timing closure at an exact 2:1 clock ratio
  (Section 3.3, Appendix A).
- A two‑stage firmware boot and a JTAG/DDR mailbox console that overcome, respectively, the Zynq
  reserved‑memory region and the absence of a serial interface (Sections 3.4–3.5).
- Identification and elimination of a class of silent misaligned‑load processor traps that
  prevented model loading (Section 4.5).
- An on‑silicon kernel self‑test establishing the bit‑exact correctness of all eleven LLM compute
  kernels, including those intractable to simulate (Chapter 5).
- A two‑axis experimental demonstration that the system is memory‑bandwidth‑bound, with supporting
  on‑chip instrumentation (Chapter 6).

## 1.6 Report Organisation

Chapter 2 reviews the relevant hardware and machine‑learning background. Chapter 3 presents the
system architecture and the principal design decisions. Chapter 4 details the implementation and
bring‑up methodology, including the engineering challenges encountered. Chapter 5 describes the
functional verification of the compute kernels. Chapter 6 reports the performance
characterisation and the memory‑bound analysis. Chapter 7 proposes future optimisations. Chapter 8
concludes. Appendices provide the timing analysis, reproduction procedures, and a memory‑map
reference.

---

# Chapter 2 — Background and Related Work

## 2.1 Field‑Programmable Gate Arrays

A Field‑Programmable Gate Array is an integrated circuit whose digital logic can be configured
after manufacture. A circuit is described in a hardware‑description language (VHDL/Verilog),
synthesised and placed‑and‑routed by vendor tools, and emitted as a *bitstream* that configures
the device's look‑up tables (LUTs), flip‑flops, block RAMs (BRAMs), and dedicated multipliers
(DSP slices). The distinction between *building* a bitstream (synthesis through implementation,
requiring hours of tool time) and *programming* a device with an existing bitstream (a sub‑second
configuration operation) is operationally important throughout this report.

## 2.2 The Xilinx Zynq‑7000 SoC and the ZC702 Platform

The Zynq‑7000 (XC7Z020) is a System‑on‑Chip integrating two domains on one die: a **Processing
System (PS)** containing a hard dual‑core ARM Cortex‑A9 and a DDR memory controller, and a
**Programmable Logic (PL)** containing the FPGA fabric. The two are connected by AXI interfaces;
in particular, the 64‑bit **S_AXI_HP0** high‑performance port allows logic in the PL to access PS
DDR memory. The ZC702 is a development board built around this device. Table 2.1 reports the
resource utilisation of the integrated design produced in this work.

**Table 2.1 — FPGA resource utilisation of the integrated design (XC7Z020).**

| Resource | Used | Available | Utilisation |
|---|---:|---:|---:|
| Slice LUTs | 47,187 | 53,200 | 88.7 % |
| Slice Registers | 57,828 | 106,400 | 54.3 % |
| Block RAM tiles | 128 | 140 | 91.4 % |
| DSP slices | 82 | 220 | 37.3 % |

The high LUT and BRAM occupancy (≈ 89 % and 91 %) confirms that the design substantially fills
this small device, motivating the use of the compact ztachip configuration and a small model.

## 2.3 The ztachip Accelerator Architecture

ztachip is an open‑source, multi‑core RISC‑V AI accelerator targeted at edge devices [1]. Its
constituent blocks are: a **VexRiscv** soft RISC‑V processor that executes control firmware; an
**Mcore** scheduler; a **dataplane** that streams data and instructions; an on‑chip **scratch‑pad
SRAM**; a **tensor engine** comprising multiple parallel processing cores (Pcores), each with
scalar and vector ALUs; and a **floating‑point unit** with a vector mode. The tensor engine
performs the matrix multiplications that dominate neural‑network inference. In this work, the
entire accelerator — VexRiscv and ztachip — resides in the PL; the control software executes on
VexRiscv, not on the ARM PS.

The LLM workload exercises a fixed set of compute *kernels* implemented on ztachip: INT4/INT8
matrix multiplication (`matmul_q4`/`matmul_q8`), RMS normalisation (`rms`), rotary position
embedding (`rope`), `softmax`, residual addition (`residual`), the SwiGLU activation, the `sine`
and `cosine` table generators, weight `quantize`, and top‑K selection (`k_max`). These kernels are
the subject of the verification in Chapter 5.

## 2.4 Large Language Models and the Transformer

A transformer LLM [2] generates text autoregressively, producing one *token* (a sub‑word unit) per
*forward pass* through a stack of identical layers. Each layer applies normalisation, projects the
input to query/key/value representations, applies positional encoding, computes self‑attention,
and passes the result through a feed‑forward network. A final projection over the vocabulary
yields *logits*, from which the next token is sampled. The models used here belong to the LLaMA
family [3], for which ztachip's software stack already implements the required operations.

## 2.5 SmolLM2

SmolLM2 [4] is a family of compact instruction‑tuned LLaMA‑style models. Two members are used:
the 135‑million‑parameter and the 360‑million‑parameter variants. Their configuration parameters,
read by the firmware at load time, are summarised in Table 2.2.

**Table 2.2 — SmolLM2 model configuration parameters.**

| Parameter | SmolLM2‑135M | SmolLM2‑360M | Meaning |
|---|---:|---:|---|
| Embedding dimension | 576 | 960 | width of each token vector |
| FFN hidden dimension | 1,536 | 2,560 | width inside the feed‑forward block |
| Number of layers | 30 | 32 | transformer blocks stacked |
| Attention heads | 9 | 15 | parallel attention sub‑spaces |
| Key/value heads | 3 | 5 | grouped‑query attention factor |
| Key/value dimension | 192 | 320 | size of key/value projections |
| Head size | 64 | 64 | dimension per attention head |
| Vocabulary size | 49,152 | 49,152 | distinct output tokens |
| Context length | 8,192 | 8,192 | maximum sequence length |

The firmware imposes compile‑time limits of 32 layers and a 1,024‑token working sequence; the
360M model, at exactly 32 layers, therefore occupies the layer limit.

## 2.6 Weight Quantisation

Quantisation reduces the numerical precision of model weights to lower memory footprint and
bandwidth. This work uses 4‑bit (**Q4/INT4**) and 8‑bit (**Q8/INT8**) integer quantisation.
The accelerator consumes models in ztachip's own **ZUF** container, converted from the standard
GGUF format [5]; the converter accepts an F16/F32 GGUF input and emits a Q4 or Q8 ZUF file. The
on‑device file sizes are 147 MB (135M‑Q4), 200 MB (135M‑Q8), and 308 MB (360M‑Q4). Because Q4 and
Q8 of the same model implement an identical network, the pair provides a controlled experiment in
which only the data volume changes — exploited in Chapter 6.

## 2.7 Related Work

Edge LLM inference on embedded GPUs (e.g. the NVIDIA Jetson family) is an active area; a teammate's
measurements on a Jetson TX1 provide an external reference point in Section 6.6. FPGA‑based neural
accelerators are well established for convolutional workloads; the present work is distinguished by
targeting a *transformer LLM* on a *resource‑constrained* Zynq device using an *unmodified*
open‑source accelerator core, and by its emphasis on on‑silicon verification and instrumented
bottleneck analysis.

---

# Chapter 3 — System Architecture and Design

## 3.1 Design Philosophy: VexRiscv in the Programmable Logic

The central architectural decision is to retain the VexRiscv soft processor as the controller of
ztachip within the PL, rather than re‑architecting the system so that the ARM PS drives the
accelerator over a general‑purpose AXI master. This choice preserves the entire existing ztachip
software stack unmodified, keeps the design portable across FPGA families, and confines the PS to
two well‑defined services: provision of DDR memory (reached from the PL via S_AXI_HP0) and
generation of clocks. The general‑purpose PS→PL master (M_AXI_GP0) is disabled.

## 3.2 Target Platform Mapping

Table 3.1 summarises the differences between the original Arty A7 environment and the ZC702
target, together with the corresponding adaptation. The accelerator core itself is reused
essentially unchanged; the modifications occur at the platform‑wrapper layer.

**Table 3.1 — Platform mapping from Arty A7 to ZC702.**

| Aspect | Arty A7 (original) | ZC702 (this work) | Adaptation |
|---|---|---|---|
| FPGA device | XC7A100T (Artix‑7) | XC7Z020 (Zynq‑7000) | new project, PS block design |
| Memory controller | soft MIG (external DDR3) | PS DDR controller | PL reaches DDR via S_AXI_HP0 (64‑bit) |
| Memory data width | 128‑bit | 64‑bit | `exmem_data_width_c` 128 → 64 |
| Clock source | oscillator + clock wizard | PS FCLK + added MMCM | single‑root 2:1 clocking |
| Model transport | Ethernet (TFTP) | JTAG pre‑load into DDR | host‑side loader scripts |
| Console I/O | UART | DDR mailbox over JTAG | ring‑buffer protocol |

The reduction of the external memory interface from 128 to 64 bits is a direct consequence of the
HP port width and is significant for the bandwidth analysis of Chapter 6.

## 3.3 Clocking Architecture

ztachip requires a secondary clock, `clk_x2`, at exactly twice the frequency of the main clock,
because certain datapaths emit two words per main‑clock cycle. The Zynq's fabric clocks (FCLK) are
derived by integer division of a 1500 MHz PLL, so an exact 2:1 ratio is only obtainable at
frequencies whose divisors are both integral. The pair **93.75 MHz (1500/16)** and
**187.5 MHz (1500/8)** satisfies this and lies just below 100 MHz, providing timing margin.

Deriving the two clocks from two independent PS outputs produced hold‑time violations, because the
two clock trees shared no common node and the timing analyser could not credit common‑path
pessimism. The solution was to feed a single PS clock into a **Mixed‑Mode Clock Manager (MMCM)**
that generates both outputs from a common root; together with a refinement of the input‑jitter
constraint, this yielded full closure (worst negative slack 0.000 ns, worst hold slack +0.009 ns).
A detailed analysis is given in Appendix A.

## 3.4 Memory Architecture and Address Map

The 1 GB DDR address space (0x00000000–0x3FFFFFFF) is partitioned as shown in Appendix C. Three
design considerations shape it:

1. **Reset vector.** The VexRiscv reset vector is fixed at 0x00004000, which lies in the PS
   On‑Chip Memory (OCM). The first executed instruction must therefore reside there.
2. **Reserved low‑memory region.** Addresses 0x00040000–0x000FFFFF are not writable through the
   debug interface on this device, a side‑effect of the OCM remapping mechanism. Consequently the
   firmware is split into a small vector stub placed in OCM at 0x00004000 and a main image placed
   in DDR at 0x00100000, straddling the reserved region.
3. **Coexistence of model, heap and console.** The model is placed at 0x10000000, clear of the
   ~200 MB firmware heap that grows below it; the mailbox console is placed at 0x30000000, leaving
   a 512 MB region for the model so that the 308 MB 360M model fits. (The console was relocated
   from 0x20000000 to 0x30000000 specifically to accommodate this larger model.)

Two sentinel values aid bring‑up: the ASCII marker `"ZTAC"` (0x4341545A) at the model base
confirms model residency in DDR, and `"ZTCH"` (0x5A544348) at the console base confirms that the
firmware has booted and initialised the console.

## 3.5 Host–Device Communication

In the absence of a serial interface reachable from the PL, host–device communication uses a
**DDR mailbox**: a pair of ring buffers in memory (one for device→host output, one for host→device
input), each 4 KB, with head/tail index words and the `"ZTCH"` liveness marker. The host accesses
these structures over JTAG using the Xilinx debugger. Standard‑library output (`printf`) on the
device is routed to the output ring, so all diagnostic and application text becomes visible to the
host. Robustness wrappers retry transient JTAG access failures, and the firmware caps each
response so that output never overflows the 4 KB ring — a property later exploited to validate
host‑side timing (Section 6.1).

---

# Chapter 4 — Implementation and Bring‑up Methodology

## 4.1 Hardware Build Flow

The PL design is created as a Vivado project incorporating a Zynq PS block design (configuring the
FCLK outputs and the S_AXI_HP0 slave) and the ztachip RTL with the modified memory‑width parameter.
Synthesis, implementation, and bitstream generation are performed once; the resulting
`main_zc702.bit` is reused thereafter. Rebuilding the bitstream is required only when the hardware
itself changes (for example, the optimisations proposed in Chapter 7) and is not part of routine
operation.

## 4.2 Firmware Build System

The firmware is compiled for the `rv32im` instruction set and linked according to a script that
realises the address map of Section 3.4. The build selects one of several mutually exclusive modes
through makefile flags: `LLM_TEST` (the chatbot application, the default), `KERNEL_TEST` (a lean
kernel self‑test introduced in this work, Chapter 5), and `UNIT_TEST` (a comprehensive vision‑plus‑
LLM suite). The linked ELF is post‑processed with `objcopy` into two binaries — the vector stub
and the main image — corresponding to the two load addresses.

## 4.3 Bring‑up Sequence

The operational bring‑up follows a fixed, verification‑first order:

0. *(Build the bitstream — only if hardware changed.)*
1. Power on and execute PS initialisation, bringing up DDR and the clocks.
2. Program the FPGA with the existing bitstream (upload the accelerator).
3. **Verify the compute kernels** by the on‑silicon self‑test (Chapter 5), before entrusting the
   accelerator with the full model.
4. Pre‑load the model into DDR at 0x10000000 over JTAG.
5. Load the two firmware binaries, clear the mailbox, and release VexRiscv from reset.
6. Communicate with the running system, or execute the automated benchmark, via the mailbox.

An operational constraint was observed: the system boots reliably only on the first bring‑up after
a power cycle, because re‑initialising an already‑running PS can leave it in an inconsistent state.
A power cycle is therefore performed before each fresh run.

## 4.4 Model Preparation and Loading

Models are converted from F16 GGUF to ZUF (Q4 or Q8) on the host and transferred into DDR over
JTAG. The transfer is the dominant latency in a cold start because the JTAG link is limited by
per‑transaction latency to approximately 65 KB/s; attempts to raise the link clock and to halt the
ARM core during transfer did not improve it. Table 4.1 lists the resulting load times. A
chunked transfer with read‑back verification is used, after a single large transfer was found to
under‑transfer silently.

**Table 4.1 — JTAG model‑load times by configuration.**

| Model | File size | Approx. load time |
|---|---:|---:|
| SmolLM2‑135M Q4 | 147 MB | ~38 min |
| SmolLM2‑135M Q8 | 200 MB | ~52 min |
| SmolLM2‑360M Q4 | 308 MB | ~88 min |

## 4.5 Engineering Challenges and Resolutions

Several platform‑specific faults were encountered and resolved; they constitute a substantial part
of the engineering contribution.

**(a) Timing closure.** Independent clock roots caused hold violations; an MMCM common root with
jitter refinement achieved closure (Section 3.3, Appendix A).

**(b) Reserved low‑memory region.** The non‑writable region 0x40000–0xFFFFF was navigated by the
two‑stage boot described in Section 3.4, with all OCM blocks mapped low.

**(c) Absent serial interface.** Replaced by the DDR mailbox (Section 3.5).

**(d) Silent misaligned‑load traps (the principal software fault).** After the model was found in
DDR, the firmware froze without diagnostic. The cause was traced to the VexRiscv core, which lacks
hardware support for misaligned word loads and traps silently when one occurs. The C library's
string‑comparison routine reads memory a full 32‑bit word at a time; because model strings reside
at arbitrary (often odd) addresses, this generated misaligned accesses. The resolution was to
replace word‑wise library comparisons with byte‑wise comparisons in the model loader and tokeniser,
which are inherently aligned. This single correction unblocked model loading and all subsequent
inference. The resulting design rule — never apply word‑optimised string routines to raw model
bytes in DDR — is recorded for future work.

**(e) Dead on‑chip counters.** The original integration returned zero for all internal AXI
peripheral reads, owing to a tied‑high bus "ready" signal; correcting this revived both the timer
and the performance‑monitoring unit used in Chapter 6.

---

# Chapter 5 — Functional Verification

## 5.1 Verification Strategy

Correctness was addressed at two complementary levels. At the **system level**, the integrated
design produces coherent, on‑topic responses to natural‑language prompts (Chapter 6 reports their
quality). At the **kernel level**, each ztachip compute primitive is compared directly against a
reference implementation. The kernel‑level test is the subject of this chapter because it isolates
the correctness of the hardware datapath from the behaviour of the full model.

## 5.2 Kernel‑Level Verification Methodology

A dedicated firmware build (`KERNEL_TEST`) executes each compute kernel on self‑generated input
data and compares its output, element by element, against the bit‑exact reference C implementation
distributed with ztachip (`llm_ref.c`). The comparison counts matching elements (`ok`) and
mismatching elements (`bad`/`fail`); correctness requires zero mismatches. No model is loaded, as
the tests synthesise their own operands. Results are emitted over the mailbox and captured by the
host.

A key methodological point is that this verification is performed **on silicon rather than in
simulation**. The heavy kernels — in particular the INT4/INT8 matrix multiplications that
constitute the bulk of every transformer layer — require on the order of billions of cycles and
are intractable to simulate at register‑transfer level (hours of wall‑clock time per kernel),
whereas they complete in seconds on the device. On‑silicon execution is therefore the only
practical route to their end‑to‑end verification.

## 5.3 Results

Table 5.1 reports the outcome. All eleven kernels matched the reference exactly. The `ok` column
records the number of compared elements (a measure of test coverage, determined by each kernel's
test‑vector size); every kernel reported zero mismatches.

**Table 5.1 — On‑silicon kernel verification results (XC7Z020 at 93.75 MHz).**

| # | Kernel | Elements compared (`ok`) | Mismatches | Function verified |
|---:|---|---:|---:|---|
| 1 | residual | 1,152 | 0 | skip‑connection addition |
| 2 | SwiGLU | 1,536 | 0 | feed‑forward activation |
| 3 | rms | 1,152 | 0 | RMS normalisation |
| 4 | rope | 384 | 0 | rotary position embedding |
| 5 | softmax | 512 | 0 | attention normalisation |
| 6 | k_max | 1 | 0 | top‑K selection |
| 7 | cosine | 14,400 | 0 | RoPE frequency table |
| 8 | sine | 14,400 | 0 | RoPE frequency table |
| 9 | quantize | 2,048 | 0 | weight quantisation |
| 10 | **matmul_q4** | 1,536 | 0 | **INT4 matrix multiplication** |
| 11 | **matmul_q8** | 1,536 | 0 | **INT8 matrix multiplication** |
| | **Total** | **≈ 38,657** | **0** | |

## 5.4 Discussion

The result establishes that the ztachip compute datapath, as integrated on the ZC702, is
mathematically faithful to the reference across the full set of LLM kernels, with particular
significance for the matrix‑multiply primitives that cannot be verified by simulation. Together
with the system‑level evidence that the model produces coherent output, this provides
independent, layered assurance of functional correctness.

---

# Chapter 6 — Performance Characterisation and Results

## 6.1 Experimental Methodology

Each model configuration was evaluated on an identical workload of 30 prompts spanning six
categories (mathematics, science, geography, history, engineering, and general knowledge), five
prompts each, to avoid topic bias. Throughput was measured by host wall‑clock timing. This is
valid because each response is capped so that its text fits within the 4 KB output ring; the
firmware therefore never stalls waiting for the host to drain the ring over the slow JTAG link, and
host‑elapsed time closely approximates on‑device computation time. Memory‑traffic quantities were
obtained from the on‑chip performance‑monitoring unit.

## 6.2 Performance Metrics

Table 6.1 defines every reported quantity to avoid ambiguity.

**Table 6.1 — Definitions of reported performance metrics.**

| Metric | Unit | Definition |
|---|---|---|
| Throughput (tok/s) | tokens/second | generated tokens divided by elapsed time; higher is faster |
| Mean / Median | tok/s | arithmetic mean and median over the 30 prompts |
| Standard deviation (sd) | tok/s | run‑to‑run dispersion; small values indicate consistency |
| TTFT | seconds | time to first token (prompt‑processing/prefill latency) |
| Generated tokens | tokens | length of the produced response |
| Bytes per token | bytes | weight bytes read from DDR to produce one token |
| DDR read rate | MB/s | sustained read bandwidth delivered by the memory engine |
| Read‑active fraction | % | proportion of time the read engine is transferring data |
| Read‑stall fraction | % | proportion of time the read engine is idle (≈ 100 % − read‑active) |
| Effective bandwidth | MB/s | throughput × bytes‑per‑token; a derived diagnostic (Section 6.4) |

The governing relationship, used throughout the analysis, is:

> throughput (tok/s) = delivered DDR bandwidth ÷ bytes per token.

## 6.3 Throughput Results

Table 6.2 reports the measured throughput and memory traffic for the three configurations.

**Table 6.2 — Three‑model throughput and memory‑traffic results (30 prompts each).**

| Configuration | Mean tok/s | Median | sd | TTFT (s) | Bytes/token | DDR read | Read‑active | Read‑stall |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| SmolLM2‑135M Q4 (baseline) | 4.13 | 4.21 | 0.29 | 5.2 | 103 MB | 431 MB/s | 59 % | 42 % |
| SmolLM2‑135M Q8 | 3.34 | 3.38 | 0.16 | 6.7 | 156 MB | 526 MB/s | 71 % | 30 % |
| SmolLM2‑360M Q4 | 1.90 | 1.89 | 0.04 | 12.0 | 248 MB | 478 MB/s | 65 % | 36 % |

The Q4 baseline is the fastest configuration; the Q8 variant of the same model is slower despite
performing identical arithmetic; and the larger 360M model is the slowest. The standard deviation
decreases markedly with model size (0.29 → 0.04 tok/s), indicating that the larger, more strongly
memory‑limited workload exhibits near‑deterministic run times.

## 6.4 The Memory‑Bound Analysis

The hypothesis that throughput is limited by memory bandwidth rather than computation is supported
by two independent experiments.

**Experiment A — fixed network, varied weight width (Q4 vs Q8).** These configurations implement
an identical network and perform identical arithmetic per token; only the weight width differs,
with Q8 transferring approximately 1.5× the bytes. The observed slowdown is 1.24×. A
compute‑limited design would exhibit equal throughput; the observed dependence on data volume
indicates a memory limit.

**Experiment B — fixed weight width, varied network size (135M vs 360M, both Q4).** The 360M model
transfers 2.4× the bytes per token and runs at 0.46× the throughput; throughput falls in near‑
proportion to data volume.

The two experiments are reconciled by the effective‑bandwidth diagnostic in Table 6.3: the product
of throughput and bytes‑per‑token is approximately constant across three very different models,
indicating that all three operate against a common memory ceiling.

**Table 6.3 — Effective bandwidth (memory‑bound evidence).**

| Configuration | Bytes/token | Throughput | Effective bandwidth |
|---|---:|---:|---:|
| SmolLM2‑135M Q4 | 103 MB | 4.13 tok/s | 426 MB/s |
| SmolLM2‑135M Q8 | 156 MB | 3.34 tok/s | 520 MB/s |
| SmolLM2‑360M Q4 | 248 MB | 1.90 tok/s | 472 MB/s |

The effective bandwidth is not perfectly constant: the wider, more regular INT8 reads stall less
(30 %) than the INT4 four‑bit unpacking (42 %), so the Q8 configuration sustains a higher raw
bandwidth. The central conclusion is nonetheless robust: throughput tracks data volume, not
arithmetic. Furthermore, the sustained 430–520 MB/s is only 57–71 % of the 64‑bit memory port's
own ceiling at 93.75 MHz (≈ 750 MB/s) and roughly one‑tenth of the DDR3 devices' raw capability,
indicating that the limiting element is the on‑chip memory *path*, not the DRAM — a finding that
directly informs Chapter 7.

## 6.5 Output‑Quality Assessment

The 30 responses of each configuration were graded against ground truth on a three‑point scale
(2 = correct, 1 = partial, 0 = incorrect; maximum 60). Results are given in Table 6.4.

**Table 6.4 — Output‑quality scores (max 60).**

| Configuration | Score | Observation |
|---|---:|---|
| SmolLM2‑135M Q4 | 24 | weakest; prone to repetition |
| SmolLM2‑135M Q8 | 28 | ≈ Q4 (same network; difference attributable to sampling) |
| SmolLM2‑360M Q4 | 40 | strongest; the only configuration to answer several technical items correctly |

The negligible Q4–Q8 quality difference is expected, as they implement the same network; this is
precisely why that pair is used for the bandwidth experiment and not for quality claims. The
quality improvement of the 360M model is attributable to parameter count, at the cost of a 2.2×
increase in latency per response. All configurations remain factually unreliable at this scale and
are best regarded as producing well‑structured rather than authoritative output.

## 6.6 Comparative Baseline

For external context, a teammate measured the same model (SmolLM2‑135M Q4) on an NVIDIA Jetson TX1,
obtaining approximately 14.92 tok/s, against 4.13 tok/s for the present design. The roughly 3.6×
advantage of the Jetson is consistent with its order‑of‑magnitude higher clock frequency and
greater memory bandwidth. As the objective of this work is efficiency on a low‑cost FPGA rather
than absolute throughput, the meaningful comparison is energy efficiency (tokens per second per
watt); the requisite power measurement is identified as the principal open item (Section 7.5).

## 6.7 Discussion

The characterisation yields a clear and quantitatively supported conclusion: the design is
memory‑bandwidth‑bound, and the bottleneck lies in the on‑chip memory path rather than the DRAM or
the compute units, the latter being idle 30–42 % of the time. This result determines the direction
of the optimisation plan in Chapter 7 — namely, that performance is to be improved by increasing
delivered bandwidth or reducing data volume per token, not by adding arithmetic resources.

---

# Chapter 7 — Proposed Optimisations (Future Work)

## 7.1 Analytical Basis

From the governing relationship of Section 6.2, throughput is improved by raising delivered
bandwidth (the numerator) or reducing bytes per token (the denominator). The measurements of
Chapter 6 show substantial headroom in the former, since the delivered bandwidth is well below both
the memory port's clock‑limited ceiling and the DRAM's raw capability, and the read engine is idle
for a significant fraction of each run. The proposed work is organised accordingly (Table 7.1).

**Table 7.1 — Proposed optimisation tracks.**

| Track | Measure | Rationale (from Chapter 6) | Requires |
|---|---|---|---|
| A1 | Raise the HP/memory‑port clock (≈ 94 → ~188 MHz) | delivered BW is 57–71 % of the port ceiling | bitstream rebuild + re‑closure |
| A2 | Widen the memory path 64 → 128 bits (dual HP ports) | restores the Arty‑class width | bitstream rebuild |
| A3 | Increase outstanding reads / prefetch depth / burst length | read engine idle 30–42 % | bitstream rebuild |
| B1 | Quantise the key/value cache (FP16 → INT8) | reduces per‑token data volume | firmware only |
| B2 | Cache reused tensors in scratch‑pad SRAM | avoids re‑reading invariants per token | firmware only |
| B3 | Sub‑4‑bit / mixed quantisation on tolerant layers | reduces data volume (quality trade‑off) | firmware + tooling |
| C1 | Double‑buffer (prefetch next layer during compute) | converts measured idle time into work | bitstream rebuild |
| D1/D2 | Per‑kernel profiling; rail‑power measurement | guides effort; enables tok/s‑per‑watt | firmware / instrumentation |

## 7.2–7.4 Summary of Tracks

Track A targets delivered bandwidth, the largest lever, through clock frequency, datapath width,
and improved memory‑transaction concurrency; these require hardware changes and a renewed timing
closure. Track B reduces data volume in firmware, primarily by compressing the key/value cache and
by retaining invariant tensors on chip. Track C overlaps computation with memory transfer through
double‑buffering, directly recovering the measured idle fraction. Track D sustains the measurement
infrastructure, adding per‑kernel profiling and the rail‑level power measurement required for an
energy‑efficiency figure.

## 7.5 Roadmap and Expected Gains

A pragmatic order is D1 → A1 → A3 → C1 → A2 → B, beginning with the lowest‑risk, most informative
steps. An analytical estimate suggests that A1, A3, and C1 together could raise the 135M‑Q4
configuration from 4.13 to approximately 7–9 tok/s without loss of output quality; this figure is a
projection and not a measured result, and its realisation depends on the frequency achievable under
renewed timing closure. The single most important measurement outstanding is electrical power,
without which the project's central efficiency hypothesis cannot be quantitatively concluded.

---

# Chapter 8 — Conclusion

## 8.1 Summary of Achievements

This project successfully mapped the open‑source ztachip AI accelerator and its VexRiscv host
processor onto the Xilinx Zynq‑7000 (ZC702) platform, with the ARM Processing System restricted to
memory and clock provision, and brought up end‑to‑end transformer LLM inference on the device. The
work delivered: a timing‑closed integration at an exact 2:1 clock ratio; a two‑stage boot and a
JTAG/DDR mailbox console that overcame platform‑specific constraints; the diagnosis and elimination
of a silent misaligned‑load fault that had prevented model loading; an on‑silicon verification
establishing the bit‑exact correctness of all eleven LLM compute kernels; and an instrumented
performance characterisation that demonstrates, through two independent experiments, that the
system is memory‑bandwidth‑bound at a sustained 426–520 MB/s.

## 8.2 Concluding Remarks

The results show that a transformer LLM can be executed on an inexpensive, resource‑constrained
FPGA using an unmodified accelerator core, and that its performance on this platform is governed by
memory movement rather than arithmetic. This understanding both explains the observed throughput
and prescribes the path to improving it. The principal remaining work is the measurement of
electrical power, which would permit the project's efficiency proposition to be evaluated against
GPU baselines on the metric for which a low‑frequency FPGA is best suited: energy per token.

---

# References

[1] ztachip: an open‑source RISC‑V AI/vision accelerator. Source repository and documentation.
(Open‑source project.)

[2] A. Vaswani, N. Shazeer, N. Parmar, J. Uszkoreit, L. Jones, A. N. Gomez, Ł. Kaiser, and
I. Polosukhin, "Attention Is All You Need," in *Advances in Neural Information Processing Systems
(NeurIPS)*, 2017.

[3] H. Touvron et al., "LLaMA: Open and Efficient Foundation Language Models," arXiv:2302.13971,
2023.

[4] L. Ben Allal et al., "SmolLM2: Compact Instruction‑Tuned Language Models," Hugging Face, 2024.

[5] G. Gerganov et al., "GGUF / llama.cpp: LLM inference and quantisation formats," open‑source
project.

[6] Xilinx, Inc., *Zynq‑7000 SoC Technical Reference Manual (UG585)*.

[7] Xilinx, Inc., *ZC702 Evaluation Board for the Zynq‑7000 XC7Z020 (UG850)*.

[8] C. Papon et al., *VexRiscv: a 32‑bit RISC‑V CPU implemented in SpinalHDL*, open‑source project.

[9] A. Waterman and K. Asanović (eds.), *The RISC‑V Instruction Set Manual, Volume I:
Unprivileged ISA*.

[10] Xilinx, Inc., *UltraFast Design Methodology Guide (UG949)* — static timing analysis and
clocking.

---

# Appendix A — Timing‑Closure Analysis

**A.1 Frequency selection.** Because Zynq FCLKs are integer divisions of a 1500 MHz PLL, an exact
`clk_x2 = 2 × clk_main` relationship requires both frequencies to have integral divisors. The pair
93.75 MHz (1500/16) and 187.5 MHz (1500/8) is the highest exact‑ratio pair below 100 MHz.

**A.2 The hold‑violation mechanism.** With the two clocks taken from independent PS outputs, their
clock trees shared no common node; the static‑timing analyser could not apply clock‑reconvergence
pessimism removal (CRPR), so the full clock uncertainty was charged against the hold check,
producing three hold violations. Hold is evaluated on the same clock edge at launch and capture
flip‑flops and therefore *cannot* be corrected by lowering the clock frequency.

**A.3 Resolution.** A single PS clock was routed into an MMCM that generates both `clk_main` and
`clk_x2` from a common node, restoring CRPR credit; an input‑jitter‑constraint refinement removed
the residual deficit. The design then closed with worst negative slack 0.000 ns and worst hold
slack +0.009 ns. Raising the memory‑port frequency in Track A1 (Chapter 7) will reopen this
analysis.

# Appendix B — Reproduction Procedures

All scripts reside under `HW/examples/ZC702/` and are invoked as `bash <script>`. The board is
power‑cycled before each fresh run.

- **Kernel verification (Chapter 5):** `run_kernel_test.sh` — programs the bitstream, loads the
  lean kernel‑test firmware (no model), runs all kernels, and writes
  `bench/results/kernel_selftest.log`.
- **Cold bring‑up and chatbot (Chapter 4):** `run_board_day.sh` — programs the bitstream, loads a
  model and the firmware, and opens the mailbox console.
- **Resume console (model already resident):** `run_resume_fw.sh`.
- **Single‑model benchmark (Chapter 6):** `run_model.sh <q4|q8|360m>` — writes
  `bench/results/results_<tag>.csv`.
- **Aggregate the benchmark:** `bench/summarize.py` — writes `bench/results/comparison.md`.

Firmware build modes (in `SW/makefile`): `LLM_TEST=yes` (chatbot, default), `KERNEL_TEST=yes`
(kernel self‑test), `UNIT_TEST=yes` (full suite).

# Appendix C — Consolidated Memory Map

| Address range | Contents | Size |
|---|---|---|
| 0x00000000 – 0x00003FFF | PL BRAM (TCM): stack / scratch | 16 KB |
| 0x00004000 – 0x0003FFFF | PS OCM (mapped low); firmware vector stub at 0x00004000 | ~240 KB |
| 0x00040000 – 0x000FFFFF | Reserved region (not writable via debug) | ~768 KB |
| 0x00100000 – 0x3FFFFFFF | PS DDR (main memory) | ~1 GB |
| — 0x00100000 | firmware main image | — |
| — 0x10000000 | model file (ZUF); marker `"ZTAC"` | — |
| — 0x30000000 | mailbox console; marker `"ZTCH"` | — |

---

*End of report.*
