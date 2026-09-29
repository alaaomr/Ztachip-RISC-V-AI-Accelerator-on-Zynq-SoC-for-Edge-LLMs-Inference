/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.
*/
OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(crtStart)

/*
 * ZC702 board memory map (JTAG/DDR boot) -- ZYNQ LOW-1MB GAP AWARE.
 *
 * The Zynq low address space is carved up like this, and the carve-up DIFFERS
 * between the master that LOADS over JTAG (the ARM/debugger) and the master
 * that RUNS the firmware (the VexRiscv via S_AXI_HP0 = "HP0_DDR_LOWOCM"):
 *
 *     0x00000000..0x00003FFF : PL BRAM (TCM)   - stack/scratch, NOT preloadable
 *     0x00004000..0x0003FFFF : PS OCM (256KB)  - writable by JTAG AND read by
 *                                                VexRiscv-HP0 (OCM mapped LOW)
 *     0x00040000..0x000FFFFF : RESERVED GAP    - JTAG/ARM CANNOT write here
 *                                                (above OCM, below CPU DDR)
 *     0x00100000..0x3FFFFFFF : PS DDR          - writable by JTAG, read by HP0
 *
 * So the firmware is split to STRADDLE THE GAP, never landing inside it:
 *   - BOOT region (OCM @0x4000): only the 12-byte reset-vector stub crtStart.
 *     The VexRiscv reset vector is hardwired to 0x00004000, so the very first
 *     instruction MUST live here. crtStart does an ABSOLUTE jump to crtInit, so
 *     the rest of the firmware can be anywhere.
 *   - RAM region (DDR @0x100000): all code, data, ctors, bss, heap. Loaded over
 *     JTAG as a second binary at 0x00100000 (clear of the reserved gap).
 *   - The host loads TWO binaries: vector.bin -> 0x4000, main.bin -> 0x100000.
 *
 * The model SMOLLM2.ZUF is pre-loaded at 0x10000000 (256MB); the heap ends well
 * below that. The DDR mailbox console lives at 0x20000000.
 */

MEMORY {
  BOOT     (rwx): ORIGIN = 0x00004000, LENGTH = 0x0003C000   /* OCM: reset stub */
  RAM      (rwx): ORIGIN = 0x00100000, LENGTH = 230m         /* DDR above the gap */
  TCM      (rwx): ORIGIN = 0x00000000, LENGTH = 16k          /* PL BRAM scratch */
}

_stack_size = 8000;
_heap_size = 200000000;

SECTIONS {

  /* Boot vector + tiny crt: lands at 0x00004000 = VexRiscv reset vector, inside
     OCM (writable by JTAG, read back by VexRiscv via HP0_DDR_LOWOCM). Stays
     well under the 240KB OCM window; crtStart jumps absolutely to crtInit. */
  ._vector ORIGIN(BOOT): {
    *crt.o(.start_jump);
    *crt.o(.text);
    */base/task.o(.text);
  } > BOOT

  /* Stack lives in TCM (fast, runtime scratch, NOLOAD - no preload needed) */
  ._stack (NOLOAD):
  {
    . = ALIGN(16);
    PROVIDE (_stack_end = .);
    . = . + _stack_size;
    . = ALIGN(16);
    PROVIDE (_stack_start = .);
  } > TCM

  .TCM_DATA (NOLOAD) :
  {
    . = ALIGN(4);
    *(.tcm_data)
    *(.tcm_data.*)
    . = ALIGN(4);
  } > TCM

  /* Code and read-only/initialized data (loadable - kept small & contiguous) */
  .data :
  {
    *(.rdata)
    *(.rodata .rodata.*)
    *(.gnu.linkonce.r.*)
    *(.data .data.*)
    *(.gnu.linkonce.d.*)
    . = ALIGN(8);
    PROVIDE( __global_pointer$ = . + 0x800 );
    *(.sdata .sdata.*)
    *(.gnu.linkonce.s.*)
    . = ALIGN(8);
    *(.srodata.cst16)
    *(.srodata.cst8)
    *(.srodata.cst4)
    *(.srodata.cst2)
    *(.srodata .srodata.*)
  } > RAM

  .rodata         :
  {
    *(.rdata)
    *(.rodata .rodata.*)
    *(.gnu.linkonce.r.*)
  } > RAM

  .memory : {
    *(.text .text.* .gnu.linkonce.t.*)
    end = .;
  } > RAM

  .ctors          :
  {
    . = ALIGN(4);
    _ctors_start = .;
    KEEP(*(.init_array*))
    KEEP (*(SORT(.ctors.*)))
    KEEP (*(.ctors))
    . = ALIGN(4);
    _ctors_end = .;
    PROVIDE ( END_OF_SW_IMAGE = . );
  } > RAM

  /* Uninitialized data (NOLOAD - zeroed by crt at boot) */
  .bss (NOLOAD) : {
    . = ALIGN(4);
    _bss_start = .;
    *(.sbss*)
    *(.gnu.linkonce.sb.*)
    *(.bss .bss.*)
    *(.gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  .noinit (NOLOAD) : {
    . = ALIGN(4);
    *(.noinit .noinit.*)
    . = ALIGN(4);
  } > RAM

  /* Heap LAST (highest address, NOLOAD). Keeps the loadable ELF small so the
     JTAG download is fast, and keeps heap below the model at 0x10000000. */
  ._user_heap (NOLOAD):
  {
    . = ALIGN(16);
    PROVIDE ( _end = . );
    PROVIDE ( _heap_start = .);
    . = . + _heap_size;
    . = ALIGN(8);
    PROVIDE ( _heap_end = .);
  } > RAM
}
