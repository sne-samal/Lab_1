####################################################################
##
##  Clock tree, routing, chip finish and export. Identical for both
##  flows, which is what makes their results comparable.
##
##  Author:   Sne Samal
##  Version:  1.1
##  Date:     2026-09-05
##
####################################################################

####################################################################
## Clock tree synthesis
####################################################################

# Clock buffers and inverters only, and ATTR-12 fires once per library
# cell without the suppression.
set cts_cells {}
foreach c [concat $CTS_BUFFERS $CTS_INVERTERS] { lappend cts_cells */$c }
set cts_cells [get_lib_cells $cts_cells]

suppress_message ATTR-12
set_lib_cell_purpose -exclude cts [get_lib_cells]
set_lib_cell_purpose -include cts $cts_cells
unsuppress_message ATTR-12

set_clock_tree_options -target_skew 0.2 -clocks [get_clocks $CLK_PORT]
set_max_transition 0.13 -clock_path [get_clocks $CLK_PORT]

# Cells driven by one clock buffer. Caps the load on any tree stage.
set_app_options -name cts.common.max_fanout -value 20

clock_opt

catch {redirect -file $RPT_DIR/cts_clock_qor.rpt  {report_clock_qor}}
catch {redirect -file $RPT_DIR/cts_clock_skew.rpt {report_clock_timing -type skew}}

lab_reports cts
save_block -label cts
save_lib

####################################################################
## Routing
####################################################################

route_auto
route_opt

redirect -tee -file $RPT_DIR/route_check.rpt {check_routes}

lab_reports route
save_block -label route
save_lib

####################################################################
## Chip finish
####################################################################
# Largest first, which the tool requires.
set fillers {}
foreach c $FILLER_CELLS { lappend fillers */$c }

create_stdcell_fillers -lib_cells [get_lib_cells $fillers]

connect_pg_net -automatic

# Saved before the checks, so a failure still leaves a block to open.
save_block -label finish
save_lib

####################################################################
## Checks
####################################################################
# These report violations and still return success, so the flow does
# not stop on them.

redirect -tee -file $RPT_DIR/finish_legality.rpt        {check_legality}
redirect -tee -file $RPT_DIR/finish_routes.rpt          {check_routes}
redirect -tee -file $RPT_DIR/finish_pg_drc.rpt          {check_pg_drc}
redirect -tee -file $RPT_DIR/finish_pg_connectivity.rpt {check_pg_connectivity}
redirect -tee -file $RPT_DIR/finish_lvs.rpt             {check_lvs -max_errors 0}

# Extraction happens as part of the timing update.
update_timing

lab_reports finish

####################################################################
## Export
####################################################################

# Make every instance and net name legal Verilog before anything is
# written, so the netlist, SDF and SPEF agree on what things are
# called. Without it bus bits reach the SDF as escaped identifiers
# and VCS cannot match them to the netlist.
change_names -rules verilog -hierarchy

# Filler and tap cells have no Verilog models and the vendor models
# declare no power ports, so both are left out or VCS will not
# elaborate. The design library and the DEF still hold every one.
write_verilog -exclude {all_physical_cells pg_netlist} $LAYOUT_V

write_def $OUT_DIR/${DESIGN}.def
write_lef $OUT_DIR/${DESIGN}.lef
write_sdc -output $OUT_DIR/${DESIGN}_final.sdc
write_sdf -corner $SDF_CORNER $OUT_DIR/${DESIGN}_${SDF_CORNER}.sdf

write_parasitics -corner $SDF_CORNER -output $OUT_DIR/${DESIGN}

save_block -label finish
save_lib
