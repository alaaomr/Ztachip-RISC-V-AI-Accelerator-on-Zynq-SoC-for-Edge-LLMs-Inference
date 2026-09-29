# =============================================================================
# board_benchmark.tcl  — automated Jetson-format benchmark over the JTAG console
#
# Drives the SmolLM2-135M chatbot on ZC702 through a fixed prompt set and writes
# results in the SAME schema the teammate used on the Jetson TX1, so the two are
# directly comparable.
#
# Run via:  bash run_board_benchmark.sh <full|resume> <smoke|N>
#   full   : connect, program PMU bitstream, load model+firmware, then benchmark
#   resume : board already powered & model in DDR -> just re-attach and benchmark
#   smoke  : 1 prompt, 1 repeat (validate the harness fast)
#   N      : run N repeats over all 30 prompts (Jetson used 5)
#
# Reads  : bench/bench_prompts.tsv   (prompt_id <TAB> category <TAB> prompt)
# Writes : bench/results/results_ZC702_SmolLM2-135M.csv   (Jetson schema + PMU cols)
#          bench/results/raw_runs_ZC702.txt               (per-run text for JSON)
#          bench/results/bench_console.log                (full console transcript)
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set PS7INIT $ZC702/ztachip_zc702.gen/sources_1/bd/zynq_system/ip/zynq_system_processing_system7_0_0/ps7_init.tcl
set BIT     $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
set ZUF     $ZTACHIP/models/SMOLLM2.ZUF
set VEC     $ZTACHIP/SW/build/vector.bin
set MAIN    $ZTACHIP/SW/build/main.bin

set BENCHDIR  $ZC702/bench
set PROMPTS   $BENCHDIR/bench_prompts.tsv
set OUTDIR    $BENCHDIR/results
set CSV       $OUTDIR/results_ZC702_SmolLM2-135M.csv
set RAW       $OUTDIR/raw_runs_ZC702.txt
set TRANSCRIPT $OUTDIR/bench_console.log

# Identity columns for the CSV (mirror Jetson's model/hardware fields)
set MODEL_NAME "SmolLM2-135M-Instruct-Q4ZUF"
set HW_NAME    "ZC702_ztachip"

# ---- mode + scope from env (set by the shell wrapper) ----
set MODE   [expr {[info exists ::env(BENCH_MODE)]   ? $::env(BENCH_MODE)   : "full"}]
set SCOPE  [expr {[info exists ::env(BENCH_SCOPE)]  ? $::env(BENCH_SCOPE)  : "smoke"}]
if {$SCOPE eq "smoke"} {
    set REPEATS 1 ; set SMOKE 1
} else {
    set REPEATS $SCOPE ; set SMOKE 0
}

set VEC_ADDR  0x00004000
set MAIN_ADDR 0x00100000
set ZUF_ADDR  0x10000000
set SLCR_UNLOCK   0xF8000008
set FPGA_RST_CTRL 0xF8000240
set OCM_CFG       0xF8000910

# ---- Mailbox layout (must match soc.cpp / board_day_run.tcl) ----
set MBX      0x20000000
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
        retarget_arm ; after 30
    }
    error "safe_mrd failed at [format 0x%08X $addr]: $err"
}
proc safe_mwr {addr val} {
    for {set i 0} {$i < 20} {incr i} {
        if {![catch {mwr $addr $val} err]} { return }
        retarget_arm ; after 30
    }
    error "safe_mwr failed at [format 0x%08X $addr]: $err"
}
proc rd32 {addr} { return [safe_mrd $addr] }
proc wr32 {addr val} { safe_mwr $addr $val }
proc peek_byte {addr} {
    set wa [expr {$addr & ~3}] ; set sh [expr {8 * ($addr & 3)}]
    set w [safe_mrd $wa] ; return [expr {($w >> $sh) & 0xFF}]
}
proc poke_byte {addr val} {
    set wa [expr {$addr & ~3}] ; set sh [expr {8 * ($addr & 3)}]
    set w [safe_mrd $wa]
    set w [expr {($w & ~(0xFF << $sh)) | (($val & 0xFF) << $sh)}]
    safe_mwr $wa $w
}
proc dow_data_progress {file addr {chunkMB 8}} {
    set total [file size $file] ; set tmp /tmp/zta_chunks
    file delete -force $tmp ; file mkdir $tmp
    puts "INFO:     splitting [expr {$total/1048576}] MB into ${chunkMB} MB chunks..."
    exec split -b ${chunkMB}M $file $tmp/c_
    set chunks [lsort [glob $tmp/c_*]] ; set n [llength $chunks]
    set cur $addr ; set loaded 0 ; set start [clock seconds] ; set i 0
    foreach c $chunks {
        incr i ; set sz [file size $c] ; dow -data $c $cur
        set cur [expr {$cur + $sz}] ; set loaded [expr {$loaded + $sz}]
        set pct [expr {100 * $loaded / $total}] ; set el [expr {[clock seconds] - $start}]
        set rate [expr {$el > 0 ? $loaded / 1024.0 / $el : 0}]
        puts [format "INFO:     model %3d%%  %d/%d MB  %.0f KB/s  %ds" \
              $pct [expr {$loaded/1048576}] [expr {$total/1048576}] $rate $el]
        flush stdout
    }
    file delete -force $tmp
    puts "INFO:     model load DONE in [expr {[clock seconds]-$start}]s"
}

