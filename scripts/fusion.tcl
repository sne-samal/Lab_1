####################################################################
##
##  Physical synthesis: RTL to a finished layout in one session.
##  Synthesis places cells as it maps them, so there is no netlist
##  handoff and the placement carries through to the router.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
##      fc_shell -f scripts/fusion.tcl
##
####################################################################

set FLOW fusion
source scripts/setup.tcl

lab_banner "Physical synthesis: $DESIGN"

set_host_options -max_cores $MAX_CORES

if { [file exists $PNR_LIB] } { file delete -force $PNR_LIB }

create_lib $PNR_LIB -technology $TECH_FILE -ref_libs $REF_LIBS

report_ref_libs

####################################################################
## Read the design
####################################################################
# No set_non_physical_mode, which is the whole difference from
# scripts/syn_logical.tcl.

analyze -format sverilog $RTL_FILES
elaborate $DESIGN
set_top_module $DESIGN

# Catches a missing module or dangling logic before a synthesis run
# is spent on it.
redirect -tee -file $RPT_DIR/synth_check.rpt \
    "check_design -checks netlist -log_file $RPT_DIR/synth_check_netlist.log"

####################################################################
## Technology fix-ups
####################################################################
# The tech file leaves layer directions and site symmetry unset, so
# the tool warns per layer and then guesses.

suppress_message ATTR-12
set_attribute [get_layers $HORIZONTAL_LAYERS] routing_direction horizontal
set_attribute [get_layers $VERTICAL_LAYERS]   routing_direction vertical
set_attribute [get_site_defs $SITE_NAME] symmetry "$SITE_SYMMETRY"
unsuppress_message ATTR-12

set PHYSICAL 1
source scripts/mcmm.tcl

report_clocks

####################################################################
## Map, then floorplan
####################################################################
# compile_fusion runs initial_map, logic_opto, initial_place,
# initial_drc, initial_opto, final_place, final_opto. It is split
# around the floorplan because a core sized by utilization needs a
# real cell area to size itself against.

lab_banner "compile_fusion -to logic_opto"

compile_fusion -to logic_opto

lab_reports synth 0
lab_headline

source scripts/floorplan.tcl

####################################################################
## Place and optimise
####################################################################

lab_banner "compile_fusion -from initial_place"

redirect -tee -file $RPT_DIR/place_pre_check.rpt \
    "check_design -checks pre_placement_stage -log_file $RPT_DIR/place_check.log"

compile_fusion -from initial_place -to final_opto

# Constants need a tie cell rather than a direct connection to a rail.
add_tie_cells \
    -tie_high_lib_cells [get_lib_cells */$TIE_HI_CELL] \
    -tie_low_lib_cells  [get_lib_cells */$TIE_LO_CELL]

connect_pg_net -automatic

legalize_placement

redirect -tee -file $RPT_DIR/place_legality.rpt        {check_legality}
redirect -tee -file $RPT_DIR/place_pg_drc.rpt          {check_pg_drc}
redirect -tee -file $RPT_DIR/place_pg_connectivity.rpt {check_pg_connectivity}

lab_reports place
lab_headline
save_block -label place
save_lib

source scripts/backend.tcl
