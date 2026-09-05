####################################################################
##
##  Place and route a synthesised netlist through to a finished
##  layout. Reads the netlist written by syn_logical.tcl.
##
##  Author:   Sne Samal
##  Version:  1.1
##  Date:     2026-09-05
##
##      fc_shell -f scripts/pnr.tcl
##
####################################################################

set FLOW logical
source scripts/setup.tcl

set_host_options -max_cores $MAX_CORES

if { ![file exists $SYNTH_V] } {
    error "No netlist at $SYNTH_V. Run scripts/syn_logical.tcl first."
}

if { [file exists $PNR_LIB] } { file delete -force $PNR_LIB }

create_lib $PNR_LIB -technology $TECH_FILE -ref_libs $REF_LIBS

read_verilog -top $DESIGN $SYNTH_V
link_block

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

source scripts/floorplan.tcl

####################################################################
## Placement
####################################################################
# PLACE-006 over utilization means the core is too small: lower
# CORE_UTIL in scripts/setup.tcl.

redirect -tee -file $RPT_DIR/place_pre_check.rpt \
    "check_design -checks pre_placement_stage -log_file $RPT_DIR/place_check.log"

place_opt

# Constants need a tie cell rather than a direct connection to a rail,
# and anything that inserts cells has to reconnect power afterwards.
add_tie_cells \
    -tie_high_lib_cells [get_lib_cells */$TIE_HI_CELL] \
    -tie_low_lib_cells  [get_lib_cells */$TIE_LO_CELL]

connect_pg_net -automatic

legalize_placement

redirect -tee -file $RPT_DIR/place_legality.rpt        {check_legality}
redirect -tee -file $RPT_DIR/place_pg_drc.rpt          {check_pg_drc}
redirect -tee -file $RPT_DIR/place_pg_connectivity.rpt {check_pg_connectivity}

lab_reports place
save_block -label place
save_lib

source scripts/backend.tcl
