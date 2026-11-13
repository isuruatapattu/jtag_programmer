// Register file for axi_gpio_jtag.
//
// Implements GPIO-ADR-*, GPIO-REG-*, GPIO-STB-*, GPIO-SYN-* and the register
// part of GPIO-RST-* from doc/axi_gpio_jtag_spec.md.
//
//   0x000 DATA   R/W  reset 0x0   drives gpio_io_o
//   0x004 TRI    R/W  reset 0x0   stored only, no effect on pins
//   0x008 DATA2  RO               synchronized gpio2_io_i
//   0x00C TRI2   R/W  reset 0xF   stored only, no effect on pins
//
// Only bits [3:0] hold state. Bits [31:4] read as 0.

`timescale 1ns / 1ps

module gpio_jtag_regs (
    input  wire        clk,
    input  wire        aresetn,

    input  wire        wr_en,
    input  wire [8:0]  wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_strb,

    input  wire [8:0]  rd_addr,
    output reg  [31:0] rd_data,

    output wire [3:0]  gpio_io_o,
    input  wire [3:0]  gpio2_io_i
);

    // Register index is addr[8:2]. addr[1:0] is ignored (GPIO-ADR-001).
    localparam [6:0] IDX_DATA  = 7'd0;
    localparam [6:0] IDX_TRI   = 7'd1;
    localparam [6:0] IDX_DATA2 = 7'd2;
    localparam [6:0] IDX_TRI2  = 7'd3;

    reg [3:0] data_q;
    reg [3:0] tri_q;
    reg [3:0] tri2_q;

    // Two-stage input synchronizer. It is not reset (GPIO-RST-006). The
    // initial values only keep simulation free of X before the first clocks.
    (* ASYNC_REG = "TRUE" *) reg [3:0] sync_q1 = 4'd0;
    (* ASYNC_REG = "TRUE" *) reg [3:0] sync_q2 = 4'd0;

    // wstrb[0] gates every write. wstrb[3:1] is ignored (GPIO-STB-001/002).
    wire wr_ok = wr_en & wr_strb[0];

    always @(posedge clk) begin
        if (!aresetn) begin
            data_q <= 4'h0;
            tri_q  <= 4'h0;
            tri2_q <= 4'hF;
        end else if (wr_ok) begin
            case (wr_addr[8:2])
                IDX_DATA: data_q <= wr_data[3:0];
                IDX_TRI:  tri_q  <= wr_data[3:0];
                IDX_TRI2: tri2_q <= wr_data[3:0];
                default: ;  // DATA2 and unmapped offsets ignore writes
            endcase
        end
    end

    always @(posedge clk) begin
        sync_q1 <= gpio2_io_i;
        sync_q2 <= sync_q1;
    end

    always @(*) begin
        case (rd_addr[8:2])
            IDX_DATA:  rd_data = {28'd0, data_q};
            IDX_TRI:   rd_data = {28'd0, tri_q};
            IDX_DATA2: rd_data = {28'd0, sync_q2};
            IDX_TRI2:  rd_data = {28'd0, tri2_q};
            default:   rd_data = {28'd0, data_q};
        endcase
    end

    // GPIO-TIM-001: the port is the flip-flop output, with no logic between.
    assign gpio_io_o = data_q;

endmodule
