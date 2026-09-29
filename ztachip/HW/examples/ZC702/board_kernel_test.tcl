# =============================================================================
# board_kernel_test.tcl — On-silicon ztachip KERNEL self-test (the "LED test")
#
# Run:  bash run_kernel_test.sh
#
# Loads the UNIT_TEST firmware (NOT the chatbot, NO model needed) and lets the
# VexRiscv run test() + test_llm() + test_dma(). Each kernel compares the ztachip
# hardware result against the reference C implementation and prints "<NAME> ok=N
# bad=0" over the DDR mailbox, which we read here over JTAG.
#
# Why on the board: the heavy kernels (dot_product, quantize, matmul_q4/q8) take
# HOURS in RTL simulation but run in MILLISECONDS on silicon @ 93.75 MHz.
#
# Full bring-up (PS7 + bitstream), so it works whether the board is warm or cold.
# It does NOT touch the model in DDR; to return to the chatbot just reload the
# chatbot firmware (fw_llm/, or SW/build) with run_resume_fw.sh / run_board_day.sh.
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set PS7INIT $ZC702/ztachip_zc702.gen/sources_1/bd/zynq_system/ip/zynq_system_processing_system7_0_0/ps7_init.tcl
set BIT     $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
set VEC     $ZC702/fw_kerneltest/vector.bin
set MAIN    $ZC702/fw_kerneltest/main.bin

set VEC_ADDR  0x00004000
set MAIN_ADDR 0x00100000
set SLCR_UNLOCK   0xF8000008
set FPGA_RST_CTRL 0xF8000240
set OCM_CFG       0xF8000910

# ---- Mailbox layout (must match soc.cpp) ----
set MBX      0x30000000
set MBX_MAGIC 0x5A544348
set OUTHEAD  [expr {$MBX + 0x40}]
set OUTTAIL  [expr {$MBX + 0x80}]
set INHEAD   [expr {$MBX + 0xC0}]
set INTAIL   [expr {$MBX + 0x100}]
set OUTBUF   [expr {$MBX + 0x1000}]
set RING     4096

# capture controls
set MAX_SECS   600   ;# hard stop (matmul_q4/q8 are heavy but well under this)
set IDLE_STOP  180   ;# idle-seconds fallback (matmul compute can be quiet for >60s)
set DONE_MARK  "SELF-TEST COMPLETE"   ;# firmware prints this after the LAST kernel

# --- Robust JTAG memory access (survives transient "Invalid context") ---------
proc retarget_arm {} {
    catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
    catch {stop}
}
proc safe_mrd {addr} {
    for {set i 0} {$i < 20} {incr i} {
        if {![catch {set r [lindex [mrd -value $addr] 0]} err]} { return $r }
        retarget_arm
        after 30
    }
    error "safe_mrd failed at [format 0x%08X $addr]: $err"
}
proc safe_mwr {addr val} {
    for {set i 0} {$i < 20} {incr i} {
        if {![catch {mwr $addr $val} err]} { return }
        retarget_arm
        after 30
    }
    error "safe_mwr failed at [format 0x%08X $addr]: $err"
}
proc rd32 {addr} { return [safe_mrd $addr] }
proc wr32 {addr val} { safe_mwr $addr $val }
proc peek_byte {addr} {
    set wa [expr {$addr & ~3}]
    set sh [expr {8 * ($addr & 3)}]
    set w [safe_mrd $wa]
    return [expr {($w >> $sh) & 0xFF}]
}

