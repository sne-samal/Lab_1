####################################################################
##
##  Place and route a synthesised netlist through to a finished layout.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
##      fc_shell -f scripts/pnr.tcl
##
##  Part 2 of the two-step flow. Reads the netlist from
##  scripts/syn_logical.tcl into a fresh physical library, floorplans
##  it, places it, then hands over to the shared back end.
##
####################################################################

set FLOW logical
source scripts/setup.tcl

lab_banner "Place and route: $DESIGN"

set_host_options -max_cores $MAX_CORES

if { ![file exists $SYNTH_V] } {
    error "No netlist at $SYNTH_V. Run scripts/syn_logical.tcl first."
}

if { [file exists $PNR_LIB] } { file delete -force $PNR_LIB }

create_lib $PNR_LIB -technology $TECH_FILE -ref_libs $REF_LIBS

# link_block resolves every instance against the reference libraries.
# A cell that cannot be found is reported here.
read_verilog -top $DESIGN $SYNTH_V
link_block

####################################################################
## Technology fix-ups
####################################################################
# The tech file gives every layer an "unknown" preferred direction and
# the site no symmetry, so the tool warns per layer and then guesses.
# Its guesses are right; setting them keeps the log readable.

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
# place_opt places, then optimises now that it knows where things are:
# resizing cells, buffering long nets and moving cells that turned out
# to be badly placed.
#
# PLACE-006 over utilization means the core is too small for the
# design. The message gives both numbers; lower CORE_UTIL to make the
# core bigger.

lab_banner "Placement"

redirect -tee -file $RPT_DIR/place_pre_check.rpt \
    {check_design -checks pre_placement_stage}

place_opt

# Logic needing a constant 1 or 0 cannot connect straight to the rail:
# the gate oxide it drives would see the supply directly. A tie cell
# provides the constant through a transistor instead.
add_tie_cells \
    -tie_high_lib_cells [get_lib_cells */$TIE_HI_CELL] \
    -tie_low_lib_cells  [get_lib_cells */$TIE_LO_CELL]

connect_pg_net -automatic

# Placement can leave cells overlapping while it optimises.
legalize_placement

redirect -tee -file $RPT_DIR/place_legality.rpt {check_legality}

# Reported, not gated. Every cell now has a location, so unlike at
# floorplan these two mean something. They are gated at finish.
redirect -tee -file $RPT_DIR/place_pg_drc.rpt          {check_pg_drc}
redirect -tee -file $RPT_DIR/place_pg_connectivity.rpt {check_pg_connectivity}

lab_reports place
lab_headline
save_block -label place
save_lib

source scripts/backend.tcl
