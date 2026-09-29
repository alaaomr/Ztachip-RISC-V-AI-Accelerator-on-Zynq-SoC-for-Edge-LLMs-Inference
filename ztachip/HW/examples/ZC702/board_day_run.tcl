# =============================================================================
# board_day_run.tcl  — FULL board-day bring-up + JTAG-DDR chatbot console
#
# Run:  bash run_board_day.sh
#
# Does everything in one xsdb session:
#   1. connect + PS7 init (clocks + DDR)
#   2. hold VexRiscv in reset
#   3. program the FPGA (timing-clean bitstream)
#   4. load SMOLLM2.ZUF (model) and ztachip.bin (firmware) into DDR
#   5. release the VexRiscv -> chatbot boots
#   6. attach to the DDR mailbox at 0x20000000 and act as the console:
#        - prints the chatbot's output (read over JTAG)
#        - sends your typed prompts (written over JTAG)
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set PS7INIT $ZC702/ztachip_zc702.gen/sources_1/bd/zynq_system/ip/zynq_system_processing_system7_0_0/ps7_init.tcl
set BIT     $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
set ZUF     $ZTACHIP/models/SMOLLM2.ZUF
set VEC     $ZTACHIP/SW/build/vector.bin
set MAIN    $ZTACHIP/SW/build/main.bin

set VEC_ADDR  0x00004000
set MAIN_ADDR 0x00100000
set ZUF_ADDR  0x10000000
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
set INBUF    [expr {$MBX + 0x2000}]
set RING     4096

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
# byte access via word read-modify-write (portable, no -size dependency)
proc peek_byte {addr} {
    set wa [expr {$addr & ~3}]
    set sh [expr {8 * ($addr & 3)}]
    set w [safe_mrd $wa]
    return [expr {($w >> $sh) & 0xFF}]
}
proc poke_byte {addr val} {
    set wa [expr {$addr & ~3}]
    set sh [expr {8 * ($addr & 3)}]
    set w [safe_mrd $wa]
    set w [expr {($w & ~(0xFF << $sh)) | (($val & 0xFF) << $sh)}]
    safe_mwr $wa $w
}

# Load a big binary into DDR in chunks, printing a live progress line after each.
# `dow -data` has no progress flag, so we split the file (GNU `split`) into
# chunkMB-sized pieces and download each to base+offset. Prints percent, MB,
# throughput and elapsed time so a slow JTAG transfer is never a silent wait.
proc dow_data_progress {file addr {chunkMB 8}} {
    set total [file size $file]
    set tmp   /tmp/zta_chunks
    file delete -force $tmp
    file mkdir $tmp
    puts "INFO:     splitting [expr {$total/1048576}] MB into ${chunkMB} MB chunks..."
    exec split -b ${chunkMB}M $file $tmp/c_
    set chunks [lsort [glob $tmp/c_*]]
    set n      [llength $chunks]
    set cur    $addr
    set loaded 0
    set start  [clock seconds]
    set i 0
    foreach c $chunks {
        incr i
        set sz [file size $c]
        dow -data $c $cur
        set cur    [expr {$cur + $sz}]
        set loaded [expr {$loaded + $sz}]
        set pct    [expr {100 * $loaded / $total}]
        set el     [expr {[clock seconds] - $start}]
        set rate   [expr {$el > 0 ? $loaded / 1024.0 / $el : 0}]
        set eta    [expr {$rate > 0 ? ($total - $loaded) / 1024.0 / $rate : 0}]
        puts [format "INFO:     model %3d%%  chunk %d/%d  %d/%d MB  %.0f KB/s  %ds elapsed  ~%ds left" \
              $pct $i $n [expr {$loaded/1048576}] [expr {$total/1048576}] $rate $el [expr {int($eta)}]]
        flush stdout
    }
    file delete -force $tmp
    puts "INFO:     model load DONE in [expr {[clock seconds]-$start}]s"
}

