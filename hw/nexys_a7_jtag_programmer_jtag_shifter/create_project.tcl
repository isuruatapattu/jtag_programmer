# Create nexys_a7_jtag_programmer_jtag_shifter from hw/nexys_a7_jtag_programmer
# and add the jtag_shifter IP (hw/ip/jtag_shifter) to its block design.
#
#   cd hw/nexys_a7_jtag_programmer_jtag_shifter
#   vivado -mode batch -source create_project.tcl                 ;# create + build
#   vivado -mode batch -source create_project.tcl -tclargs -nobuild
#
# The source project is only opened and saved under the new name; it is not
# modified. Running the script again reopens the new project and skips steps
# that are already done.

set script_dir [file normalize [file dirname [info script]]]
set proj_name  nexys_a7_jtag_programmer_jtag_shifter
set new_xpr    [file join $script_dir $proj_name.xpr]
set src_xpr    [file normalize [file join $script_dir .. nexys_a7_jtag_programmer nexys_a7_jtag_programmer.xpr]]
set ip_rtl     [file normalize [file join $script_dir .. ip jtag_shifter rtl]]
set do_build   [expr {[lsearch -exact $argv -nobuild] < 0}]

# ---------------------------------------------------------------- project
if {[file exists $new_xpr]} {
    open_project $new_xpr
} else {
    open_project $src_xpr
    save_project_as $proj_name $script_dir -exclude_run_results -force
}

if {[file normalize [get_property DIRECTORY [current_project]]] ne $script_dir} {
    error "current project is not in $script_dir; refusing to edit it"
}

# RTL is referenced from hw/ip/jtag_shifter, not copied.
foreach f [glob -directory $ip_rtl *.sv *.v] {
    if {[get_files -quiet $f] eq ""} {
        add_files -norecurse -fileset sources_1 $f
    }
}
update_compile_order -fileset sources_1

# ---------------------------------------------------------------- block design
open_bd_design [get_files design_1.bd]

if {[get_bd_cells -quiet jtag_shifter] eq ""} {
    create_bd_cell -type module -reference jtag_shifter_top jtag_shifter

    set_property CONFIG.NUM_MI {4} [get_bd_cells axi_smc]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M03_AXI] \
                        [get_bd_intf_pins jtag_shifter/S_AXI]
    connect_bd_net -net microblaze_0_Clk [get_bd_pins jtag_shifter/s_axi_aclk]
    connect_bd_net -net rst_clk_wiz_0_100M_peripheral_aresetn \
                   [get_bd_pins jtag_shifter/s_axi_aresetn]

    # axi_gpio_0 -> jtag_shifter (bypass) -> ck_a0; ck_b0 also feeds the shifter.
    delete_bd_objs [get_bd_nets axi_gpio_0_gpio_io_o]
    connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] \
                   [get_bd_pins jtag_shifter/gpio_bypass_i]
    connect_bd_net [get_bd_pins jtag_shifter/jtag_o] [get_bd_ports ck_a0]
    connect_bd_net -net ck_b0_1 [get_bd_pins jtag_shifter/jtag_i]

    assign_bd_address -offset 0x44A00000 -range 0x00010000 \
        -target_address_space [get_bd_addr_spaces microblaze_0/Data] \
        [get_bd_addr_segs jtag_shifter/S_AXI/*] -force
}

validate_bd_design
save_bd_design
generate_target all [get_files design_1.bd]

# ---------------------------------------------------------------- constraints
# Edit only the copy that belongs to the new project.
set xdc [lindex [get_files -of_objects [get_filesets constrs_1] *.xdc] 0]
set xdc [file normalize $xdc]
if {[string first $script_dir $xdc] != 0} {
    error "constraint file $xdc is outside the new project; refusing to edit it"
}
set fh [open $xdc r]
set xdc_text [read $fh]
close $fh
if {[string first "jtag_shifter" $xdc_text] < 0} {
    set fh [open $xdc a]
    puts $fh ""
    puts $fh "## jtag_shifter: pack the JA output flip-flops (TCK, TMS, TDI, spare) into the IOBs"
    puts $fh "set_property IOB TRUE \[get_ports {ck_a0\[*\]}\]"
    close $fh
}

# ---------------------------------------------------------------- build
if {$do_build} {
    reset_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "impl_1 did not complete"
    }

    open_run impl_1
    report_timing_summary -file [file join $script_dir timing_summary.rpt]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    puts "Worst setup slack: $wns ns"
    if {$wns < 0} {
        error "timing not met (WNS $wns ns)"
    }

    write_hw_platform -fixed -include_bit -force \
        -file [file join $script_dir design_1_wrapper.xsa]
    puts "Wrote [file join $script_dir design_1_wrapper.xsa]"
}

close_project
