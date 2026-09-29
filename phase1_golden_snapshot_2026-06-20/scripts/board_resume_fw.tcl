# =============================================================================
# board_resume_fw.tcl  — RESUME after a successful model load
#
# Use this when the 141MB model is ALREADY in DDR (from a prior run that got
# through step [4]) and the board has stayed powered. It does NOT re-run
# ps7_init, does NOT reprogram the FPGA, and does NOT reload the model.
#
# It fixes the OCM-low-address trap (firmware @0x4000 was landing in OCM, not
# DDR), loads just the firmware, and opens the chatbot console.
#
#   bash run_resume_fw.sh
#
# If the model magic is gone (board was power-cycled), it aborts and tells you
# to run the full run_board_day.sh instead.
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set VEC      $ZTACHIP/SW/build/vector.bin
set MAIN     $ZTACHIP/SW/build/main.bin

set VEC_ADDR  0x00004000
set MAIN_ADDR 0x00100000
set ZUF_ADDR  0x10000000
set ZUF_MAGIC 0x4341545A             ;# 'ZTAC' little-endian = first word of "ZTACHIP!"

set SLCR_UNLOCK   0xF8000008
set FPGA_RST_CTRL 0xF8000240
set OCM_CFG       0xF8000910

# ---- Mailbox layout (must match soc.cpp) ----
set MBX      0x20000000
set MBX_MAGIC 0x5A544348
set OUTHEAD  [expr {$MBX + 0x40}]
set OUTTAIL  [expr {$MBX + 0x80}]
set INHEAD   [expr {$MBX + 0xC0}]
set INTAIL   [expr {$MBX + 0x100}]
set OUTBUF   [expr {$MBX + 0x1000}]
set INBUF    [expr {$MBX + 0x2000}]
set RING     4096

# --- Robust JTAG memory access -------------------------------------------------
# The Cortex-A9 debug context xsdb uses to read DDR occasionally goes stale
# ("Invalid context") under continuous console polling. A bare `mrd` then throws
# and kills the whole script. These wrappers catch that, re-select + re-halt the
# ARM core, and retry, so the console survives transient JTAG hiccups.
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
proc poke_byte {addr val} {
    set wa [expr {$addr & ~3}]
    set sh [expr {8 * ($addr & 3)}]
    set w [safe_mrd $wa]
    set w [expr {($w & ~(0xFF << $sh)) | (($val & 0xFF) << $sh)}]
    safe_mwr $wa $w
}
proc dow_data_progress {file addr {chunkMB 4}} {
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
        puts [format "INFO:     fw %3d%%  chunk %d/%d  %d/%d MB  %.0f KB/s  %ds" \
              $pct $i $n [expr {$loaded/1048576}] [expr {$total/1048576}] $rate $el]
        flush stdout
    }
    file delete -force $tmp
    puts "INFO:     firmware load DONE in [expr {[clock seconds]-$start}]s"
}

puts "INFO: ===== ZC702 RESUME (firmware only) ====="
foreach f [list $VEC $MAIN] { if {![file exists $f]} { puts "ERROR: missing $f"; return } }

# 1. connect, attach to ARM core (do NOT ps7_init / reprogram / reload model)
puts "INFO: \[1\] Connecting (reusing the model already in DDR)..."
connect
after 500
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {stop}

# 2. make sure VexRiscv is still held in reset before we touch DDR
puts "INFO: \[2\] Holding VexRiscv in reset..."
mwr $SLCR_UNLOCK   0x0000DF0D
mwr $FPGA_RST_CTRL 0x00000001

# 3. verify the model survived in DDR
puts "INFO: \[3\] Checking the model is still in DDR at $ZUF_ADDR..."
set m [rd32 $ZUF_ADDR]
if {$m != $ZUF_MAGIC} {
    puts "ERROR: model magic missing (read 0x[format %08X $m], expected 0x[format %08X $ZUF_MAGIC])."
    puts "ERROR: DDR was probably power-cycled. Run the FULL flow instead:"
    puts "ERROR:   bash $ZC702/run_board_day.sh"
    return
}
puts "INFO:     model OK (magic 0x[format %08X $m] present)."

# 4. map ALL OCM blocks LOW so 0x0..0x3FFFF is one contiguous OCM (no 0x30000
# hole). xsdb only writes this window when OCM is actually mapped here, and the
# OCM-low shadow applies to the VexRiscv's HP0 port too, so it reads the same
# bytes back. Default OCM_CFG=0x18 (block3 high = the hole) -> clear RAM_HI.
puts "INFO: \[4\] Mapping all OCM low (fills the 0x30000 hole)..."
set ocm [rd32 $OCM_CFG]
set newocm [expr {$ocm & ~0xF}]
mwr $OCM_CFG $newocm
puts "INFO:     OCM_CFG 0x[format %X $ocm] -> 0x[format %X [rd32 $OCM_CFG]]"