# --- global console cursors + transcript handle -------------------------------
set ::outtail 0
set ::inhead  0
set ::tfh ""

# Drain currently-available console bytes, append to var `bufName`, echo+log them.
proc drain_console {bufName} {
    upvar 1 $bufName buf
    set outhead [rd32 $::OUTHEAD]
    while {$::outtail != $outhead} {
        set v [peek_byte [expr {$::OUTBUF + ($::outtail % $::RING)}]]
        set ch [format %c $v]
        append buf $ch
        puts -nonewline $ch
        if {$::tfh ne ""} { puts -nonewline $::tfh $ch }
        incr ::outtail
    }
    flush stdout
    wr32 $::OUTTAIL $::outtail
}

# Wait until the chatbot returns to its '>' prompt (optionally requiring that the
# [PMU] end-of-response marker was already seen). Returns the collected text.
proc read_until_prompt {{needPmu 1} {timeoutS 240}} {
    set buf "" ; set sawPmu 0 ; set start [clock seconds]
    while 1 {
        drain_console buf
        if {$needPmu && !$sawPmu && [string match "*\[PMU\]*" $buf]} { set sawPmu 1 }
        # ready for next prompt = a '>' appears AFTER the PMU line (or no PMU needed)
        if {(!$needPmu || $sawPmu)} {
            set tail [string range $buf end-3 end]
            if {[string first ">" $tail] >= 0} { break }
        }
        if {([clock seconds] - $start) > $timeoutS} {
            puts "\nWARN: timeout waiting for '>' (got [string length $buf] bytes)"
            break
        }
        after 25
    }
    return $buf
}

# Send one line of text to the firmware's getInput() (writes INBUF ring + NL).
proc send_line {text} {
    foreach ch [split $text ""] {
        scan $ch %c code
        poke_byte [expr {$::INBUF + ($::inhead % $::RING)}] $code
        incr ::inhead
    }
    poke_byte [expr {$::INBUF + ($::inhead % $::RING)}] 10
    incr ::inhead
    wr32 $::INHEAD $::inhead
}

# ============================ BRING-UP ========================================
file mkdir $OUTDIR
foreach f [list $PS7INIT $BIT $ZUF $VEC $MAIN $PROMPTS] {
    if {![file exists $f]} { puts "ERROR: missing $f"; return }
}
puts "INFO: ===== ZC702 BENCHMARK ($MODE / $SCOPE, repeats=$REPEATS) ====="

connect ; after 500
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}

if {$MODE eq "full"} {
    puts "INFO: \[1\] PS7 init (clocks + DDR)..."
    source $PS7INIT ; ps7_init ; ps7_post_config
    puts "INFO: \[2\] Hold VexRiscv in reset + map OCM low..."
    mwr $SLCR_UNLOCK 0x0000DF0D ; mwr $FPGA_RST_CTRL 0x00000001
    set _ocm [lindex [mrd -value $OCM_CFG] 0] ; mwr $OCM_CFG [expr {$_ocm & ~0xF}]
    puts "INFO: \[3\] Program FPGA (PMU bitstream)..."
    targets -set -filter {name =~ "xc7z020"} ; fpga -file $BIT
    targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
    puts "INFO: \[4\] Load model + firmware into DDR..."
    dow_data_progress $ZUF $ZUF_ADDR 8
    dow -data $VEC $VEC_ADDR
    dow_data_progress $MAIN $MAIN_ADDR 4
    puts "INFO: \[4b\] Clear stale mailbox..."
    mwr $MBX 0 ; mwr $OUTHEAD 0 ; mwr $OUTTAIL 0 ; mwr $INHEAD 0 ; mwr $INTAIL 0
    puts "INFO: \[5\] Release VexRiscv -> chatbot booting..."
    mwr $FPGA_RST_CTRL 0x00000000
} elseif {$MODE eq "reprog"} {
    # Reprogram a NEW bitstream but KEEP the model+firmware already resident in DDR.
    # DDR is owned by the PS (hardened) and survives PL reconfiguration, so there is
    # no ~40 min model reload. VexRiscv is held in reset during reconfig.
    puts "INFO: \[reprog\] New bitstream, KEEPING model+firmware in DDR (no reload)..."
    mwr $SLCR_UNLOCK 0x0000DF0D ; mwr $FPGA_RST_CTRL 0x00000001
    set _ocm [lindex [mrd -value $OCM_CFG] 0] ; mwr $OCM_CFG [expr {$_ocm & ~0xF}]
    puts "INFO:     programming FPGA (model at 0x10000000 untouched)..."
    targets -set -filter {name =~ "xc7z020"} ; fpga -file $BIT
    targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
    puts "INFO:     reloading firmware (vector+main, ~3 min; model stays in DDR)..."
    dow -data $VEC $VEC_ADDR
    dow_data_progress $MAIN $MAIN_ADDR 4
    puts "INFO:     clearing mailbox + releasing VexRiscv..."
    mwr $MBX 0 ; mwr $OUTHEAD 0 ; mwr $OUTTAIL 0 ; mwr $INHEAD 0 ; mwr $INTAIL 0
    mwr $FPGA_RST_CTRL 0x00000000
} else {
    puts "INFO: RESUME mode -- assuming model+firmware already live in DDR."
}

