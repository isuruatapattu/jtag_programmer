# Grouped waveform for tb_jtag_shifter.
# Applied by run_questa.tcl. Re-apply after a reload with: do sim/wave.do
#
# Groups, top to bottom:
#   Pins, TAP, AXI write, AXI read, Registers, Engine, FIFOs.

catch {delete wave *}

set tb /tb_jtag_shifter
set tap $tb/u_tap
set axil $tb/dut/u_axil
set core $axil/u_core

# The trace the target sees. TCK is jtag_o[0], TMS [1], TDI [2].
add wave -noupdate -group Pins -label clk $tb/clk
add wave -noupdate -group Pins -label rst_n $tb/rst_n
add wave -noupdate -group Pins -label TCK $tb/jtag_o\[0\]
add wave -noupdate -group Pins -label TMS $tb/jtag_o\[1\]
add wave -noupdate -group Pins -label TDI $tb/jtag_o\[2\]
add wave -noupdate -group Pins -label tdo_pin $tb/tdo_pin
add wave -noupdate -group Pins -label tap_tdo $tb/tap_tdo
add wave -noupdate -group Pins -label gpio_bypass -radix hexadecimal $tb/gpio_bypass

add wave -noupdate -group TAP -label state $tap/st
add wave -noupdate -group TAP -label ir -radix hexadecimal $tap/ir
add wave -noupdate -group TAP -label ir_sr -radix hexadecimal $tap/ir_sr
add wave -noupdate -group TAP -label dr_sr -radix hexadecimal $tap/dr_sr

add wave -noupdate -group {AXI write} -label awaddr -radix hexadecimal $tb/awaddr
add wave -noupdate -group {AXI write} -label awvalid $tb/awvalid
add wave -noupdate -group {AXI write} -label awready $tb/awready
add wave -noupdate -group {AXI write} -label wdata -radix hexadecimal $tb/wdata
add wave -noupdate -group {AXI write} -label wvalid $tb/wvalid
add wave -noupdate -group {AXI write} -label wready $tb/wready
add wave -noupdate -group {AXI write} -label bvalid $tb/bvalid
add wave -noupdate -group {AXI write} -label bready $tb/bready
add wave -noupdate -group {AXI write} -label bresp -radix hexadecimal $tb/bresp

add wave -noupdate -group {AXI read} -label araddr -radix hexadecimal $tb/araddr
add wave -noupdate -group {AXI read} -label arvalid $tb/arvalid
add wave -noupdate -group {AXI read} -label arready $tb/arready
add wave -noupdate -group {AXI read} -label rdata -radix hexadecimal $tb/rdata
add wave -noupdate -group {AXI read} -label rvalid $tb/rvalid
add wave -noupdate -group {AXI read} -label rready $tb/rready
add wave -noupdate -group {AXI read} -label rresp -radix hexadecimal $tb/rresp

add wave -noupdate -group Registers -label engine_en $axil/engine_en
add wave -noupdate -group Registers -label flush $axil/flush
add wave -noupdate -group Registers -label clkdiv -radix unsigned $axil/clkdiv
add wave -noupdate -group Registers -label nbits_m1 -radix unsigned $axil/cfg_nbm1
add wave -noupdate -group Registers -label mode $axil/cfg_mode
add wave -noupdate -group Registers -label tms_last $axil/cfg_tms_last
add wave -noupdate -group Registers -label capture $axil/cfg_capture
add wave -noupdate -group Registers -label busy $axil/busy
add wave -noupdate -group Registers -label cycles -radix unsigned $axil/cycles

add wave -noupdate -group Engine -label state $core/state
add wave -noupdate -group Engine -label bit_index -radix unsigned $core/idx_q
add wave -noupdate -group Engine -label phase_count -radix unsigned $core/cnt_q
add wave -noupdate -group Engine -label nbits_m1 -radix unsigned $core/nbm1_q
add wave -noupdate -group Engine -label mode $core/mode_q
add wave -noupdate -group Engine -label tms_last $core/tlast_q
add wave -noupdate -group Engine -label capture $core/capt_q
add wave -noupdate -group Engine -label shift_data -radix hexadecimal $core/data_q
add wave -noupdate -group Engine -label captured -radix hexadecimal $core/cap_q
add wave -noupdate -group Engine -label tdo_sync $core/tdo_sync
add wave -noupdate -group Engine -label tck $core/tck_o
add wave -noupdate -group Engine -label tms $core/tms_o
add wave -noupdate -group Engine -label tdi $core/tdi_o

add wave -noupdate -group FIFOs -label tx_level -radix unsigned $axil/tx_level
add wave -noupdate -group FIFOs -label tx_empty $axil/tx_empty
add wave -noupdate -group FIFOs -label tx_full $axil/tx_full
add wave -noupdate -group FIFOs -label rx_level -radix unsigned $axil/rx_level
add wave -noupdate -group FIFOs -label rx_empty $axil/rx_empty
add wave -noupdate -group FIFOs -label rx_full $axil/rx_full

configure wave -namecolwidth 220
configure wave -valuecolwidth 120
configure wave -timelineunits ns
configure wave -signalnamewidth 1
WaveRestoreZoom {0 ns} {2000 ns}
