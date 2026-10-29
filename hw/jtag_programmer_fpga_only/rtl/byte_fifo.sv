`timescale 1ns / 1ps
// Synchronous first-word-fall-through byte FIFO.
//
// `dout` is valid whenever `empty` is 0; `rd_en` pops it.
// `room` is 1 when at least ROOM more bytes can be written without
// overflowing, so a producer can commit to a burst of ROOM bytes.
//
// USE_XPM = 1 uses xpm_fifo_sync (block RAM). USE_XPM = 0 uses an inferred
// memory, for simulators without the Xilinx XPM library.
module byte_fifo #(
    parameter int DEPTH   = 4096,
    parameter int ROOM    = 320,
    parameter int USE_XPM = 1
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       wr_en,
    input  logic [7:0] din,
    input  logic       rd_en,
    output logic [7:0] dout,
    output logic       empty,
    output logic       room,
    output logic       overflow
);

    localparam int CW = $clog2(DEPTH) + 1;

    generate
        if (USE_XPM != 0) begin : g_xpm
            logic          xpm_empty;
            logic          xpm_full;
            logic          wr_rst_busy;
            logic          rd_rst_busy;
            logic [CW-1:0] wr_count;

            xpm_fifo_sync #(
                .FIFO_MEMORY_TYPE    ("block"),
                .ECC_MODE            ("no_ecc"),
                .FIFO_WRITE_DEPTH    (DEPTH),
                .WRITE_DATA_WIDTH    (8),
                .READ_DATA_WIDTH     (8),
                .WR_DATA_COUNT_WIDTH (CW),
                .RD_DATA_COUNT_WIDTH (CW),
                .PROG_FULL_THRESH    (10),
                .PROG_EMPTY_THRESH   (10),
                .FULL_RESET_VALUE    (0),
                .USE_ADV_FEATURES    ("0004"),
                .READ_MODE           ("fwft"),
                .FIFO_READ_LATENCY   (0),
                .DOUT_RESET_VALUE    ("0"),
                .SIM_ASSERT_CHK      (0),
                .WAKEUP_TIME         (0)
            ) u_fifo (
                .sleep         (1'b0),
                .rst           (rst),
                .wr_clk        (clk),
                .wr_en         (wr_en),
                .din           (din),
                .full          (xpm_full),
                .prog_full     (),
                .wr_data_count (wr_count),
                .overflow      (),
                .wr_rst_busy   (wr_rst_busy),
                .almost_full   (),
                .wr_ack        (),
                .rd_en         (rd_en && !xpm_empty && !rd_rst_busy),
                .dout          (dout),
                .empty         (xpm_empty),
                .prog_empty    (),
                .rd_data_count (),
                .underflow     (),
                .rd_rst_busy   (rd_rst_busy),
                .almost_empty  (),
                .data_valid    (),
                .injectsbiterr (1'b0),
                .injectdbiterr (1'b0),
                .sbiterr       (),
                .dbiterr       ()
            );

            assign empty = xpm_empty || rd_rst_busy;

            // wr_data_count lags by a cycle and may include the FWFT output
            // stage; ROOM carries enough margin for both.
            always_ff @(posedge clk) begin
                room <= !rst && !wr_rst_busy && !xpm_full &&
                        (wr_count <= CW'(DEPTH - ROOM));
                if (rst)
                    overflow <= 1'b0;
                else if (wr_en && (xpm_full || wr_rst_busy))
                    overflow <= 1'b1;
            end
        end else begin : g_inferred
            localparam int AW = $clog2(DEPTH);

            logic [7:0]    mem [0:DEPTH-1];
            logic [AW-1:0] wr_ptr;
            logic [AW-1:0] rd_ptr;
            logic [CW-1:0] count;
            logic          do_wr;
            logic          do_rd;

            assign empty = (count == 0);
            assign dout  = mem[rd_ptr];
            assign do_rd = rd_en && !empty;
            assign do_wr = wr_en && (count != CW'(DEPTH));

            always_ff @(posedge clk) begin
                if (do_wr)
                    mem[wr_ptr] <= din;
                if (rst) begin
                    wr_ptr   <= '0;
                    rd_ptr   <= '0;
                    count    <= '0;
                    room     <= 1'b0;
                    overflow <= 1'b0;
                end else begin
                    if (do_wr)
                        wr_ptr <= wr_ptr + 1'b1;
                    if (do_rd)
                        rd_ptr <= rd_ptr + 1'b1;
                    count <= count + CW'(do_wr) - CW'(do_rd);
                    room  <= (count <= CW'(DEPTH - ROOM));
                    if (wr_en && !do_wr)
                        overflow <= 1'b1;
                end
            end
        end
    endgenerate

endmodule