puts "INFO: \[6\] Waiting for console magic..."
set tries 0
while {[rd32 $MBX] != $MBX_MAGIC} {
    after 200 ; incr tries
    if {$tries > 600} { puts "ERROR: console magic never appeared."; return }
}
# sync cursors to current ring state
set ::outtail [rd32 $OUTTAIL]
set ::inhead  [rd32 $INHEAD]
set ::tfh [open $TRANSCRIPT a]
puts $::tfh "\n===== benchmark session [clock format [clock seconds]] mode=$MODE scope=$SCOPE ====="

# consume the boot banner up to the first '>'
puts "INFO: draining boot banner to first '>' ..."
read_until_prompt 0 60

# ============================ BENCHMARK LOOP ==================================
# load prompts
set plist {}
set pf [open $PROMPTS r]
foreach ln [split [read $pf] "\n"] {
    if {[string trim $ln] eq ""} continue
    set parts [split $ln "\t"]
    lappend plist [list [lindex $parts 0] [lindex $parts 1] [join [lrange $parts 2 end] "\t"]]
}
close $pf
if {$SMOKE} { set plist [list [lindex $plist 0]] }

# open output files
set csvfh [open $CSV w]
puts $csvfh "repeat,prompt_id,category,gen_tokens,wall_time_s,tps,model,hardware,inf_start_ts,inf_end_ts,ttft_ms,ddr_rd_mbs,rd_stall_pct,rd_active_pct,bytes_per_tok"
set rawfh [open $RAW w]

set runIdx 0 ; set nTotal [expr {$REPEATS * [llength $plist]}]
for {set rep 1} {$rep <= $REPEATS} {incr rep} {
    foreach p $plist {
        incr runIdx
        set pid  [lindex $p 0] ; set cat [lindex $p 1] ; set ptext [lindex $p 2]
        puts "\nINFO: ---- \[$runIdx/$nTotal\] repeat=$rep $pid ($cat) ----"
        if {$::tfh ne ""} { puts $::tfh "\n--- run $runIdx repeat=$rep $pid ---\nPROMPT: $ptext" }
        set t_start [expr {[clock milliseconds]/1000.0}]
        send_line $ptext
        set buf [read_until_prompt 1 240]

        # ---- parse on-chip PERF/PMU numbers ----
        set gen 0 ; set tps 0.0 ; set ttft 0.0
        set mbs 0.0 ; set stall 0.0 ; set act 0.0 ; set bpt 0.0
        if {[regexp {decode=(\d+) tok / ([0-9.]+) tok/s} $buf -> g t]} { set gen $g ; set tps $t }
        regexp {TTFT\(prefill\)=([0-9.]+) ms} $buf -> ttft
        regexp {DDR_rd=([0-9.]+) MB/s} $buf -> mbs
        regexp {rd_stall=([0-9.]+)%} $buf -> stall
        regexp {rd_active=([0-9.]+)%} $buf -> act
        regexp {bytes/tok=([0-9.]+)} $buf -> bpt
        set wall [expr {$tps > 0 ? $gen / $tps : 0.0}]
        set t_end [expr {$t_start + $wall}]

        puts $csvfh [format "%d,%s,%s,%d,%.3f,%.2f,%s,%s,%.3f,%.3f,%.1f,%.1f,%.1f,%.1f,%.0f" \
            $rep $pid $cat $gen $wall $tps $::MODEL_NAME $::HW_NAME $t_start $t_end \
            $ttft $mbs $stall $act $bpt]
        flush $csvfh

        # ---- store cleaned response text for JSON build ----
        # strip echoed prompt + trailing [PERF]/[PMU]/(tok=) lines
        set resp $buf
        set cut [string first "\n\[PERF\]" $resp]
        if {$cut < 0} { set cut [string first "\[PERF\]" $resp] }
        if {$cut >= 0} { set resp [string range $resp 0 [expr {$cut-1}]] }
        puts $rawfh "===RUN\t$rep\t$pid\t$cat"
        puts $rawfh "PROMPT\t$ptext"
        puts $rawfh "OUTPUT_BEGIN"
        puts $rawfh $resp
        puts $rawfh "OUTPUT_END"
        flush $rawfh
        puts "INFO:     -> gen=$gen tok  tps=$tps  wall=[format %.2f $wall]s  stall=${stall}%  bytes/tok=$bpt"
    }
}
close $csvfh ; close $rawfh
if {$::tfh ne ""} { close $::tfh }
puts "\nINFO: ============================================================"
puts "INFO:  BENCHMARK DONE.  $runIdx runs."
puts "INFO:  CSV : $CSV"
puts "INFO:  RAW : $RAW"
puts "INFO:  Next: python3 $BENCHDIR/summarize.py"
puts "INFO: ============================================================"