# Load a big binary into DDR in chunks (proven for the chatbot/model). A single
# huge `dow -data` can silently under-transfer; chunking is reliable + shows progress.
proc dow_data_progress {file addr {chunkMB 4}} {
    set total [file size $file]
    set tmp   /tmp/zta_kt_chunks
    file delete -force $tmp
    file mkdir $tmp
    puts "INFO:     splitting [expr {$total/1048576}] MB into ${chunkMB} MB chunks..."
    exec split -b ${chunkMB}M $file $tmp/c_
    set chunks [lsort [glob $tmp/c_*]]
    set n [llength $chunks]
    set cur $addr
    set loaded 0
    set start [clock seconds]
    set i 0
    foreach c $chunks {
        incr i
        set sz [file size $c]
        dow -data $c $cur
        set cur    [expr {$cur + $sz}]
        set loaded [expr {$loaded + $sz}]
        set el     [expr {[clock seconds] - $start}]
        set rate   [expr {$el > 0 ? $loaded / 1024.0 / $el : 0}]
        puts [format "INFO:     fw %3d%%  %d/%d MB  %.0f KB/s  %ds" \
              [expr {100*$loaded/$total}] [expr {$loaded/1048576}] [expr {$total/1048576}] $rate $el]
        flush stdout
    }
    file delete -force $tmp
    puts "INFO:     firmware load DONE in [expr {[clock seconds]-$start}]s"
}

# Read the 32-bit little-endian word at byte offset $off of a file.
proc file_word {file off} {
    set f [open $file rb]
    seek $f $off
    set b [read $f 4]
    close $f
    binary scan $b iu w
    return $w
}

puts "INFO: ===== ZC702 ON-SILICON KERNEL SELF-TEST ====="
foreach f [list $PS7INIT $BIT $VEC $MAIN] {
    if {![file exists $f]} { puts "ERROR: missing $f"; return }
}

# 1. connect + PS7
puts "INFO: \[1\] Connect + PS7 init (clocks + DDR)..."
connect
after 500
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
source $PS7INIT
ps7_init
ps7_post_config

# 2. hold VexRiscv in reset
puts "INFO: \[2\] Holding VexRiscv in reset..."
mwr $SLCR_UNLOCK   0x0000DF0D
mwr $FPGA_RST_CTRL 0x00000001

# 2b. map all OCM low (fills the 0x30000 hole; shadows for the HP0 read path)
puts "INFO: \[2b\] Mapping all OCM low..."
set _ocm [lindex [mrd -value $OCM_CFG] 0]
mwr $OCM_CFG [expr {$_ocm & ~0xF}]
puts "INFO:     OCM_CFG 0x[format %X $_ocm] -> 0x[format %X [lindex [mrd -value $OCM_CFG] 0]]"

# 3. program FPGA
puts "INFO: \[3\] Programming FPGA (timing-clean bitstream)..."
targets -set -filter {name =~ "xc7z020"}
fpga -file $BIT

# 4. load ONLY the test firmware (no model)
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {stop}   ;# halt the ARM core so the DAP can write OCM/DDR (avoids "Blocked address")
after 200
puts "INFO: \[4\] Loading kernel-test firmware (no model needed)..."
puts "INFO:     vector stub ([file size $VEC] B) -> $VEC_ADDR (OCM)"
# retry the OCM write: a wedged AHB bus sometimes clears after a re-halt
set ok 0
for {set i 0} {$i < 5} {incr i} {
    if {![catch {dow -data $VEC $VEC_ADDR} err]} { set ok 1; break }
    puts "WARN: vector write failed (try [expr {$i+1}]): $err"
    catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
    catch {stop}
    after 400
}
if {!$ok} {
    puts "ERROR: cannot write OCM at $VEC_ADDR (AHB bus wedged)."
    puts "ERROR: POWER-CYCLE the board (off ~5s, on) and re-run — this clears the DAP/bus state."
    return
}
puts "INFO:     main image ([expr {[file size $MAIN]/1048576}] MB) -> $MAIN_ADDR (DDR), chunked..."
dow_data_progress $MAIN $MAIN_ADDR 4

# 4a. VERIFY the load actually reached the END of the image (main() lives near the
# top of an 18MB image; a truncated load = silent crash). Check first + last words.
set last_off [expr {[file size $MAIN] - 4}]
set ddr_first [rd32 $MAIN_ADDR]
set ddr_last  [rd32 [expr {$MAIN_ADDR + $last_off}]]
set f_first   [file_word $MAIN 0]
set f_last    [file_word $MAIN $last_off]
puts [format "INFO:     verify  @0x%08X ddr=0x%08X file=0x%08X  %s" \
      $MAIN_ADDR $ddr_first $f_first [expr {$ddr_first==$f_first ? "OK" : "MISMATCH"}]]
