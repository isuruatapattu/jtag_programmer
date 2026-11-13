// JTAG bit engine: TX command FIFO, clock divider, TDO synchronizer and
// RX capture FIFO.
//
// TX command word (40 bits):
//   [31:0]  data      TDI bits (MODE 0) or TMS bits (MODE 1), bit 0 first
//   [36:32] nbits_m1  number of bits minus 1
//   [37]    mode      0: TDI = data, TMS = 0; 1: TMS = data, TDI held
//   [38]    tms_last  MODE 0 only: TMS = 1 on the last bit
//   [39]    capture   push the captured TDO word into the RX FIFO
//
// Each bit is CLKDIV cycles with TCK low, then CLKDIV cycles with TCK high.
// TMS and TDI change together with the falling edge. TDO (after the 2-FF
// synchronizer) is sampled in the cycle that ends the high phase.
module jtag_shifter_core #(
    parameter int TX_DEPTH = 512,
    parameter int RX_DEPTH = 256
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      flush,
    input  logic [15:0]               clkdiv,

    input  logic                      tx_wr,
    input  logic [39:0]               tx_din,
    output logic                      tx_full,
    output logic                      tx_empty,
    output logic [$clog2(TX_DEPTH):0] tx_level,

    input  logic                      rx_rd,
    output logic [31:0]               rx_dout,
    output logic                      rx_full,
    output logic                      rx_empty,
    output logic [$clog2(RX_DEPTH):0] rx_level,

    output logic                      busy,

    input  logic                      tdo_i,
    output logic                      tck_o,
    output logic                      tms_o,
    output logic                      tdi_o
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_LOW,
        S_HIGH,
        S_PUSH
    } state_t;

    state_t      state;
    logic [39:0] tx_dout;
    logic        tx_rd;
    logic        rx_wr;

    logic [31:0] data_q;
    logic [31:0] cap_q;
    logic [4:0]  nbm1_q;
    logic [4:0]  idx_q;
    logic        mode_q;
    logic        tlast_q;
    logic        capt_q;
    logic [15:0] cnt_q;
    logic [15:0] div_m1;

    (* ASYNC_REG = "TRUE" *) logic tdo_meta;
    (* ASYNC_REG = "TRUE" *) logic tdo_sync;

    always_ff @(posedge clk) begin
        tdo_meta <= tdo_i;
        tdo_sync <= tdo_meta;
    end

    assign div_m1 = (clkdiv == 16'd0) ? 16'd0 : (clkdiv - 16'd1);
    assign tx_rd  = (state == S_IDLE) && !tx_empty && !flush;
    assign rx_wr  = (state == S_PUSH) && !rx_full && !flush;
    assign busy   = (state != S_IDLE) || !tx_empty;

    jtag_shifter_fifo #(
        .WIDTH(40),
        .DEPTH(TX_DEPTH)
    ) u_tx_fifo (
        .clk  (clk),
        .rst_n(rst_n),
        .clear(flush),
        .wr_en(tx_wr),
        .din  (tx_din),
        .full (tx_full),
        .rd_en(tx_rd),
        .dout (tx_dout),
        .empty(tx_empty),
        .level(tx_level)
    );

    jtag_shifter_fifo #(
        .WIDTH(32),
        .DEPTH(RX_DEPTH)
    ) u_rx_fifo (
        .clk  (clk),
        .rst_n(rst_n),
        .clear(flush),
        .wr_en(rx_wr),
        .din  (cap_q),
        .full (rx_full),
        .rd_en(rx_rd),
        .dout (rx_dout),
        .empty(rx_empty),
        .level(rx_level)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            data_q  <= '0;
            cap_q   <= '0;
            nbm1_q  <= '0;
            idx_q   <= '0;
            mode_q  <= 1'b0;
            tlast_q <= 1'b0;
            capt_q  <= 1'b0;
            cnt_q   <= '0;
            tck_o   <= 1'b0;
            tms_o   <= 1'b0;
            tdi_o   <= 1'b0;
        end else if (flush) begin
            state <= S_IDLE;
            tck_o <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (tx_rd) begin
                        data_q  <= tx_dout[31:0];
                        nbm1_q  <= tx_dout[36:32];
                        mode_q  <= tx_dout[37];
                        tlast_q <= tx_dout[38];
                        capt_q  <= tx_dout[39];
                        cap_q   <= '0;
                        idx_q   <= '0;
                        cnt_q   <= div_m1;
                        tck_o   <= 1'b0;
                        if (tx_dout[37]) begin
                            tms_o <= tx_dout[0];
                        end else begin
                            tdi_o <= tx_dout[0];
                            tms_o <= tx_dout[38] && (tx_dout[36:32] == 5'd0);
                        end
                        state <= S_LOW;
                    end
                end

                S_LOW: begin
                    if (cnt_q == 16'd0) begin
                        tck_o <= 1'b1;
                        cnt_q <= div_m1;
                        state <= S_HIGH;
                    end else begin
                        cnt_q <= cnt_q - 16'd1;
                    end
                end

                S_HIGH: begin
                    if (cnt_q == 16'd0) begin
                        tck_o        <= 1'b0;
                        cap_q[idx_q] <= tdo_sync;
                        if (idx_q == nbm1_q) begin
                            state <= capt_q ? S_PUSH : S_IDLE;
                        end else begin
                            idx_q <= idx_q + 5'd1;
                            cnt_q <= div_m1;
                            if (mode_q) begin
                                tms_o <= data_q[idx_q + 5'd1];
                            end else begin
                                tdi_o <= data_q[idx_q + 5'd1];
                                tms_o <= tlast_q && ((idx_q + 5'd1) == nbm1_q);
                            end
                            state <= S_LOW;
                        end
                    end else begin
                        cnt_q <= cnt_q - 16'd1;
                    end
                end

                S_PUSH: begin
                    if (rx_wr) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
