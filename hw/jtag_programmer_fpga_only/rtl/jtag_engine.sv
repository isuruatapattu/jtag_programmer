`timescale 1ns / 1ps
// JTAG pin engine.
//
// Executes one work item at a time:
//   * clock item (item_wait = 0): one TCK cycle. At the falling edge TMS and
//     TDI take the item values (TDI keeps its value when item_hold = 1).
//     TCK is low for `half` clocks, then high for `half` clocks.
//   * wait item (item_wait = 1): TCK stays high for item_us microseconds.
// TCK idles high. An item is accepted (item_valid && item_ready) when the
// engine is idle or in the last cycle of a TCK high phase, so back-to-back
// clock items give a continuous TCK.
//
// TDO is launched by the target on the falling edge and must be stable at
// the end of the TCK cycle. It passes through an IOB register and one more
// synchronizer stage; the value captured by the IOB register at the edge
// that ends the cycle (just before the next falling edge reaches the pin)
// is compared TDO_LAG clocks later against the expected value, if the item
// asked for a check. The first mismatch is sticky and records its 0-based
// TCK index.
module jtag_engine #(
    parameter int CLK_PER_US = 100,
    parameter int TDO_LAG    = 2
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,

    input  logic [15:0] half,

    input  logic        item_valid,
    output logic        item_ready,
    input  logic        item_wait,
    input  logic        item_tms,
    input  logic        item_tdi,
    input  logic        item_hold,
    input  logic        item_chk,
    input  logic        item_exp,
    input  logic [31:0] item_us,

    input  logic        cancel_wait,

    output logic        idle,
    output logic [63:0] tck_count,
    output logic        err,
    output logic [63:0] err_tck,

    output logic        tck_o,
    output logic        tms_o,
    output logic        tdi_o,
    input  logic        tdo_i
);

    typedef enum logic [1:0] {
        E_IDLE,
        E_LOW,
        E_HIGH,
        E_WAIT
    } state_t;

    state_t      state;
    logic [15:0] cnt;
    logic [15:0] half_q;
    logic        cur_chk;
    logic        cur_exp;
    logic [31:0] us_left;
    logic [6:0]  us_pre;

    (* IOB = "TRUE" *) logic tck_q;
    (* IOB = "TRUE" *) logic tms_q;
    (* IOB = "TRUE" *) logic tdi_q;
    (* IOB = "TRUE" *) logic tdo_q;
    logic tdo_s;

    assign tck_o = tck_q;
    assign tms_o = tms_q;
    assign tdi_o = tdi_q;

    logic last_high;
    assign last_high  = (state == E_HIGH) && (cnt == 16'd0);
    assign item_ready = (state == E_IDLE) || last_high;

    logic take;
    assign take = item_valid && item_ready;

    // Compare pipeline: entry k describes the clock that ended k+1 cycles ago.
    logic        pend_v   [0:TDO_LAG-1];
    logic        pend_exp [0:TDO_LAG-1];
    logic [63:0] pend_tck [0:TDO_LAG-1];
    logic        pend_any;

    always_comb begin
        pend_any = 1'b0;
        for (int i = 0; i < TDO_LAG; i++)
            pend_any = pend_any | pend_v[i];
    end

    assign idle = (state == E_IDLE) && !pend_any;

    always_ff @(posedge clk) begin
        tdo_q <= tdo_i;
        tdo_s <= tdo_q;
    end

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            state     <= E_IDLE;
            cnt       <= 16'd0;
            half_q    <= 16'd5;
            cur_chk   <= 1'b0;
            cur_exp   <= 1'b0;
            us_left   <= 32'd0;
            us_pre    <= 7'd0;
            tck_q     <= 1'b1;
            tms_q     <= 1'b1;
            tdi_q     <= 1'b0;
            tck_count <= 64'd0;
            err       <= 1'b0;
            err_tck   <= 64'd0;
            for (int i = 0; i < TDO_LAG; i++) begin
                pend_v[i]   <= 1'b0;
                pend_exp[i] <= 1'b0;
                pend_tck[i] <= 64'd0;
            end
        end else begin
            // Compare stage.
            for (int i = 1; i < TDO_LAG; i++) begin
                pend_v[i]   <= pend_v[i-1];
                pend_exp[i] <= pend_exp[i-1];
                pend_tck[i] <= pend_tck[i-1];
            end
            pend_v[0] <= last_high && cur_chk;
            pend_exp[0] <= cur_exp;
            pend_tck[0] <= tck_count - 64'd1;
            if (pend_v[TDO_LAG-1] && (tdo_s != pend_exp[TDO_LAG-1]) && !err) begin
                err     <= 1'b1;
                err_tck <= pend_tck[TDO_LAG-1];
            end

            case (state)
                E_LOW: begin
                    if (cnt == 16'd0) begin
                        tck_q <= 1'b1;
                        cnt   <= half_q - 16'd1;
                        state <= E_HIGH;
                    end else begin
                        cnt <= cnt - 16'd1;
                    end
                end
                E_HIGH: begin
                    if (cnt != 16'd0)
                        cnt <= cnt - 16'd1;
                    else
                        state <= E_IDLE;
                end
                E_WAIT: begin
                    if (cancel_wait || (us_left == 32'd0)) begin
                        state <= E_IDLE;
                    end else if (us_pre == 7'(CLK_PER_US - 1)) begin
                        us_pre  <= 7'd0;
                        us_left <= us_left - 32'd1;
                        if (us_left == 32'd1)
                            state <= E_IDLE;
                    end else begin
                        us_pre <= us_pre + 7'd1;
                    end
                end
                default: ;
            endcase

            if (take) begin
                if (item_wait) begin
                    us_left <= item_us;
                    us_pre  <= 7'd0;
                    state   <= E_WAIT;
                end else begin
                    tck_q     <= 1'b0;
                    tms_q     <= item_tms;
                    if (!item_hold)
                        tdi_q <= item_tdi;
                    cur_chk   <= item_chk;
                    cur_exp   <= item_exp;
                    half_q    <= half;
                    cnt       <= half - 16'd1;
                    tck_count <= tck_count + 64'd1;
                    state     <= E_LOW;
                end
            end
        end
    end

endmodule
