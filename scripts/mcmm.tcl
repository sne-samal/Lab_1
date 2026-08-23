####################################################################
##
##  Modes, corners and scenarios, and the constraints read into them.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
##  Sourced once the block exists. The caller sets PHYSICAL to 1 or 0
##  first, since parasitics only mean something once cells have a
##  location.
##
##    mode      what the chip is doing. One here, "func".
##    corner    process, voltage, temperature and the RC data with it.
##    scenario  a mode analysed at a corner. Timing runs on these.
##
####################################################################

if { ![info exists PHYSICAL] } {
    error "Set PHYSICAL to 1 or 0 before sourcing mcmm.tcl"
}

# The tool makes a default mode, corner and scenario with no process
# label and no parasitics. Left in place, a design can appear to pass
# at a corner that does not exist.
catch {remove_scenarios -all}
catch {remove_corners   -all}
catch {remove_modes     -all}

####################################################################
## Parasitics
####################################################################

if { $PHYSICAL } {
    read_parasitic_tech -tlup $TLUPLUS_MAX -name rcworst
    read_parasitic_tech -tlup $TLUPLUS_TYP -name rctyp
    read_parasitic_tech -tlup $TLUPLUS_MIN -name rcbest
}

array set RC_SPEC {
    wc rcworst
    tc rctyp
    bc rcbest
}

####################################################################
## Mode and corners
####################################################################
# The process label selects a characterisation point inside the
# reference library. The labels were assigned when the NDM was built.

create_mode func
current_mode func

foreach corner $CORNER_LABELS {
    create_corner $corner
    current_corner $corner

    set_process_label $corner
    set_temperature   $CORNER_TEMP($corner)
    set_voltage $CORNER_VOLTAGE($corner) -object_list $PWR_NET
    set_voltage 0.0                      -object_list $GND_NET

    if { $PHYSICAL } {
        set_parasitic_parameters \
            -late_spec  $RC_SPEC($corner) \
            -early_spec $RC_SPEC($corner)
    }

    create_scenario -name func_$corner -mode func -corner $corner
}

####################################################################
## Constraints
####################################################################
# The same SDC into every scenario. They differ by corner, not by what
# the design is being asked to do.

foreach corner $CORNER_LABELS {
    current_scenario func_$corner
    read_sdc $SDC_FILE

    # The one constraint that names a library cell, so it comes from
    # the kit. Without it the inputs are assumed to be driven by
    # something infinitely strong. Not the clock, whose edge rate is
    # set by the SDC before CTS and by the clock tree afterwards.
    set_driving_cell -lib_cell $DRIVE_CELL \
        [get_ports * -filter "direction == in && name != $CLK_PORT"]
}

# read_sdc reports an error and carries on, so a scenario can end up
# with no clock at all and then report no violations.
foreach corner $CORNER_LABELS {
    current_scenario func_$corner
    if { [sizeof_collection [all_clocks]] == 0 } {
        error "No clock in scenario func_$corner after reading $SDC_FILE.\
               Look for 'Errors reading SDC file' above."
    }
}

####################################################################
## What each scenario is for
####################################################################
# Checking everything everywhere wastes time and buries the result
# that matters. Setup is a slow-corner check, hold a fast-corner one.
#
#   wc  slow, hot, low voltage    setup, transition, capacitance
#   bc  fast, cold, high voltage  hold
#   tc  nominal                   power

set_scenario_status func_wc -active true \
    -setup true  -hold false \
    -max_transition true  -max_capacitance true \
    -leakage_power true   -dynamic_power false

set_scenario_status func_bc -active true \
    -setup false -hold true \
    -max_transition false -max_capacitance false \
    -leakage_power false  -dynamic_power false

set_scenario_status func_tc -active true \
    -setup false -hold false \
    -max_transition false -max_capacitance false \
    -leakage_power true   -dynamic_power true

current_scenario func_wc

puts ""
puts "MCMM: mode func, corners $CORNER_LABELS"
puts "  func_wc  setup, max_tran, max_cap, leakage"
puts "  func_bc  hold"
puts "  func_tc  power"
if { $PHYSICAL } {
    puts "  parasitics: wc=rcworst tc=rctyp bc=rcbest"
} else {
    puts "  non-physical mode, zero interconnect delay"
}
