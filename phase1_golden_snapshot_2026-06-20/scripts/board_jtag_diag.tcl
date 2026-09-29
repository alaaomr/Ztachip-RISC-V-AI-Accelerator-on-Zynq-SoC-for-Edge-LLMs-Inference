# Raw JTAG diagnostic — what does the cable actually see?
# Run:  bash run_jtag_diag.sh
connect
puts "INFO: ================= RAW JTAG SCAN CHAIN ================="
puts "INFO: 'jtag targets' = physical cables + devices on the chain:"
if {[catch {jtag targets} result]} { puts "jtag targets error: $result" } else { puts $result }
puts "INFO: ------------------------------------------------------"
puts "INFO: 'targets' = debug targets (CPUs):"
if {[catch {targets} result]} { puts "targets error: $result" } else { puts $result }
puts "INFO: ======================================================"
puts "INFO: If a cable is listed but NO device under it -> VREF/chain issue"
puts "INFO: (board JTAG header not powered, or chain routed elsewhere)."
puts "INFO: If a device shows with IDCODE -> chain OK, name-filter was wrong."
