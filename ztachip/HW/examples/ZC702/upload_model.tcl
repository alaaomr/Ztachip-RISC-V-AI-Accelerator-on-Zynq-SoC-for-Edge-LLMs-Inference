# =============================================================================
# upload_model.tcl  --  Upload ONE (large) model into DDR over JTAG. Nothing else.
#
# Run via:   bash upload_model.sh [q4|q8|360m|<path>] [prog]
#   (the wrapper sets UP_ZUF, and UP_PROG=1 if you pass "prog")
#
# What it does (minimum needed to get bytes safely into DDR):
#   1. connect + ps7_init        -> brings up PS clocks + DDR controller
#   2. hold VexRiscv in reset    -> so the CPU can't touch DDR while we load
#   3. (optional) program FPGA   -> only if UP_PROG=1
#   4. dow the model into DDR at 0x10000000, with a live % / MB/s progress line
#   5. leave VexRiscv HELD IN RESET and exit
#
# After this you do NOT re-run the heavy model load. This script loaded ONLY the
# model -- the bitstream + firmware are NOT loaded yet (unless you passed 'prog').
# Bring the chatbot up WITHOUT reloading the model with the 'reprog' mode, which
# programs the bitstream + firmware but keeps the model at 0x10000000 untouched:
#   bash run_model.sh <q4|q8|360m> 1 reprog
# (use 'resume' only if a prior full run already left bitstream+firmware live.)
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set PS7INIT $ZC702/ztachip_zc702.gen/sources_1/bd/zynq_system/ip/zynq_system_processing_system7_0_0/ps7_init.tcl
set BIT     $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit

# model file comes from the wrapper (UP_ZUF); default = the large 360M model
set ZUF [expr {[info exists ::env(UP_ZUF)] ? $::env(UP_ZUF) : "$ZTACHIP/models/SMOLLM2_360M_Q4.ZUF"}]
set PROG [expr {[info exists ::env(UP_PROG)] ? $::env(UP_PROG) : 0}]
# JTAG clock for the download. Default 15 MHz (same as board_benchmark.tcl) is
# ~10x faster than the slow cable default. Lower it if you get dow/mrd errors:
#   UP_JTAG_HZ=10000000 bash upload_model.sh ...
set JTAG_FREQ [expr {[info exists ::env(UP_JTAG_HZ)] ? $::env(UP_JTAG_HZ) : 15000000}]

# ---- addresses (identical to board_day_run.tcl / board_benchmark.tcl) ----
set ZUF_ADDR      0x10000000
set SLCR_UNLOCK   0xF8000008
set FPGA_RST_CTRL 0xF8000240

# --- Robust JTAG memory access (survives transient "Invalid context") ---------
proc retarget_arm {} {
    catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
    catch {stop}
}
proc safe_mwr {addr val} {
    for {set i 0} {$i < 20} {incr i} {
        if {![catch {mwr $addr $val} err]} { return }
        retarget_arm
        after 30
    }
    error "safe_mwr failed at [format 0x%08X $addr]: $err"
}

# Load a big binary into DDR in chunks, printing a live progress line after each.
# `dow -data` has no progress flag, so we split the file into chunkMB pieces and
# download each to base+offset. Prints percent, MB, throughput and ETA so a slow
# JTAG transfer is never a silent wait.
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

puts "INFO: ===== ZC702 MODEL UPLOAD ====="
if {![file exists $ZUF]}     { puts "ERROR: missing model $ZUF"; return }
if {![file exists $PS7INIT]} { puts "ERROR: missing $PS7INIT";  return }
if {$PROG && ![file exists $BIT]} { puts "ERROR: missing bitstream $BIT"; return }
puts "INFO: model = [file tail $ZUF]  ([file size $ZUF] bytes)  -> DDR @ $ZUF_ADDR"

# 1. connect + PS7 (clocks + DDR)
puts "INFO: \[1\] Connect + ps7_init (clocks + DDR)..."
connect
after 500
# Bump the JTAG clock BEFORE any dow (select the cable target, level==0).
# This is what makes the upload ~10x faster than the slow default.
if {[catch {
    jtag targets -set -filter {level==0}
    jtag frequency $JTAG_FREQ
} jerr]} {
    puts "WARN: JTAG frequency bump failed ($jerr) -- continuing at slow default speed."
} else {
    puts "INFO:     JTAG clock set -> [jtag frequency] Hz (was the slow default)"
}
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
source $PS7INIT
ps7_init
ps7_post_config

# 2. hold VexRiscv in reset so it can't touch DDR during the load
puts "INFO: \[2\] Holding VexRiscv in reset..."
safe_mwr $SLCR_UNLOCK   0x0000DF0D
safe_mwr $FPGA_RST_CTRL 0x00000001

# 3. optional FPGA program
if {$PROG} {
    puts "INFO: \[3\] Programming FPGA (UP_PROG=1)..."
    targets -set -filter {name =~ "xc7z020"}
    fpga -file $BIT
    targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
} else {
    puts "INFO: \[3\] Skipping FPGA program (set UP_PROG=1 / pass 'prog' to enable)."
}

# 4. the actual upload
puts "INFO: \[4\] Uploading model over JTAG (large file - watch the % below)..."
dow_data_progress $ZUF $ZUF_ADDR 8

# 5. done -- leave VexRiscv held in reset
puts "INFO: ============================================================"
puts "INFO:  MODEL IN DDR @ $ZUF_ADDR. VexRiscv still held in reset."
puts "INFO:  Bitstream + firmware are NOT loaded yet -> use 'reprog' (keeps model):"
puts "INFO:  Next:  bash run_model.sh <q4|q8|360m> 1 reprog   (bitstream+fw, NO model reload)"
puts "INFO:  (use 'resume' only if a prior full run already left bitstream+fw live)"
puts "INFO: ============================================================"
