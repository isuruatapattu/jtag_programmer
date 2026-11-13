# Wave layout for axi_mapped_registers_tb.
# Read top to bottom the same way a write happens:
#   clock -> address channel -> data channel -> response
#   -> captured address/data inside axi_write_logic
#   -> register file that is updated

onerror {resume}
quietly WaveActivateNextPane {} 0

set tb /axi_mapped_registers_tb
set wr $tb/dut/wrinst

# -----------------------------------------------------------------------------
# Clock and reset
# -----------------------------------------------------------------------------
add wave -noupdate -divider -height 22 {Clock and reset}

add wave -noupdate -label clk   -color Yellow $tb/ACLK
add wave -noupdate -label rst_n -color Orange $tb/ARESETN

# -----------------------------------------------------------------------------
# AXI4-Lite write channels.
# VALID is next to READY so the handshake is one glance.
# -----------------------------------------------------------------------------
add wave -noupdate -divider -height 22 {AXI write address}

add wave -noupdate -group AW -label awvalid -color Cyan $tb/AWVALID
add wave -noupdate -group AW -label awready -color Cyan $tb/AWREADY
add wave -noupdate -group AW -label awaddr  -color Cyan -radix unsigned $tb/AWADDR

add wave -noupdate -divider -height 22 {AXI write data}

add wave -noupdate -group W -label wvalid -color Green $tb/WVALID
add wave -noupdate -group W -label wready -color Green $tb/WREADY
add wave -noupdate -group W -label wdata  -color Green -radix hexadecimal $tb/WDATA

add wave -noupdate -divider -height 22 {AXI write response}

add wave -noupdate -group B -label bvalid -color Salmon $tb/BVALID
add wave -noupdate -group B -label bready -color Salmon $tb/BREADY
add wave -noupdate -group B -label bresp  -color Salmon -radix binary $tb/BRESP

# -----------------------------------------------------------------------------
# AXI4-Lite read channels
# -----------------------------------------------------------------------------
add wave -noupdate -divider -height 22 {AXI read address}

add wave -noupdate -group AR -label arvalid -color {Light Blue} $tb/ARVALID
add wave -noupdate -group AR -label arready -color {Light Blue} $tb/ARREADY
add wave -noupdate -group AR -label araddr  -color {Light Blue} -radix unsigned $tb/ARADDR

add wave -noupdate -divider -height 22 {AXI read data}

add wave -noupdate -group R -label rvalid -color {Pale Green} $tb/RVALID
add wave -noupdate -group R -label rready -color {Pale Green} $tb/RREADY
add wave -noupdate -group R -label rdata  -color {Pale Green} -radix hexadecimal $tb/RDATA
add wave -noupdate -group R -label rresp  -color {Pale Green} -radix binary $tb/RRESP

# -----------------------------------------------------------------------------
# Inside axi_read_logic: address is latched, then data is fetched and held.
# -----------------------------------------------------------------------------
add wave -noupdate -divider -height 22 {Read logic}

add wave -noupdate -group read_logic -color Turquoise $tb/dut/rdinst/addr_done_r
add wave -noupdate -group read_logic -color Turquoise -radix unsigned    $tb/dut/rdinst/addr_r
add wave -noupdate -group read_logic -color Turquoise -radix hexadecimal $tb/dut/rdinst/data_r

# -----------------------------------------------------------------------------
# Inside axi_write_logic: both handshakes must complete before data_valid.
# -----------------------------------------------------------------------------
add wave -noupdate -divider -height 22 {Write logic}

add wave -noupdate -group capture -color Magenta $wr/addr_done_r
add wave -noupdate -group capture -color Magenta $wr/data_done_r
add wave -noupdate -group capture -label data_valid -color Magenta $wr/data_valid
add wave -noupdate -group capture -label addr_r   -color Magenta -radix unsigned    $wr/addr_r
add wave -noupdate -group capture -label data_r   -color Magenta -radix hexadecimal $wr/data_r

add wave -noupdate -group commit -label write_en -color Violet $tb/dut/write_en
add wave -noupdate -group commit -label wraddr   -color Violet -radix unsigned    $tb/dut/wraddr
add wave -noupdate -group commit -label wdata_in -color Violet -radix hexadecimal $tb/dut/rdata_in

# -----------------------------------------------------------------------------
# Register file. Each entry on its own row so overwrites are obvious.
# -----------------------------------------------------------------------------
add wave -noupdate -divider -height 22 {Register file}

add wave -noupdate -group rfile -label {rfile[0]} -color Gold -radix hexadecimal $tb/dut/rfile(0)
add wave -noupdate -group rfile -label {rfile[1]} -color Gold -radix hexadecimal $tb/dut/rfile(1)
add wave -noupdate -group rfile -label {rfile[2]} -color Gold -radix hexadecimal $tb/dut/rfile(2)
add wave -noupdate -group rfile -label {rfile[3]} -color Gold -radix hexadecimal $tb/dut/rfile(3)

# -----------------------------------------------------------------------------
# Window
# -----------------------------------------------------------------------------
configure wave -namecolwidth  160
configure wave -valuecolwidth 100
configure wave -justifyvalue   left
configure wave -signalnamewidth 1
configure wave -timelineunits ns
configure wave -gridoffset 0
configure wave -gridperiod {10 ns}

TreeUpdate [SetDefaultTree]
quietly wave cursor active 1
update
