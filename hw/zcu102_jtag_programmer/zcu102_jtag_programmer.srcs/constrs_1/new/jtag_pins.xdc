# ============================================================
# ZCU102 JTAG Programmer GPIO
# J55 PMOD Connector
#
# jtag_out[0] = TCK
# jtag_out[1] = TMS
# jtag_out[2] = TDI
# jtag_out[3] = unused/dummy
#
# jtag_in[0]  = TDO
# jtag_in[1]  = unused/dummy
# jtag_in[2]  = unused/dummy
# jtag_in[3]  = unused/dummy
# ============================================================


# ------------------------------------------------------------
# JTAG outputs
# ------------------------------------------------------------

# TCK - J55.1
set_property PACKAGE_PIN A20 [get_ports {jtag_out[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_out[0]}]

# TMS - J55.3
set_property PACKAGE_PIN B20 [get_ports {jtag_out[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_out[1]}]

# TDI - J55.5
set_property PACKAGE_PIN A22 [get_ports {jtag_out[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_out[2]}]

# Dummy output - J55.2
set_property PACKAGE_PIN B21 [get_ports {jtag_out[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_out[3]}]


# ------------------------------------------------------------
# JTAG inputs
# ------------------------------------------------------------

# TDO - J55.7
set_property PACKAGE_PIN A21 [get_ports {jtag_in[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_in[0]}]

# Dummy input - J55.4
set_property PACKAGE_PIN C21 [get_ports {jtag_in[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_in[1]}]

# Dummy input - J55.6
set_property PACKAGE_PIN C22 [get_ports {jtag_in[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_in[2]}]

# Dummy input - J55.8
set_property PACKAGE_PIN D21 [get_ports {jtag_in[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_in[3]}]