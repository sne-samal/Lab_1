####################################################################
##
##  Logical synthesis: RTL to a gate level netlist, no physical data.
##  The netlist and SDC it writes are the whole handoff to pnr.tcl.
##
##  Author:   Sne Samal
##  Version:  1.1
##  Date:     2026-09-05
##
##      fc_shell -f scripts/syn_logical.tcl
##
####################################################################

set FLOW logical
source scripts/setup.tcl

set_host_options -max_cores $MAX_CORES

# Recreated each run, so a stale block cannot be picked up.
if { [file exists $SYN_LIB] } { file delete -force $SYN_LIB }

create_lib $SYN_LIB -technology $TECH_FILE -ref_libs $REF_LIBS
report_ref_libs

# Must be set before the design is read.
set_non_physical_mode

analyze -format sverilog $RTL_FILES
elaborate $DESIGN
set_top_module $DESIGN

redirect -tee -file $RPT_DIR/synth_check.rpt \
    "check_design -checks netlist -log_file $RPT_DIR/synth_check_netlist.log"

set PHYSICAL 0
source scripts/mcmm.tcl

report_clocks

compile_logical

report_cells

lab_reports synth 0

write_verilog $SYNTH_V
write_sdc -output $SYNTH_SDC

save_block
save_lib
