// AXI4-Lite slave front end for axi_gpio_jtag.
//
// Implements GPIO-AXI-001..022 and the handshake part of GPIO-RST-001..005 from
// doc/axi_gpio_jtag_spec.md. It knows nothing about GPIO: it turns AXI
// transactions into a plain register port.
//
// Write path
//   awready and wready are flip-flops. They are 1 only while no write
//   address, no write data and no response are held. When both the address
//   and the data have been taken (in the same cycle or in two cycles, in
//   either order) the write is committed on that clock edge: reg_wr_en is 1
//   in that cycle, and bvalid goes 1 at the same edge. The register file
//   therefore already holds the new value in the first cycle of bvalid
//   (GPIO-AXI-008). A new address or data is not accepted until the B
//   handshake is done (GPIO-AXI-005).
//
// Read path
//   arready is a flip-flop that is 1 while no read response is held. On the
//   AR handshake, reg_rd_data is captured into rdata and rvalid goes 1 at the
//   same edge. rdata and rvalid are held until the R handshake.
//
// bvalid and rvalid are flip-flops. They never depend on bready or rready in
// the same cycle (GPIO-AXI-020). bresp and rresp are always OKAY
// (GPIO-AXI-022).

`timescale 1ns / 1ps

module axi_lite_slave (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [8:0]  awaddr,
    input  wire        awvalid,
    output reg         awready,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    input  wire        wvalid,
    output reg         wready,
    output wire [1:0]  bresp,
    output reg         bvalid,
    input  wire        bready,

    input  wire [8:0]  araddr,
    input  wire        arvalid,
    output reg         arready,
    output reg  [31:0] rdata,
    output wire [1:0]  rresp,
    output reg         rvalid,
    input  wire        rready,

    // Register port
    output wire        reg_wr_en,
    output wire [8:0]  reg_wr_addr,
    output wire [31:0] reg_wr_data,
    output wire [3:0]  reg_wr_strb,
    output wire [8:0]  reg_rd_addr,
    input  wire [31:0] reg_rd_data
);

    assign bresp = 2'b00;
    assign rresp = 2'b00;

    // ------------------------------------------------------------------
    // Write channel
    // ------------------------------------------------------------------
    reg         aw_seen;
    reg         w_seen;
    reg  [8:0]  awaddr_q;
    reg  [31:0] wdata_q;
    reg  [3:0]  wstrb_q;

    wire aw_hs   = awvalid & awready;
    wire w_hs    = wvalid  & wready;
    wire aw_have = aw_seen | aw_hs;
    wire w_have  = w_seen  | w_hs;
    wire commit  = aw_have & w_have;

    // A handshake in this cycle takes its value straight from the input. A
    // value taken in an earlier cycle comes from the holding register.
    assign reg_wr_en   = commit;
    assign reg_wr_addr = aw_seen ? awaddr_q : awaddr;
    assign reg_wr_data = w_seen  ? wdata_q  : wdata;
    assign reg_wr_strb = w_seen  ? wstrb_q  : wstrb;

    wire aw_seen_n = aw_have & ~commit;
    wire w_seen_n  = w_have  & ~commit;
    wire bvalid_n  = commit | (bvalid & ~bready);

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_seen  <= 1'b0;
            w_seen   <= 1'b0;
            awaddr_q <= 9'd0;
            wdata_q  <= 32'd0;
            wstrb_q  <= 4'd0;
            bvalid   <= 1'b0;
            awready  <= 1'b0;
            wready   <= 1'b0;
        end else begin
            aw_seen <= aw_seen_n;
            w_seen  <= w_seen_n;
            bvalid  <= bvalid_n;

            if (aw_hs) awaddr_q <= awaddr;
            if (w_hs) begin
                wdata_q <= wdata;
                wstrb_q <= wstrb;
            end

            awready <= ~aw_seen_n & ~bvalid_n;
            wready  <= ~w_seen_n  & ~bvalid_n;
        end
    end

    // ------------------------------------------------------------------
    // Read channel
    // ------------------------------------------------------------------
    wire ar_hs    = arvalid & arready;
    wire rvalid_n = ar_hs | (rvalid & ~rready);

    assign reg_rd_addr = araddr;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rvalid  <= 1'b0;
            arready <= 1'b0;
            rdata   <= 32'd0;
        end else begin
            rvalid  <= rvalid_n;
            arready <= ~rvalid_n;
            rdata <= reg_rd_data;
        end
    end

endmodule
