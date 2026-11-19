set root [file dirname [file normalize [info script]]]
open_hw_manager
connect_hw_server -url localhost:3121
set target [create_hw_target -svf led_fill_svf]
if {[llength $target] != 1 || ![get_property IS_SVF $target]} {
    error "Refusing to open a non-SVF target"
}
open_hw_target $target
set dev [create_hw_device -part xc7s25csga324-1]
set_property PROGRAM.FILE [file join $root build leb_blink.bit] $dev
if {![get_property IS_SVF [current_hw_target]]} {
    error "Refusing to program physical hardware"
}
program_hw_devices $dev
set output [file join $root arty_s7_led_blink.svf]
write_hw_svf -force $output
close_hw_target
disconnect_hw_server
close_hw_manager
# The bundled libxsvf requires exponential notation for fractional RUNTEST.
set f [open $output r]
set data [read $f]
close $f
set data [string map {"RUNTEST 0.100000 SEC;" "RUNTEST 1E-1 SEC;"} $data]
if {[regexp {RUNTEST\s+[0-9]+\.[0-9]+} $data]} {error "Unsupported decimal RUNTEST remains"}
set f [open $output w]
puts -nonewline $f $data
close $f