puts [format "INFO:     verify  @0x%08X ddr=0x%08X file=0x%08X  %s" \
      [expr {$MAIN_ADDR+$last_off}] $ddr_last $f_last [expr {$ddr_last==$f_last ? "OK" : "MISMATCH"}]]
if {$ddr_first != $f_first || $ddr_last != $f_last} {
    puts "ERROR: firmware did NOT load correctly into DDR (readback mismatch) — aborting."
    return
}
puts "INFO:     firmware verified in DDR (first+last word match the file)."

# 4b. clear stale mailbox
puts "INFO: \[4b\] Clearing stale mailbox state..."
foreach off {0x00 0x40 0x80 0xC0 0x100} { mwr [expr {$MBX + $off}] 0x00000000 }

# 5. release VexRiscv
puts "INFO: \[5\] Releasing VexRiscv -> kernel tests running..."
mwr $FPGA_RST_CTRL 0x00000000

# 6. wait for the console magic (first printf auto-inits it)
puts "INFO: \[6\] Waiting for first kernel output..."
set tries 0
while {[rd32 $MBX] != $MBX_MAGIC} {
    after 200
    incr tries
    if {$tries > 600} {
        puts "ERROR: no kernel output appeared (magic\@$MBX = 0x[format %08X [rd32 $MBX]])."
        puts "ERROR: This is the stale-board state — a re-run without a power-cycle re-inits"
        puts "ERROR: the live PS and the firmware won't boot. POWER-CYCLE the board (off ~5s,"
        puts "ERROR: on) and run ONCE. It boots reliably on the first bring-up after power-up."
        return
    }
}
puts "INFO: ============================================================"
puts "INFO:  KERNEL TESTS LIVE — capturing results below."
puts "INFO:  Each line '<KERNEL> ok=N bad=0'  => that kernel PASSED on silicon."
puts "INFO:  Capturing one full pass (auto-stops when idle); Ctrl+C to end early."
puts "INFO: ============================================================"

# 7. drain the mailbox output for one full pass
set outtail [rd32 $OUTTAIL]
set t0       [clock seconds]
set tlast    [clock seconds]
set capbuf   ""
set recent   ""
while 1 {
    set outhead [rd32 $OUTHEAD]
    if {$outhead != $outtail} {
        while {$outtail != $outhead} {
            set v [peek_byte [expr {$OUTBUF + ($outtail % $RING)}]]
            set ch [format %c $v]
            puts -nonewline $ch
            append recent $ch
            incr outtail
        }
        flush stdout
        wr32 $OUTTAIL $outtail
        set tlast [clock seconds]
        # keep only the tail of the stream to scan for the completion marker
        if {[string length $recent] > 200} {
            set recent [string range $recent end-200 end]
        }
    } else {
        after 50
    }
    set now [clock seconds]
    # clean stop: firmware printed its final banner after the last kernel
    if {[string first $DONE_MARK $recent] >= 0} {
        puts "\nINFO: completion marker seen — all kernels ran, stopping capture."
        break
    }
    if {[expr {$now - $t0}] > $MAX_SECS} {
        puts "\nINFO: reached MAX_SECS ($MAX_SECS) — stopping capture."
        break
    }
    if {[expr {$now - $tlast}] > $IDLE_STOP && [expr {$now - $t0}] > 10} {
        puts "\nINFO: output idle for ${IDLE_STOP}s — stopping capture."
        break
    }
}
puts "INFO: ============================================================"
puts "INFO:  KERNEL SELF-TEST CAPTURE COMPLETE."
puts "INFO:  Look for 'bad=0' on every line = all ztachip kernels verified."
puts "INFO:  To return to the chatbot: bash run_resume_fw.sh (model still in DDR)"
puts "INFO: ============================================================"
