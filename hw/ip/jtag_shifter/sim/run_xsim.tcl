# Run the jtag_shifter testbench in Vivado xsim.
#
#   cd hw/ip/jtag_shifter/sim
#   vivado -mode batch -source run_xsim.tcl
#
# Exits with status 1 unless the log contains "TB RESULT: PASS".

set sim_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $sim_dir .. rtl]]
set work    [file join $sim_dir xsim_work]

file mkdir $work
cd $work

set rtl_sv [list \
    [file join $rtl_dir jtag_shifter_fifo.sv] \
    [file join $rtl_dir jtag_shifter_core.sv] \
    [file join $rtl_dir jtag_shifter_axil.sv] \
    [file join $sim_dir tb_jtag_shifter.sv]]
set rtl_v [list [file join $rtl_dir jtag_shifter_top.v]]

proc run {args} {
    puts "> $args"
    if {[catch {exec {*}$args 2>@1} out]} {
        puts $out
        error "command failed: [lindex $args 0]"
    }
    puts $out
    return $out
}

run xvlog -sv {*}$rtl_sv
run xvlog {*}$rtl_v
run xelab -debug typical -timescale 1ns/1ps tb_jtag_shifter -s tb_jtag_shifter
set log [run xsim tb_jtag_shifter -R]

if {[string first "TB RESULT: PASS" $log] < 0} {
    puts "jtag_shifter testbench FAILED"
    exit 1
}
puts "jtag_shifter testbench PASSED"
#exit 0