puts "INFO: ===== ZC702 BOARD-DAY BRING-UP ====="
foreach f [list $PS7INIT $BIT $ZUF $VEC $MAIN] {
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

# 2. hold VexRiscv in reset BEFORE the PL comes up
puts "INFO: \[2\] Holding VexRiscv in reset..."
mwr $SLCR_UNLOCK   0x0000DF0D
mwr $FPGA_RST_CTRL 0x00000001

# 2b. Map ALL OCM blocks LOW so 0x0..0x3FFFF is one contiguous OCM (no 0x30000
# hole). The default OCM_CFG=0x18 maps block 3 high, leaving a hole that kills
# the firmware write at 0x30000. OCM-low shadows for the VexRiscv HP0 port too,
# so it reads the firmware's low part back from the same OCM.
puts "INFO: \[2b\] Mapping all OCM low (fills the 0x30000 hole)..."
set _ocm [lindex [mrd -value $OCM_CFG] 0]
mwr $OCM_CFG [expr {$_ocm & ~0xF}]
puts "INFO:     OCM_CFG 0x[format %X $_ocm] -> 0x[format %X [lindex [mrd -value $OCM_CFG] 0]]"

# 3. program FPGA
puts "INFO: \[3\] Programming FPGA..."
targets -set -filter {name =~ "xc7z020"}
fpga -file $BIT

# 4. load model + firmware into DDR
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
puts "INFO: \[4\] Loading model (141MB over JTAG - slow, watch the % below)..."
dow_data_progress $ZUF $ZUF_ADDR 8
puts "INFO:     Loading vector stub ([file size $VEC] B) to $VEC_ADDR (OCM)..."
dow -data $VEC $VEC_ADDR
puts "INFO:     Loading main image (8.4MB) to $MAIN_ADDR (DDR)..."
dow_data_progress $MAIN $MAIN_ADDR 4

# 4b. Clear the mailbox magic + ring pointers BEFORE releasing the CPU so step
# [6] waits for the NEW firmware to re-init the console (avoids latching a stale
# magic/OUTTAIL left in DDR from a prior run on a powered board).
puts "INFO: \[4b\] Clearing stale mailbox state (magic + ring pointers)..."
mwr $MBX        0x00000000
mwr $OUTHEAD    0x00000000
mwr $OUTTAIL    0x00000000
mwr $INHEAD     0x00000000
mwr $INTAIL     0x00000000

# 5. release VexRiscv
puts "INFO: \[5\] Releasing VexRiscv from reset -> chatbot booting..."
mwr $FPGA_RST_CTRL 0x00000000

# 6. console
puts "INFO: \[6\] Waiting for firmware to init the DDR console..."
set tries 0
while {[rd32 $MBX] != $MBX_MAGIC} {
    after 200
    incr tries
    if {$tries > 300} {
        puts "ERROR: console magic never appeared (firmware may not have booted)."
        puts "ERROR: magic\@$MBX = 0x[format %08X [rd32 $MBX]] (expected 0x$MBX_MAGIC)"
        return
    }
}
puts "INFO: ============================================================"
puts "INFO:  CHATBOT CONSOLE LIVE. Type a prompt and press Enter."
puts "INFO:  (the model is small - keep questions short)"
puts "INFO: ============================================================"

set outtail [rd32 $OUTTAIL]
set inhead  [rd32 $INHEAD]
set lastch ""

while 1 {
    set outhead [rd32 $OUTHEAD]
    if {$outhead != $outtail} {
        # drain all pending output bytes
        while {$outtail != $outhead} {
            set v [peek_byte [expr {$OUTBUF + ($outtail % $RING)}]]
            puts -nonewline [format %c $v]
            if {$v > 32} { set lastch [format %c $v] }
            incr outtail
        }
        flush stdout
        wr32 $OUTTAIL $outtail
    } else {
        # caught up: if the chatbot is at its '>' prompt, get a line from the user
        if {$lastch eq ">"} {
            set line [gets stdin]
            if {$line eq "" && [eof stdin]} { puts "\n(eof)"; return }
            foreach ch [split $line ""] {
                scan $ch %c code
                poke_byte [expr {$INBUF + ($inhead % $RING)}] $code
                incr inhead
            }
            poke_byte [expr {$INBUF + ($inhead % $RING)}] 10
            incr inhead
            wr32 $INHEAD $inhead
            set lastch ""
        } else {
            after 30
        }
    }
}
