# Run the FPGA-only JTAG programmer simulation suite in QuestaSim.
#
# From hw/jtag_programmer_fpga_only:
#
#   vsim -c -do sim/run_questa.tcl
#   vsim -c -do "do sim/run_questa.tcl tb_top"
#   vsim -gui
#   do sim/run_questa.tcl tb_jtag_engine
#
# Start Questa with its working directory set to hw/jtag_programmer_fpga_only.
# A GUI command such as `do sim/run_questa.tcl ...` does not update
# [info script]: it remains Questa's internal /mtitcl/vsim path, so the
# project location is taken from the working directory.
#
# Batch mode runs every selected test and exits with the pass/fail status.
# GUI mode compiles, loads one test, records its signals, runs it, and stays
# open. The optional argument selects the test label, for example
# tb_jtag_engine or tb_top_SCEN_3. With no argument the GUI loads
# tb_jtag_engine.
#
# The test suite generates JBIN vectors first, then compiles all sources into
# build/questa/work. It uses byte_fifo's inferred-memory implementation
# (FIFO_XPM = 0), because QuestaSim does not include the Xilinx XPM library.
# Per-test transcript logs are written to build/questa/logs/.

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
    set root [file normalize [file join [file dirname $script_path] ..]]
} elseif {[file exists [file join [pwd] sim run_questa.tcl]]} {
    set root [file normalize [pwd]]
} else {
    puts stderr "ERROR: start Questa in hw/jtag_programmer_fpga_only, then run:"
    puts stderr "  do sim/run_questa.tcl tb_jtag_engine 1"
    quit -code 1 -f
}

set build_dir [file join $root build questa]
set lib_dir   [file join $build_dir work]
set log_dir   [file join $build_dir logs]
set vec_dir   [file join $root build sim vectors]

# `do sim/run_questa.tcl tb_jtag_engine` passes the test name by replacing
# the $1 macro. $argv belongs to the vsim command line; in the GUI it is
# "--", which is why a lookup for that string matches no test.
set do_arg ""
catch {set do_arg "$1"}
if {$do_arg ne "" && $do_arg ne "--"} {
    set filter $do_arg
} elseif {[llength $argv] >= 1 && [lindex $argv 0] ni {"" "--"}} {
    set filter [lindex $argv 0]
} else {
    set filter ""
}
if {[catch {batch_mode} batch]} {
    set batch 0
}
puts "Project root: $root"
puts "Running filter: [expr {$filter eq {} ? {(all tests)} : $filter}]"

