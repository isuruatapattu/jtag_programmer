set root [file dirname [file normalize [info script]]]
set out [file join $root build]
file mkdir $out
create_project -in_memory -part xc7s25csga324-1
read_verilog -sv [file join $root arty_s7_led_blink.srcs sources_1 new leb_blink.sv]
read_xdc [file join $root arty_s7_led_blink.srcs constrs_1 imports Downloads Arty-S7-25-Master.xdc]
synth_design -top leb_blink -part xc7s25csga324-1
opt_design
place_design
route_design
report_timing_summary -file [file join $out timing_summary.rpt]
report_drc -file [file join $out drc.rpt]
report_io -file [file join $out io.rpt]
set worst [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst] == 0 || [get_property SLACK $worst] < 0} {error "Setup timing failed"}
set worst_hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $worst_hold] == 0 || [get_property SLACK $worst_hold] < 0} {error "Hold timing failed"}
write_checkpoint -force [file join $out leb_blink_routed.dcp]
write_bitstream -force [file join $out leb_blink.bit]
