# Create a Vivado project for the FPGA-only JTAG programmer.
#
# Run from hw/jtag_programmer_fpga_only:
#
#   vivado -mode gui -source scripts/create_vivado_project.tcl
#   vivado -mode batch -source scripts/create_vivado_project.tcl -tclargs gui
#   vivado -mode batch -source scripts/create_vivado_project.tcl -tclargs synth
#
# The project is generated at build/vivado_project/. Re-running this script
# recreates it from the RTL and XDC, so make project-specific GUI changes in
# a separate saved project or reproduce them here.
#
# Optional tclargs:
#   gui    Create the project, elaborate the RTL, and open the Vivado GUI.
#          This is also done automatically when the script is started with
#          "vivado -mode gui" and no tclargs.
#   synth  Create the project, run synth_1, and wait for synthesis to finish.
#   impl   Create the project, run synth_1 and impl_1 through routing.

set root         [file normalize [file join [file dirname [info script]] ..]]
set project_name jtag_programmer_fpga_only
set project_dir  [file join $root build vivado_project]
set part         xc7a100tcsg324-1
set action       [expr {[llength $argv] > 0 ? [lindex $argv 0] : ""}]

if {$action ni {"" gui synth impl}} {
    error "usage: create_vivado_project.tcl ?gui|synth|impl?"
}

set gui_running 0
if {![catch {rdi::is_gui_mode} gui_running]} {
    set gui_running [expr {$gui_running ? 1 : 0}]
} else {
    set gui_running 0
}
set explore [expr {$action eq "gui" || ($action eq "" && $gui_running)}]

set rtl {
    rtl/crc32.sv
    rtl/byte_fifo.sv
    rtl/flash_sck_startup.sv
    rtl/spi_flash_reader.sv
    rtl/jtag_engine.sv
    rtl/jbin_decoder.sv
    rtl/debounce.sv
    rtl/uart_tx_status.sv
    rtl/top_ctrl.sv
    rtl/reset_gen.sv
    rtl/tck_rate_selector.sv
    rtl/top.sv
}

file mkdir [file dirname $project_dir]
# The previous run leaves this .xpr open in the GUI. create_project cannot
# open it again until that session releases it (Coretcl 2-101).
if {![catch {current_project}]} {
    puts "Closing the project already open in this Vivado session."
    catch {close_design}
    close_project
}
create_project -force $project_name $project_dir -part $part

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

set source_files {}
foreach relative_path $rtl {
    set path [file join $root $relative_path]
    if {![file exists $path]} {
        error "missing RTL source: $path"
    }
    lappend source_files $path
}
add_files -norecurse -fileset sources_1 $source_files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] *.sv]

set xdc [file join $root constraints top.xdc]
if {![file exists $xdc]} {
    error "missing constraint file: $xdc"
}
add_files -norecurse -fileset constrs_1 $xdc

set_property top top [get_filesets sources_1]
set_property top_auto_set 0 [get_filesets sources_1]
update_compile_order -fileset sources_1

# The default byte FIFO uses xpm_fifo_sync. Vivado supplies the XPM library,
# so no simulation stub or manually added XPM source is needed for synthesis.
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Default [get_runs synth_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]

# create_project already writes and opens the .xpr. save_project_as to that
# same path fails with Coretcl 2-101 because the project is already open.
puts "Created Vivado project:"
puts "  [file join $project_dir ${project_name}.xpr]"
puts "Top module: top"
puts "Part:       $part"

if {$action in {synth impl}} {
    puts "Launching synthesis..."
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
        error "synthesis did not complete; inspect synth_1_runme.log"
    }
    puts "Synthesis completed."
}

if {$action eq "impl"} {
    puts "Launching implementation..."
    launch_runs impl_1 -to_step route_design -jobs 8
    wait_on_run impl_1
    if {[get_property STATUS [get_runs impl_1]] ne "route_design Complete!"} {
        error "implementation did not complete; inspect impl_1_runme.log"
    }
    puts "Implementation completed."
}

if {$explore} {
    puts "Elaborating RTL so the hierarchy and schematic can be explored..."
    synth_design -rtl -name rtl_explore -top top -part $part
    if {!$gui_running} {
        start_gui
    }
    puts "Vivado is open on the elaborated design rtl_explore."
    puts "In Flow Navigator, use RTL Analysis -> Open Elaborated Design."
    puts "Select top in Netlist, then click Schematic to browse the hierarchy."
}
