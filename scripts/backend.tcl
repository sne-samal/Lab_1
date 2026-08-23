####################################################################
##
##  Clock tree synthesis, routing, chip finish and export.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
##  Sourced by pnr.tcl and fusion.tcl with a placed, legalised block.
##  Identical for both flows, which is what makes their results
##  comparable: only the front end differs.
##
####################################################################

####################################################################
## Clock tree synthesis
####################################################################
# Until now the clock has been ideal. It has to be distributed to
# every flip-flop, and that network is the largest, most heavily
# loaded net on the chip. Look at skew and transition afterwards.

lab_banner "Clock tree synthesis"

# Clock buffers and inverters only: balanced rise and fall, and drive
# strengths in even steps. Exclude everything, then add them back.
set cts_cells {}
foreach c [concat $CTS_BUFFERS $CTS_INVERTERS] { lappend cts_cells */$c }
set cts_cells [get_lib_cells $cts_cells]

puts "  clock tree cells: [sizeof_collection $cts_cells]"

# ATTR-12 fires once per library cell otherwise.
suppress_message ATTR-12
set_lib_cell_purpose -exclude cts [get_lib_cells]
set_lib_cell_purpose -include cts $cts_cells
unsuppress_message ATTR-12

set_clock_tree_options -target_skew 0.2 -clocks [get_clocks $CLK_PORT]
set_max_transition 0.13 -clock_path [get_clocks $CLK_PORT]

# build_clock, route_clock, then final_opto against the real clock.
# Hold violations usually appear and are fixed here.
clock_opt

catch {redirect -file $RPT_DIR/cts_clock_qor.rpt  {report_clock_qor}}
catch {redirect -file $RPT_DIR/cts_clock_skew.rpt {report_clock_timing -type skew}}

lab_reports cts
lab_headline
save_block -label cts
save_lib

####################################################################
## Routing
####################################################################
# route_auto runs global routing, track assignment and detail routing.
# route_opt then re-optimises timing, since wire delay was an estimate
# until now and is a fact afterwards.

lab_banner "Routing"

route_auto
route_opt

redirect -tee -file $RPT_DIR/route_check.rpt {check_routes}

lab_reports route
lab_headline
save_block -label route
save_lib

####################################################################
## Chip finish
####################################################################
# Wells and implants have to run continuously across a row, and a gap
# between cells breaks them. Fillers carry those layers and the power
# rails through. Largest first, which the tool requires.

lab_banner "Chip finish"

set fillers {}
foreach c $FILLER_CELLS { lappend fillers */$c }

create_stdcell_fillers -lib_cells [get_lib_cells $fillers]

# Anything that inserts cells has to reconnect power afterwards.
connect_pg_net -automatic

# Saved before the checks, so a failure still leaves a block to open.
save_block -label finish
save_lib

####################################################################
## Checks
####################################################################
# The tool checking its own work, not signoff. Signoff DRC and LVS run
# against the foundry decks in Lab 2. check_lvs compares the layout
# against its own connectivity; -max_errors 0 reports all of them
# rather than the default 20 per type.
#
# These report violations and still return success, so the flow does
# not stop on them. Read the reports: the closing summary says how.

lab_banner "Checks"

redirect -tee -file $RPT_DIR/finish_legality.rpt {check_legality}

redirect -tee -file $RPT_DIR/finish_routes.rpt          {check_routes}
redirect -tee -file $RPT_DIR/finish_pg_drc.rpt          {check_pg_drc}
redirect -tee -file $RPT_DIR/finish_pg_connectivity.rpt {check_pg_connectivity}
redirect -tee -file $RPT_DIR/finish_lvs.rpt             {check_lvs -max_errors 0}

# Extraction happens as part of the timing update. There is no
# separate extract_rc command in this release.
update_timing

lab_reports finish
lab_headline

####################################################################
## Export
####################################################################
#   .v     netlist, for simulation
#   .sdf   cell and net delays, annotated onto the netlist so the
#          simulation runs at silicon speed rather than zero delay
#   .def   placement and routing in text form
#   .lef   an abstract of this block: outline, pins and blockages
#   .spef  extracted parasitics, for signoff timing analysis
#   .sdc   the constraints as they ended up

lab_banner "Export"

# Filler and tap cells have no Verilog models, and the vendor cell
# models declare no power ports, so both are left out or VCS will not
# elaborate. The design library and the DEF still hold every one.
write_verilog -exclude {all_physical_cells pg_netlist} $LAYOUT_V

write_def $OUT_DIR/${DESIGN}.def
write_lef $OUT_DIR/${DESIGN}.lef
write_sdc -output $OUT_DIR/${DESIGN}_final.sdc
write_sdf -corner $SDF_CORNER $OUT_DIR/${DESIGN}_${SDF_CORNER}.sdf

# write_parasitics appends the parasitic technology name and the
# corner temperature, giving $OUT_DIR/lfsr4.rctyp_25.spef.
write_parasitics -corner $SDF_CORNER -output $OUT_DIR/${DESIGN}

save_block -label finish
save_lib

puts ""
puts "  Files in $OUT_DIR:"
foreach f [lsort [glob -nocomplain $OUT_DIR/*]] {
    puts [format "    %-44s %d bytes" $f [file size $f]]
}

lab_banner "Layout complete"

####################################################################
## Did it run properly
####################################################################
# None of the checks above stops the flow: they report violations and
# still return success. So the reports are the answer, not the fact
# that the script reached the end.

puts "  Every check wrote a report. Read the summary at the end of each:"
puts ""
puts "    $RPT_DIR/finish_legality.rpt         every cell in a legal site"
puts "    $RPT_DIR/finish_routes.rpt           every net routed, no rule broken"
puts "    $RPT_DIR/finish_pg_drc.rpt           power grid spacing and width"
puts "    $RPT_DIR/finish_pg_connectivity.rpt  power reaches every cell"
puts "    $RPT_DIR/finish_lvs.rpt              shorts, opens, floating routes"
puts ""
puts "  A clean run says, in finish_routes.rpt:"
puts "      Total number of open nets = 0"
puts "      Total number of DRCs = 0"
puts ""
puts "  One 'end-of-line keepout zone violation on M1' in finish_pg_drc.rpt"
puts "  is known and accepted. See ../notes/lab1_flow_review.md."
puts ""
puts "  Timing and area are in $RPT_DIR/finish_*.rpt."
puts ""
puts "  View it:  start_gui"
puts "  Simulate: make sim-layout FLOW=$FLOW"
