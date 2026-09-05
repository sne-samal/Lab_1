####################################################################
##
##  Modes, corners and scenarios, and the SDC read into them.
##  Sourced once the block exists; the caller sets PHYSICAL first.
##
##  Author:   Sne Samal
##  Version:  1.1
##  Date:     2026-09-05
##
####################################################################

if { ![info exists PHYSICAL] } { error "Set PHYSICAL to 1 or 0 before sourcing mcmm.tcl" }

# The tool's own default mode, corner and scenario have no process
# label and no parasitics, so a design can appear to pass at a corner
# that does not exist.
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

array set RC_SPEC { wc rcworst  tc rctyp  bc rcbest }

####################################################################
## Mode and corners
####################################################################
# The process label picks a characterisation point inside the
# reference library. The labels were set when the NDM was built.

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

foreach corner $CORNER_LABELS {
    current_scenario func_$corner
    read_sdc $SDC_FILE

    # Every input except the clock, whose edge rate the SDC sets.
    set_driving_cell -lib_cell $DRIVE_CELL \
        [get_ports * -filter "direction == in && name != $CLK_PORT"]

    # A corner fixes one PVT for the whole die. Derating lets paths
    # differ from each other within it.
    set_timing_derate -early $DERATE_EARLY -cell_delay -net_delay
    set_timing_derate -late  $DERATE_LATE  -cell_delay -net_delay
}

# read_sdc reports an error and carries on, so a scenario can end up
# with no clock and then report no violations.
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
