# Wave setup for the JTAG GPIO example. sim/gui.sh launches vsim -gui -do this.
#
# Pin names match sw/nexys_a7/app_mb_svf_player/svf_player.c:
#   gpio_io_o[0]  TCK  JA1     written through DATA (0x000)
#   gpio_io_o[1]  TMS  JA2
#   gpio_io_o[2]  TDI  JA3
#   gpio2_io_i[0] TDO  JA7     read through DATA2 (0x008), after two flops
#
# Default test t_sw_loopback is the JA1-to-JA7 jumper:
#   write DATA = 0, TDO pin follows TCK, wait 3 clocks, read DATA2
#   write DATA = 1, same read-back, then drive TCK low again.
# The read data is the synchronizer output, so DATA2[0] moves two clocks
# after the TDO pin.

onerror {resume}

set TB /tb_axi_gpio_jtag

log -r $TB/dut/*
log -r $TB/axi/*
log $TB/aclk $TB/gpio_io_o $TB/gpio2_io_i

view wave
delete wave *

configure wave -namecolwidth 320
configure wave -valuecolwidth 100
configure wave -timelineunits ns
configure wave -signalnamewidth 1

add wave -divider "Clock and reset"
add wave -noupdate -label aclk $TB/aclk
add wave -noupdate -label s_axi_aresetn $TB/axi/aresetn

add wave -divider "JTAG pins"
add wave -noupdate -group "JTAG pins" -radix binary -color yellow \
    -label "TCK  JA1  gpio_io_o\[0\]" "$TB/gpio_io_o\[0\]"
add wave -noupdate -group "JTAG pins" -radix binary -color orange \
    -label "TMS  JA2  gpio_io_o\[1\]" "$TB/gpio_io_o\[1\]"
add wave -noupdate -group "JTAG pins" -radix binary -color cyan \
    -label "TDI  JA3  gpio_io_o\[2\]" "$TB/gpio_io_o\[2\]"
add wave -noupdate -group "JTAG pins" -radix binary -color green \
    -label "TDO  JA7  gpio2_io_i\[0\]" "$TB/gpio2_io_i\[0\]"
add wave -noupdate -group "JTAG pins" -radix binary -color green \
    -label "TDO after 1 clock" "$TB/dut/u_regs/sync_q1\[0\]"
add wave -noupdate -group "JTAG pins" -radix binary -color green \
    -label "TDO read by firmware (DATA2\[0\])" "$TB/dut/u_regs/sync_q2\[0\]"

add wave -divider "Output register  (0x000 DATA)"
add wave -noupdate -group "Registers" -radix binary \
    -label "DATA   gpio_io_o" $TB/dut/u_regs/data_q
add wave -noupdate -group "Registers" -radix binary \
    -label "TRI    0x004 stored only" $TB/dut/u_regs/tri_q
add wave -noupdate -group "Registers" -radix binary \
    -label "TRI2   0x00C stored only" $TB/dut/u_regs/tri2_q

add wave -divider "AXI write   addr 000 DATA, 004 TRI, 008 DATA2, 00C TRI2"
add wave -noupdate -group "AXI write" $TB/axi/awvalid
add wave -noupdate -group "AXI write" $TB/axi/awready
add wave -noupdate -group "AXI write" -radix hexadecimal \
    -label awaddr $TB/axi/awaddr
add wave -noupdate -group "AXI write" $TB/axi/wvalid
add wave -noupdate -group "AXI write" $TB/axi/wready
add wave -noupdate -group "AXI write" -radix hexadecimal \
    -label wdata $TB/axi/wdata
add wave -noupdate -group "AXI write" -radix binary \
    -label wstrb $TB/axi/wstrb
add wave -noupdate -group "AXI write" $TB/axi/bvalid
add wave -noupdate -group "AXI write" $TB/axi/bready
add wave -noupdate -group "AXI write" -radix binary \
    -label bresp $TB/axi/bresp

add wave -divider "AXI read"
add wave -noupdate -group "AXI read" $TB/axi/arvalid
add wave -noupdate -group "AXI read" $TB/axi/arready
add wave -noupdate -group "AXI read" -radix hexadecimal \
    -label araddr $TB/axi/araddr
add wave -noupdate -group "AXI read" $TB/axi/rvalid
add wave -noupdate -group "AXI read" $TB/axi/rready
add wave -noupdate -group "AXI read" -radix hexadecimal \
    -label rdata $TB/axi/rdata
add wave -noupdate -group "AXI read" -radix binary \
    -label rresp $TB/axi/rresp

TreeUpdate [SetDefaultTree]
wave zoomfull

echo "Running. Look for TCK (yellow) copied onto TDO (green), then DATA2 two clocks later."
run -all
wave zoomfull