# 5. load firmware in two pieces (straddling the reserved gap):
#    vector stub -> OCM @0x4000,  main image -> DDR @0x100000
puts "INFO: \[5\] Loading vector stub ([file size $VEC] B) to $VEC_ADDR (OCM)..."
dow -data $VEC $VEC_ADDR
puts "INFO:     Loading main image (8.4MB) to $MAIN_ADDR (DDR)..."
dow_data_progress $MAIN $MAIN_ADDR 4

# 5b. read-back sanity on BOTH regions (first word must match each file)
proc check_word {file addr} {
    set f [open $file rb]; set d [read $f 4]; close $f
    binary scan $d iu e
    set g [lindex [mrd -value $addr] 0]
    if {($g & 0xFFFFFFFF) != ($e & 0xFFFFFFFF)} {
        puts "WARNING: read-back MISMATCH at [format 0x%08X $addr]: expected 0x[format %08X [expr {$e & 0xFFFFFFFF}]] got 0x[format %08X $g]"
        return 0
    }
    puts "INFO:     read-back OK at [format 0x%08X $addr] (0x[format %08X $g])"
    return 1
}
check_word $VEC  $VEC_ADDR
check_word $MAIN $MAIN_ADDR

# 5c. Clear the mailbox magic + ring pointers BEFORE releasing the CPU. The
# board stayed powered, so the previous run's magic/OUTTAIL are still in DDR.
# Without this, step [7] sees the OLD magic instantly and latches a STALE
# OUTTAIL, so it never tracks the new firmware's fresh ring -> console looks dead.
# Clearing magic forces [7] to wait for the NEW firmware to re-init the console.
puts "INFO: \[5c\] Clearing stale mailbox state (magic + ring pointers)..."
mwr $MBX        0x00000000
mwr $OUTHEAD    0x00000000
mwr $OUTTAIL    0x00000000
mwr $INHEAD     0x00000000
mwr $INTAIL     0x00000000

# 6. release VexRiscv
puts "INFO: \[6\] Releasing VexRiscv from reset -> chatbot booting..."
mwr $FPGA_RST_CTRL 0x00000000

# 7. wait for the DDR console handshake
puts "INFO: \[7\] Waiting for firmware to init the DDR console..."
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
# --- Host-side performance timing -------------------------------------------
# On-chip timers are dead in this bitstream, so we time each response on the PC
# wall clock. Valid because responses (<=160 tok ~640 B) fit the 4KB ring, so
# the firmware never stalls on the slow JTAG console; host elapsed ~= compute.
# Token counts come from the firmware's own output ("(tok=N" and "decode=K tok").
set respbuf ""
set t0 0
set timing 0
while 1 {
    set outhead [rd32 $OUTHEAD]
    if {$outhead != $outtail} {
        while {$outtail != $outhead} {
            set v [peek_byte [expr {$OUTBUF + ($outtail % $RING)}]]
            puts -nonewline [format %c $v]
            append respbuf [format %c $v]
            if {$v > 32} { set lastch [format %c $v] }
            incr outtail
        }
        flush stdout
        wr32 $OUTTAIL $outtail
    } else {
        if {$lastch eq ">"} {
            # the previous response just finished -> report host-side timing
            if {$timing} {
                set secs [expr {([clock milliseconds] - $t0)/1000.0}]
                set ntok 0; regexp {\(tok=([0-9]+)} $respbuf -> ntok
                set dtok 0; regexp {decode=([0-9]+) tok} $respbuf -> dtok
                if {$secs > 0.0 && $ntok > 0} {
                    # Every token = one full forward pass (prefill & decode cost the
                    # same, no batching), so total_passes/wall IS the true throughput.
                    set tps    [expr {$ntok/$secs}]
                    set mspt   [expr {1000.0*$secs/$ntok}]
                    puts ""
                    puts [format "INFO: \[HOST PERF\] wall=%.2fs  fwd_passes=%d  throughput=%.2f tok/s  %.0f ms/tok  (generated=%d tok)" \
                          $secs $ntok $tps $mspt $dtok]
                    flush stdout
                }
                set timing 0
            }
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
            # start timing this new prompt
            set respbuf ""
            set t0 [clock milliseconds]
            set timing 1
        } else {
            after 30
        }
    }
}
