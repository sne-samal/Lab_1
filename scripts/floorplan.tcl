####################################################################
##
##  Core area, power grid, tap cells and pin placement.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
##  Sourced by pnr.tcl and fusion.tcl once the design is mapped, so
##  both flows get the same floorplan from the same numbers.
##
####################################################################

lab_banner "Floorplan"

# -side_ratio takes proportions, not sizes: {1 $ASPECT} gives a core
# whose height is ASPECT times its width.
initialize_floorplan \
    -site_def         $SITE_NAME \
    -core_utilization $CORE_UTIL \
    -side_ratio       [list 1 $ASPECT] \
    -core_offset      $CORE_OFFSET

report_utilization

puts ""
puts "  utilization : $CORE_UTIL"
puts "  aspect      : $ASPECT"
puts "  core offset : $CORE_OFFSET um"
puts "  boundary    : [get_attribute [current_block] boundary]"

####################################################################
## Power and ground nets
####################################################################
# A gate has two pins in RTL and four in silicon. The netlist says
# nothing about power, so the nets and every cell's connection to them
# are made here.

if { [sizeof_collection [get_nets -quiet $PWR_NET]] == 0 } {
    create_net -power $PWR_NET
}
if { [sizeof_collection [get_nets -quiet $GND_NET]] == 0 } {
    create_net -ground $GND_NET
}

connect_pg_net -automatic

####################################################################
## Power plan
####################################################################
# Rails: one wire per cell row on M1, which is what the cells connect
# to. Ring: a loop around the core bringing current in from the edge,
# each segment on a layer running its preferred direction.

lab_banner "Power plan"

# -mark_as_follow_pin marks these as the row rail structure rather
# than ordinary metal, and -check_std_cell_drc has compile_pg check
# the rail against cell pins as it builds. Both default to false, and
# without them the rail reports end-of-line spacing violations against
# signal pins inside the cells it runs through.
create_pg_std_cell_conn_pattern rail_pattern \
    -layers              $RAIL_LAYER \
    -mark_as_follow_pin  true \
    -check_std_cell_drc  true

# Rails and ring are separate strategies and nothing joins them, so
# "stop: first_target" runs the rails out to the ring.
set_pg_strategy rail_strategy -core \
    -pattern   [list [list pattern: rail_pattern] \
                     [list nets: [list $PWR_NET $GND_NET]]] \
    -extension [list [list stop: first_target]]

create_pg_ring_pattern ring_pattern \
    -horizontal_layer   $RING_H_LAYER \
    -horizontal_width   [list $RING_WIDTH] \
    -horizontal_spacing [list $RING_SPACING] \
    -vertical_layer     $RING_V_LAYER \
    -vertical_width     [list $RING_WIDTH] \
    -vertical_spacing   [list $RING_SPACING]

# Nets are laid innermost first, so this puts VSS beside the core and
# VDD outside it.
#
# Extending to the die boundary generates the block's power pins.
# Without them routing warns that VDD and VSS are unplaced, check_lvs
# skips both supplies and the LEF abstract has no power pins.
set_pg_strategy ring_strategy -core \
    -pattern   [list [list pattern: ring_pattern] \
                     [list nets: [list $GND_NET $PWR_NET]] \
                     [list offset: [list $RING_OFFSET $RING_OFFSET]]] \
    -extension [list [list [list nets: [list $GND_NET $PWR_NET]] \
                           [list stop: design_boundary_and_generate_pin]]]

# Rails are on M1 and the ring on M2 and M3, so every rail-to-ring
# connection is a via. Without a rule compile_pg warns PGR-095 and
# connects the layers however it sees fit.
set_pg_strategy_via_rule pg_via_rule \
    -via_rule [list [list intersection: adjacent] [list via_master: default]]

# Ring first, so the rails have something to stop at.
compile_pg -strategies ring_strategy -via_rule pg_via_rule
compile_pg -strategies rail_strategy -via_rule pg_via_rule

connect_pg_net

####################################################################
## Tap cells
####################################################################
# Tap cells tie the substrate and wells to the supplies. Too far apart
# and the parasitic transistors between neighbouring devices can latch
# up, shorting supply to ground until power is removed. The spacing is
# a foundry rule, not a preference.

lab_banner "Tap cells"

create_tap_cells \
    -lib_cell [get_lib_cells */$TAP_CELL] \
    -distance $TAP_DISTANCE \
    -pattern  stagger

####################################################################
## Pins
####################################################################
# -self places this block's own pins, not those of any child block.

place_pins -self

# Reported, not gated. Nothing is placed yet, so cells sit stacked on
# each other outside the core and one cell's VDD pin overlaps
# another's VSS. What is worth checking here is the grid itself.
redirect -tee -file $RPT_DIR/floorplan_pg_connectivity.rpt \
    {check_pg_connectivity -check_std_cell_pins none}

save_block -label floorplan
save_lib
