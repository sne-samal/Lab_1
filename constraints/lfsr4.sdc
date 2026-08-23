####################################################################
##
##  Timing constraints for lfsr4.
##
##  This is the file to edit when you want to change the clock. It is
##  read into every scenario, so synthesis, placement, clock tree
##  synthesis and routing all see the same constraints.
##
##  Units are nanoseconds and picofarads, taken from the TSMC library.
##
####################################################################

####################################################################
## Clock
####################################################################
# 1 ns, so 1 GHz. The Cadence lab wrote this as 1000 ps.

create_clock -name clk -period 1.0 [get_ports clk]

# Uncertainty stands in for clock jitter and, before the clock tree is
# built, for the skew it will have. 2 percent of the period, as in the
# Cadence lab. Applied to both setup and hold.

set_clock_uncertainty 0.02 [get_clocks clk]

# Before clock tree synthesis the clock is ideal, so the tool needs to
# be told how sharp its edges will be. 50 ps, again from the Cadence
# lab. After CTS the real transition is used instead.

set_clock_transition 0.05 [get_clocks clk]

####################################################################
## Design rule constraints
####################################################################
# How slowly a signal is allowed to change. Without this the tool
# reports "Cannot find any default max transition constraint on the
# design", and the max_transition checking enabled on the wc scenario
# has no value to check against: the reports then say zero violations
# because nothing was checked, not because nothing was wrong.
#
# 0.2 ns is 20 percent of the clock period, an ordinary starting
# point. The clock itself is held to 0.13 ns in scripts/cts.tcl,
# since a clock edge has to be sharper than the data it launches.

set_max_transition 0.2 [current_design]

####################################################################
## Input and output timing
####################################################################
# The Cadence lab constrained only the clock, which leaves every path
# to and from a port unconstrained and silently unoptimised. Budgeting
# 20 percent of the period at each boundary is the ordinary starting
# point and makes the reports honest.

set_input_delay  0.2 -clock clk [get_ports rst]
set_output_delay 0.2 -clock clk [get_ports data_out[*]]

# rst is an asynchronous reset. It is constrained above so that the
# tool sizes its buffering sensibly, but it is not a timed path in the
# usual sense; the recovery and removal checks are what matter.

####################################################################
## Drive and load
####################################################################
# Without a load the tool assumes the outputs drive nothing at all,
# which flatters the timing. 10 fF is a modest guess at what a wire
# and a receiving gate would present.

set_load 0.01 [all_outputs]

# The drive strength of whatever feeds this block matters just as
# much, and is applied with set_driving_cell in scripts/mcmm.tcl
# rather than here. It is the one constraint that has to name a
# specific library cell, and cell names belong to the PDK kit, which
# keeps this file usable against a different technology.
