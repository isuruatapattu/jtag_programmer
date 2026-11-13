# Run the jtag_shifter testbench in QuestaSim.
#
# From hw/ip/jtag_shifter:
#
#   vsim -c -do sim/run_questa.tcl
#   vsim -do sim/run_questa.tcl
#
# Start Questa with its working directory set to hw/ip/jtag_shifter
# (or to hw/ip/jtag_shifter/sim). A GUI command such as
# `do sim/run_questa.tcl` does not update [info script]: it remains
# Questa's internal /mtitcl/vsim path, so the script location is taken
# from the working directory.
#
# Batch mode runs the testbench and exits 0 only when the transcript
# contains "TB RESULT: PASS". GUI mode compiles, loads the testbench,
# applies sim/wave.do, runs to $finish, and stays open.

# `do` inside the GUI leaves [info script] at /mtitcl/vsim. That path exists
# only inside Questa's virtual filesystem, so directory creation must use a
# real project directory instead.
set script_path [info script]
set script_is_real [expr {
    $script_path ne "" &&
    [string first "/mtitcl/" $script_path] != 0 &&
    [file exists $script_path]
}]
if {$script_is_real} {
    set sim_dir [file normalize [file dirname $script_path]]
} elseif {[file exists [file join [pwd] sim run_questa.tcl]]} {
    set sim_dir [file normalize [file join [pwd] sim]]
} elseif {[file exists [file join [pwd] run_questa.tcl]]} {
    set sim_dir [file normalize [pwd]]
} else {
    puts stderr "ERROR: start Questa in hw/ip/jtag_shifter, then run:"
    puts stderr "  do sim/run_questa.tcl"
    quit -code 1 -f
}

set rtl_dir   [file normalize [file join $sim_dir .. rtl]]
set build_dir [file join $sim_dir questa_work]
set lib_dir   [file join $build_dir work]
set wave_do   [file join $sim_dir wave.do]

if {[catch {batch_mode} batch]} {
    set batch 0
}

proc fail {message} {
    global batch
    puts stderr "ERROR: $message"
    if {$batch} {
        quit -code 1 -f
    }
    return -code error $message
}

proc run_command {command} {
    if {[catch {uplevel 1 $command} result options]} {
        puts stderr $result
        if {[dict exists $options -errorinfo]} {
            puts stderr [dict get $options -errorinfo]
        }
        fail "command failed: $command"
    }
}

file mkdir $build_dir
cd $build_dir

# Keep the work-library mapping local to questa_work instead of changing a
# project- or installation-wide modelsim.ini.
if {![file exists [file join $build_dir modelsim.ini]]} {
    run_command [list vmap -c]
}

if {[file exists $lib_dir]} {
    file delete -force $lib_dir
}
run_command [list vlib $lib_dir]
run_command [list vmap work $lib_dir]

set sv_sources [list \
    [file join $rtl_dir jtag_shifter_fifo.sv] \
    [file join $rtl_dir jtag_shifter_core.sv] \
    [file join $rtl_dir jtag_shifter_axil.sv] \
    [file join $sim_dir tb_jtag_shifter.sv]]

puts "Compiling jtag_shifter into $lib_dir"
foreach source $sv_sources {
    run_command [list vlog -sv -work work $source]
}
run_command [list vlog -work work [file join $rtl_dir jtag_shifter_top.v]]

# +acc keeps internal signals available in the Wave window.
# -onfinish stop leaves the waveform loaded when the testbench $finish-es.
set vsim_args [list -voptargs=+acc -onfinish stop -t 1ps work.tb_jtag_shifter]
puts "Loading tb_jtag_shifter"
run_command [concat vsim $vsim_args]

if {$batch} {
    set log [file join $build_dir tb_jtag_shifter.log]
    file delete -force $log
    transcript file $log
    transcript on
    run -all
    transcript off

    set fh [open $log r]
    set contents [read $fh]
    close $fh
    if {[string first "TB RESULT: PASS" $contents] < 0} {
        puts "jtag_shifter testbench FAILED (see $log)"
        quit -code 1 -f
    }
    puts "jtag_shifter testbench PASSED"
    quit -code 0 -f
}

view wave
log -r /tb_jtag_shifter/*
run_command [list do $wave_do]
run -all
wave zoom full

puts ""
puts "Simulation is stopped at the end of tb_jtag_shifter. Questa stays open."
puts "The Wave window is grouped by sim/wave.do. To run again:"
puts "  restart -f"
puts "  run -all"
puts "  wave zoom full"
