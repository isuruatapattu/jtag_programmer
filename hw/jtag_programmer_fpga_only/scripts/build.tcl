# Non-project build of the FPGA-only JTAG programmer.
#
#   cd hw/jtag_programmer_fpga_only
#   vivado -mode batch -source scripts/build.tcl
#
# Output: build/top.bit plus timing, utilization and IO reports in build/.
# Fails if timing is not met or if a JTAG/flash register was not packed
# into its IOB (the pin timing relies on it).

set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root build]
set part xc7a100tcsg324-1
file mkdir $out

set rtl {
    rtl/crc32.sv rtl/byte_fifo.sv rtl/flash_sck_startup.sv
    rtl/spi_flash_reader.sv rtl/jtag_engine.sv rtl/jbin_decoder.sv
    rtl/debounce.sv rtl/uart_tx_status.sv rtl/top_ctrl.sv rtl/top.sv
}
foreach f $rtl { read_verilog -sv [file join $root $f] }
read_xdc [file join $root constraints top.xdc]
catch {auto_detect_xpm}

synth_design -top top -part $part
write_checkpoint -force [file join $out post_synth.dcp]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]

report_timing_summary -file [file join $out timing.rpt]
report_utilization    -file [file join $out utilization.rpt]
report_io             -file [file join $out io.rpt]
report_drc            -file [file join $out drc.rpt]

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "WNS $wns ns, WHS $whs ns"
if {$wns < 0 || $whs < 0} {
    error "timing not met (WNS $wns, WHS $whs), see build/timing.rpt"
}

# IOB packing of the pin registers.
set iob_regs {
    u_engine/tck_q_reg u_engine/tms_q_reg u_engine/tdi_q_reg
    u_engine/tdo_q_reg u_flash_reader/cs_q_reg u_flash_reader/mosi_q_reg
    u_flash_reader/miso_q_reg
}
foreach r $iob_regs {
    set c [get_cells -quiet $r]
    if {[llength $c] != 1} {
        error "register $r not found after implementation"
    }
    set site [get_property SITE $c]
    if {![string match "OLOGIC*" $site] && ![string match "ILOGIC*" $site]} {
        error "register $r is at $site, not in an IOB"
    }
    puts "IOB ok: $r at $site"
}

write_bitstream -force [file join $out top.bit]
puts "wrote [file join $out top.bit]"
