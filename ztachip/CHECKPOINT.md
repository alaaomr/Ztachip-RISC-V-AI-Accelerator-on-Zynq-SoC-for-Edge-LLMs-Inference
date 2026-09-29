# ZC702 ztachip LLM — Phase-1 Checkpoint (2026-06-17)

## STATUS: ✅ SmolLM2-135M chatbot RUNS on the ZC702 and answers prompts.
Measured baseline: **~4.5 tokens/s, ~222 ms/token** (host wall-clock timing,
<1% run-to-run variance) on VexRiscv @93.75 MHz + ztachip, model JTAG-preloaded
into DDR @0x10000000.

This file marks a restore point. Git tag: `phase1-llm-working-2026-06-17`.

---

## How to RETURN to this exact step
- Source + scripts are committed in git (this commit / the tag above):
    git checkout phase1-llm-working-2026-06-17      # detached, to inspect
  or just stay on master (this commit is the latest).
- Portable backup tarball (source+scripts+firmware bins+bitstream) lives at:
    ../ztachip_phase1_backup_2026-06-17.tar.gz   (outside the repo)

## What is NOT in git/backup (regenerable or static, by design)
- models/SMOLLM2.ZUF (141MB)  -> the model. STATIC, already on disk. If lost,
  regenerate from an F16/F32 SmolLM2 GGUF with SW/apps/llm/gguf/quant.
- SW/build/ (170MB)           -> firmware build. Regenerate: `bash SW/rebuild_fw.sh`.
- HW/examples/ZC702/ztachip_zc702.{runs,sim,gen,srcs,cache,...} (2GB Vivado
  project) -> regenerate with HW/examples/ZC702/create_project_zc702.tcl.
  The compiled bitstream (main_zc702.bit) IS saved in the tarball backup.

---

## How to RESUME work (board day)
1. Power the ZC702 (12V/5A). Confirm LEDs: DS2 + greens on, DS14 OFF (DS14 on =
   power fault -> power-cycle, reseat 12V).
2. JTAG cable STATUS LED off at first = normal -> run_jtag_diag.sh, wait 5s, rescan.
3. If board STAYED powered and model is still in DDR:
     bash HW/examples/ZC702/run_resume_fw.sh     (~3 min, firmware only)
   If board was OFF (DDR wiped):
     bash HW/examples/ZC702/run_board_day.sh      (~40 min, full model reload)
4. Wait for "I am a chatbot" + ">". Type a SHORT question.
5. After each answer: `[HOST PERF] ... throughput=X tok/s` line shows performance.

## Key fixes that make it work (see also the AI memory notes)
- VexRiscv (rv32im) TRAPS SILENTLY on unaligned word loads. libc strcmp on the
  unaligned DDR model strings hung the CPU. Fixed with byte-wise compares:
  SW/apps/llm/gguf/zuf.cpp (findKey) and SW/apps/llm/tokenizer.cpp (zstrcmp).
  RULE: never use libc word-optimized string fns on DDR model bytes.
- Firmware split across the Zynq low-1MB reserved gap: vector.bin@0x4000(OCM) +
  main.bin@0x100000(DDR), OCM mapped low. Build: `bash SW/rebuild_fw.sh`.
- Console robustness: board_*.tcl use safe_mrd/safe_mwr (retry on "Invalid
  context") + clear mailbox before releasing CPU + host wall-clock timing.
- Response hard-cap = maxTokenResponse*4 (=160 tok) so runaway loops self-stop.

## Performance instrumentation already in place (apps/llm/llm.cpp)
- [PERF] per-response line (prefill/decode/tok-s) - cycle math ready but on-chip
  timer is DEAD in this bitstream (see below), so use the host [HOST PERF] line.
- Timer self-test at model open (proves APB counters read 0 in this bitstream).

## KNOWN LIMITATION blocking detailed HW profiling (Phase-2 work)
On-chip timers are unusable in THIS bitstream:
- APB timer (time.vhd) reads 0 (prdata not reaching CPU in the ZC702 integration).
- VexRiscv mcycle increments but is NOT wired to CSR read (riscv.v).
=> A bitstream rebuild is needed to add a PMU (perf counters) + working cycle
   counter for cycle-accurate + per-block profiling. Design notes in AI memory
   (project-perf-timing) and the plan: PMU on free APB id 7, tapping pcore
   tid_valid / dp task_busy / fpu_busy / ddr_tx/rx AXI valid-ready.

## Phase-2 goal: make the SAME LLM faster on the SAME chip.
Decode is expected MEMORY-BOUND (every token streams all weights from DDR).
Measure: per-kernel cycles, pcore busy%, DDR bandwidth+stall, INT4 vs INT8.
Likely wins: lower-bit quantization, weight prefetch/double-buffer, more DDR BW.