proc fail {message} {
    global batch
    puts stderr "ERROR: $message"
    if {$batch} {
        quit -code 1 -f
    }
    # Stop this script without closing the GUI.
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

proc sanitize_name {name} {
    return [string map {" " "_" "=" "_" "+" "" "/" "_"} $name]
}

proc test_passed {log} {
    set fh [open $log r]
    set contents [read $fh]
    close $fh
    return [expr {
        [string first "TEST PASSED" $contents] >= 0 &&
        [string first "TEST FAILED" $contents] < 0
    }]
}

file mkdir $build_dir
file mkdir $log_dir
cd $build_dir

# Keep the work-library mapping local to build/questa instead of changing a
# project- or installation-wide modelsim.ini.
if {![file exists [file join $build_dir modelsim.ini]]} {
    run_command [list vmap -c]
}

# Generate the same JBIN, trace and negative-test vectors consumed by xsim
# and Icarus. The testbenches receive the absolute vector directory through
# +VEC, so they work regardless of QuestaSim's current directory.
set python [auto_execok python3]
if {$python eq ""} {
    set python [auto_execok python]
}
if {$python eq ""} {
    fail "Python 3 is required for sim/gen_vectors.py"
}
run_command [list exec $python [file join $root sim gen_vectors.py]]

# Build a clean local simulation library.
if {[file exists $lib_dir]} {
    file delete -force $lib_dir
}
run_command [list vlib $lib_dir]
run_command [list vmap work $lib_dir]

# Compile order matters: module dependencies precede their users. Use the
# behavioural STARTUPE2 replacement, never rtl/flash_sck_startup.sv, because
# the latter instantiates the Xilinx primitive used only in synthesis.
set sources {
    rtl/crc32.sv
    rtl/byte_fifo.sv
    sim/models/flash_sck_startup_sim.sv
    rtl/spi_flash_reader.sv
    rtl/jtag_engine.sv
    rtl/jbin_decoder.sv
    rtl/debounce.sv
    rtl/uart_tx_status.sv
    rtl/top_ctrl.sv
    rtl/reset_gen.sv
    rtl/tck_rate_selector.sv
    rtl/top.sv
    sim/models/spi_flash_model.sv
    sim/models/tap_model.sv
    sim/tb_spi_flash_reader.sv
    sim/tb_jtag_engine.sv
    sim/tb_jbin_decoder.sv
    sim/tb_top.sv
}

puts "Compiling [llength $sources] SystemVerilog files into $lib_dir"
foreach source $sources {
    run_command [list vlog -sv -work work [file join $root $source]]
}

# Each entry is:
#   {label top_module additional_vsim_generic_arguments plusargs}
#
# These match sim/run_icarus.py and sim/run_sim.tcl. FIFO_XPM=0 selects the
# inferred RAM FIFO in every bench that instantiates it.
set tests {
    {tb_spi_flash_reader            tb_spi_flash_reader {}              {}}
    {tb_spi_flash_reader_slow_flash tb_spi_flash_reader {-gT_V_NS=24.0} {}}
    {tb_jtag_engine                 tb_jtag_engine      {}              {}}
    {tb_jbin_decoder                tb_jbin_decoder     {}              {}}
    {tb_top_SCEN_0                  tb_top              {}              {+SCEN=0}}
    {tb_top_SCEN_1                  tb_top              {}              {+SCEN=1}}
    {tb_top_SCEN_2                  tb_top              {}              {+SCEN=2}}
    {tb_top_SCEN_3                  tb_top              {}              {+SCEN=3}}
    {tb_top_SCEN_4                  tb_top              {}              {+SCEN=4}}
    {tb_top_SCEN_5                  tb_top              {}              {+SCEN=5}}
    {tb_top_SCEN_6                  tb_top              {}              {+SCEN=6}}
    {tb_top_SCEN_7                  tb_top              {}              {+SCEN=7}}
    {tb_top_SCEN_8                  tb_top              {}              {+SCEN=8}}
    {tb_top_SCEN_9                  tb_top              {}              {+SCEN=9}}
}

proc vsim_args_for {top extra_generics plusargs vec_dir} {
    # +acc keeps internal signals available in the Wave and Objects windows.
    # -onfinish stop leaves the waveform loaded when the testbench finishes.
    set args [list -voptargs=+acc -onfinish stop -t 1ps]
    if {$top ne "tb_jtag_engine"} {
        lappend args -gFIFO_XPM=0
    }
    foreach generic $extra_generics {
        lappend args $generic
    }
    lappend args "work.$top" "+VEC=$vec_dir"
    foreach plusarg $plusargs {
        lappend args $plusarg
    }
    return $args
}

if {!$batch} {
    if {$filter eq ""} {
        set filter "tb_jtag_engine"
    }
    set selected {}
    foreach test $tests {
        if {[string first $filter [lindex $test 0]] >= 0} {
            lappend selected $test
        }
    }
    if {[llength $selected] == 0} {
        fail "no tests matched filter \"$filter\""
    }
    if {[llength $selected] > 1} {
        puts "Several tests match \"$filter\"; loading the first one."
        puts "Pass the full label to choose another, for example tb_top_SCEN_3."
    }
    lassign [lindex $selected 0] label top extra_generics plusargs
    puts "Loading $label for waveform viewing"
    run_command [concat vsim [vsim_args_for $top $extra_generics $plusargs $vec_dir]]
    view wave
    log -r *
    add wave -r /$top/*
    run -all
    wave zoom full
    puts ""
    puts "Simulation is stopped at the end of $label. Questa stays open."
    puts "The Wave window shows /$top. Zoom with the Wave toolbar or:"
    puts "  wave zoom full"
    puts "Drag any other logged signal from Structure/Objects into Wave."
    puts "Its history is already recorded. To run again:"
    puts "  restart -f"
    puts "  run -all"
    return
}

set passed 0
set failed 0

foreach test $tests {
    lassign $test label top extra_generics plusargs
    if {$filter ne "" && [string first $filter $label] < 0} {
        continue
    }

    set log [file join $log_dir "[sanitize_name $label].log"]
    file delete -force $log

    puts "Running $label"
    run_command [concat vsim [vsim_args_for $top $extra_generics $plusargs $vec_dir]]
    transcript file $log
    transcript on
    run -all
    transcript off
    quit -sim

    if {[test_passed $log]} {
        puts [format "%-45s PASS" $label]
        incr passed
    } else {
        puts [format "%-45s FAIL (see %s)" $label $log]
        incr failed
    }
}

set total [expr {$passed + $failed}]
puts "$passed of $total passed"

if {$total == 0} {
    fail "no tests matched filter \"$filter\""
}
if {$failed != 0} {
    quit -code 1 -f
}
quit -code 0 -f
