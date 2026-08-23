####################################################################
##
##  Logical synthesis: RTL to a gate level netlist, no physical data.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
##      fc_shell -f scripts/syn_logical.tcl
##
##  Part 1 of the two-step flow. Every wire is assumed to have zero
##  delay, so the timing here is optimistic. The netlist and SDC it
##  writes are the whole handoff to scripts/pnr.tcl.
##
####################################################################

set FLOW logical
source scripts/setup.tcl

lab_banner "Logical synthesis: $DESIGN"

set_host_options -max_cores $MAX_CORES

# Deleted and recreated each run. A stale block from an earlier run is
# a confusing thing to debug.
if { [file exists $SYN_LIB] } { file delete -force $SYN_LIB }

create_lib $SYN_LIB -technology $TECH_FILE -ref_libs $REF_LIBS

report_ref_libs

# Must be set before the design is read.
set_non_physical_mode

####################################################################
## Read the design
####################################################################
# analyze checks the HDL, elaborate builds the design from it. Read
# the elaboration report: it names every register it inferred, and one
# you did not expect is the earliest sign of an RTL bug.

analyze -format sverilog $RTL_FILES
elaborate $DESIGN
set_top_module $DESIGN

set PHYSICAL 0
source scripts/mcmm.tcl

report_clocks

####################################################################
## Synthesise
####################################################################

lab_banner "compile_logical"

compile_logical

lab_reports synth 0
lab_headline

####################################################################
## Export
####################################################################

write_verilog $SYNTH_V
write_sdc -output $SYNTH_SDC

save_block
save_lib

puts ""
puts "  netlist     : $SYNTH_V"
puts "  constraints : $SYNTH_SDC"
puts "  next        : fc_shell -f scripts/pnr.tcl"
