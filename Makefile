####################################################################
#
#  Lab 1 simulation and waveform viewing.
#
#  Author:   Sne Samal
#  Version:  1.0
#  Date:     2026-08-23
#
#  Synthesis and layout are not run from here. They are run directly
#  in the tool, one script at a time:
#
#      fc_shell -f scripts/syn_logical.tcl
#      fc_shell -f scripts/pnr.tcl
#      fc_shell -f scripts/fusion.tcl
#
####################################################################

DESIGN     := lfsr4
FLOW       ?= logical
SDF_CORNER ?= tc

OUT  := outputs/$(FLOW)
SIM  := sim
LOGS := logs
TB   := src/$(DESIGN)_tb.sv

# -full64        the 32-bit binary is broken on this server
# -timescale=    the netlist declares none and VCS rejects a mix
# +neg_tchk      honour negative setup and hold from the library
# +error+30      the default of 10 hides whole categories of failure
# -kdb           lets Verdi show source and schematic, not just waves
VCS := vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb \
       +neg_tchk +error+30

.DEFAULT_GOAL := help
.PHONY: sim-rtl sim-synth sim-layout waves waves-verdi clean help

# The testbench dumps to waveform.vcd in the current directory, so
# each simulation's output is moved aside and kept under its own tag.
define run_sim
	test -n "$$SYN_KIT_TCL" || { echo "Run 'tools/syn tsmc65LP' from the repo root first."; exit 1; }
	mkdir -p $(SIM) $(LOGS)
	rm -f waveform.vcd
	$(1) -o $(SIM)/simv_$(2) -Mdir=$(SIM)/csrc_$(2) -l $(LOGS)/vcs_$(2).log
	./$(SIM)/simv_$(2) -l $(LOGS)/sim_$(2).log
	test -f waveform.vcd && mv -f waveform.vcd $(SIM)/$(2).vcd || true
	echo ""
	echo "Waveforms: make waves KIND=$(2)"
endef

## sim-rtl: simulate the RTL, before synthesis has touched it
sim-rtl:
	$(call run_sim,$(VCS) src/$(DESIGN).sv $(TB),rtl)

## sim-synth: simulate the synthesised netlist, real cells, no wire delay
sim-synth:
	@test "$(FLOW)" = logical || { \
	  echo "sim-synth is for FLOW=logical. The fusion flow writes no"; \
	  echo "intermediate netlist: placement carries straight through."; \
	  exit 1; }
	@test -f $(OUT)/$(DESIGN)_synth.v || \
	  { echo "No $(OUT)/$(DESIGN)_synth.v. Run scripts/syn_logical.tcl."; exit 1; }
	$(call run_sim,$(VCS) $$SYN_SIM_MODELS $(OUT)/$(DESIGN)_synth.v $(TB),synth)

## sim-layout: simulate the routed layout with SDF back-annotation
sim-layout:
	@test -f $(OUT)/$(DESIGN)_layout.v || \
	  { echo "No $(OUT)/$(DESIGN)_layout.v. Run the $(FLOW) flow first."; exit 1; }
	@test -f $(OUT)/$(DESIGN)_$(SDF_CORNER).sdf || \
	  { echo "No SDF at $(OUT)/$(DESIGN)_$(SDF_CORNER).sdf."; exit 1; }
	$(call run_sim,$(VCS) +sdfverbose $$SYN_SIM_MODELS $(OUT)/$(DESIGN)_layout.v $(TB) \
	    -sdf typ:$(DESIGN)_tb.dut:$(OUT)/$(DESIGN)_$(SDF_CORNER).sdf,layout_$(FLOW))

####################################################################
# Waveforms
####################################################################
# The testbench writes a VCD, which every viewer understands.

KIND ?= layout_$(FLOW)

## waves: view waveforms in GTKWave (KIND=rtl, synth or layout_<flow>)
waves: $(SIM)/$(KIND).vcd
	@test -n "$$DISPLAY" || \
	  { echo "No X display. Reconnect with 'ssh -Y' to open a window."; exit 1; }
	gtkwave $(SIM)/$(KIND).vcd

# Verdi reads its own FSDB format, so the VCD is converted once.
$(SIM)/%.fsdb: $(SIM)/%.vcd
	vcd2fsdb $< -o $@

## waves-verdi: the same waveforms in Verdi, which also shows the design
# -dbdir is the database VCS wrote next to simv. It is what populates the
# hierarchy browser, the source view and the schematic; without it Verdi
# shows waveforms and nothing to relate them to.
waves-verdi: $(SIM)/$(KIND).fsdb
	@test -n "$$DISPLAY" || \
	  { echo "No X display. Reconnect with 'ssh -Y' so Verdi can open a window."; exit 1; }
	verdi -nologo -ssf $(SIM)/$(KIND).fsdb \
	  $$(test -d $(SIM)/simv_$(KIND).daidir/kdb && echo "-dbdir $(SIM)/simv_$(KIND).daidir/kdb")

$(SIM)/$(KIND).vcd:
	@echo "No $(SIM)/$(KIND).vcd yet. Run the matching 'make sim-...' first."
	@exit 1

## clean: remove everything the flow and the simulator generated
clean:
	rm -rf work outputs reports logs sim
	rm -rf *.svf fc_command.log fc_output.txt HDL_LIBRARIES over_utilization_*.tcl*
	rm -rf csrc simv simv.daidir ucli.key *.vcd *.fsdb
	rm -rf verdiLog novas* .inter.vpd DVEfiles

## help: list the targets
help:
	@echo ""
	@echo "  Lab 1 simulation. Load the tools first:  tools/syn tsmc65LP"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  make /' | \
	  awk -F': ' '{ printf "%-24s %s\n", $$1, $$2 }'
	@echo ""
	@printf "%-24s %s\n" "    FLOW" "logical (default) or fusion"
	@printf "%-24s %s\n" "    SDF_CORNER" "corner to annotate from, default $(SDF_CORNER)"
	@echo ""
	@echo "  Layout and synthesis are run in fc_shell:"
	@echo "    fc_shell -f scripts/syn_logical.tcl   then  scripts/pnr.tcl"
	@echo "    fc_shell -f scripts/fusion.tcl"
	@echo ""
