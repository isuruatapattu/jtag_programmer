// axi_gpio_jtag - custom AXI4-Lite GPIO for the Nexys A7 JTAG port.
//
// Replaces the Xilinx axi_gpio_0 (dual channel, 4 bits per channel, channel 1
// all outputs, channel 2 all inputs, no interrupt). See
// doc/axi_gpio_jtag_spec.md.
//
// This file is Verilog-2001 on purpose (GPIO-IF-008) so Vivado IP Integrator
// can add it as a module reference. The X_INTERFACE_* attributes make Vivado
// group the ports into the S_AXI bus interface, the clock and the reset
// (GPIO-IF-007).

`timescale 1ns / 1ps

module axi_gpio_jtag (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn" *)
    input  wire        s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aresetn, POLARITY ACTIVE_LOW" *)
    input  wire        s_axi_aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, ADDR_WIDTH 9, DATA_WIDTH 32, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0" *)
    input  wire [8:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [8:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        s_axi_rready,

    output wire [3:0]  gpio_io_o,
    input  wire [3:0]  gpio2_io_i
);

    wire        reg_wr_en;
    wire [8:0]  reg_wr_addr;
    wire [31:0] reg_wr_data;
    wire [3:0]  reg_wr_strb;
    wire [8:0]  reg_rd_addr;
    wire [31:0] reg_rd_data;

    axi_lite_slave u_slave (
        .aclk        (s_axi_aclk),
        .aresetn     (s_axi_aresetn),
        .awaddr      (s_axi_awaddr),
        .awvalid     (s_axi_awvalid),
        .awready     (s_axi_awready),
        .wdata       (s_axi_wdata),
        .wstrb       (s_axi_wstrb),
        .wvalid      (s_axi_wvalid),
        .wready      (s_axi_wready),
        .bresp       (s_axi_bresp),
        .bvalid      (s_axi_bvalid),
        .bready      (s_axi_bready),
        .araddr      (s_axi_araddr),
        .arvalid     (s_axi_arvalid),
        .arready     (s_axi_arready),
        .rdata       (s_axi_rdata),
        .rresp       (s_axi_rresp),
        .rvalid      (s_axi_rvalid),
        .rready      (s_axi_rready),
        .reg_wr_en   (reg_wr_en),
        .reg_wr_addr (reg_wr_addr),
        .reg_wr_data (reg_wr_data),
        .reg_wr_strb (reg_wr_strb),
        .reg_rd_addr (reg_rd_addr),
        .reg_rd_data (reg_rd_data)
    );

    gpio_jtag_regs u_regs (
        .clk        (s_axi_aclk),
        .aresetn    (s_axi_aresetn),
        .wr_en      (reg_wr_en),
        .wr_addr    (reg_wr_addr),
        .wr_data    (reg_wr_data),
        .wr_strb    (reg_wr_strb),
        .rd_addr    (reg_rd_addr),
        .rd_data    (reg_rd_data),
        .gpio_io_o  (gpio_io_o),
        .gpio2_io_i (gpio2_io_i)
    );

endmodule
