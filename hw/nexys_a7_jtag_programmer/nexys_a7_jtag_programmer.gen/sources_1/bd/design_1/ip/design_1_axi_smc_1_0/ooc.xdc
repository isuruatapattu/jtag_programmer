# aclk {FREQ_HZ 100000000 CLK_DOMAIN design_1_clk_100MHz PHASE 0.0} aclk1 {FREQ_HZ 81247969 CLK_DOMAIN design_1_mig_7series_0_0_ui_clk PHASE 0}
# Clock Domain: design_1_clk_100MHz
create_clock -name aclk -period 10.000 [get_ports aclk]
# Clock Domain: design_1_mig_7series_0_0_ui_clk
create_clock -name aclk1 -period 12.308 [get_ports aclk1]
# Generated clocks
