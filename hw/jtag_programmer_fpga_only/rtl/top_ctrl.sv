`timescale 1ns / 1ps
// Control state machine of the FPGA-only JTAG programmer.
//
//   1. After reset, wait for the flash JEDEC ID check.
//   2. Ready. `start` (BTNC, or once after reset when `auto_start` is set)
//      runs pass 1: the whole JBIN is decoded with no JTAG activity, which
//      verifies the header, every opcode, the TCK count and the payload
//      CRC. `skip_check` skips pass 1.
//   3. If pass 1 is OK, pass 2 plays the stream on the JTAG pins.
//   4. The result is shown on the LEDs and printed on the UART; then back
//      to ready.
// `abort` (BTNU) stops a pass; the JTAG pins are released (high impedance)
// whenever no play pass is running.
//
// LEDs: 0 ready, 1 busy, 2 OK, 3 TDO mismatch, 4 stream error (header,
// opcode, overrun, CRC, TCK count, argument, timeout), 5 flash ID error,
// 6 aborted, 7 pass 1 running. LEDs 15..8: progress bar while running;
// after a result: all on for OK, the JEDEC manufacturer byte for a flash ID
// error, otherwise the status code.
module top_ctrl #(
    parameter logic [23:0] DATA_ADDR    = 24'h40_0000,
    parameter int          SETUP_CYCLES = 64
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic        abort,
    input  logic        auto_start,
    input  logic        skip_check,

    input  logic        id_done,
    input  logic        id_ok,
    input  logic [23:0] jedec_id,

    output logic        stream_en,
    output logic [23:0] start_addr,
    output logic        fifo_rst,

    output logic        dec_start,
    output logic        dec_dry,
    output logic        dec_abort,
    input  logic        dec_done,
    input  logic [3:0]  dec_status,
    input  logic [63:0] dec_info,
    input  logic        dec_hdr_valid,
    input  logic [63:0] total_tck,
    input  logic [63:0] tck_issued,

    output logic        jtag_oe,
    output logic        eng_clear,

    output logic        uart_send,
    output logic [3:0]  uart_code,
    output logic [63:0] uart_info,

    output logic [15:0] led
);

    localparam logic [3:0] ST_OK     = 4'd1;
    localparam logic [3:0] ST_TDO    = 4'd2;
    localparam logic [3:0] ST_ABORT  = 4'd8;
    localparam logic [3:0] ST_FLID   = 4'd10;
    localparam logic [3:0] ST_FLASHOK = 4'd12;

    typedef enum logic [2:0] {
        T_ID,
        T_IDERR,
        T_READY,
        T_SETUP,
        T_RUN
    } state_t;

    state_t      state;
    logic        pass2;
    logic        auto_done;
    logic        abort_req;
    logic [7:0]  cnt;
    logic [3:0]  result;
    logic        have_result;
    logic [7:0]  progress;
    logic [3:0]  fin_status;

    assign start_addr = DATA_ADDR;
    assign dec_abort  = abort_req;
    assign eng_clear  = (state != T_RUN);

    // An abort that arrives as pass 1 completes still counts as an abort.
    assign fin_status = (abort_req && !pass2 && dec_status == ST_OK) ?
                        ST_ABORT : dec_status;

    always_ff @(posedge clk) begin
        dec_start <= 1'b0;
        uart_send <= 1'b0;
        if (rst) begin
            state       <= T_ID;
            pass2       <= 1'b0;
            auto_done   <= 1'b0;
            abort_req   <= 1'b0;
            cnt         <= 8'd0;
            result      <= 4'd0;
            have_result <= 1'b0;
            stream_en   <= 1'b0;
            fifo_rst    <= 1'b1;
            dec_dry     <= 1'b1;
            jtag_oe     <= 1'b0;
            uart_code   <= 4'd0;
            uart_info   <= 64'd0;
        end else begin
            case (state)
                T_ID: begin
                    if (id_done) begin
                        uart_send <= 1'b1;
                        uart_info <= {40'd0, jedec_id};
                        if (id_ok) begin
                            uart_code <= ST_FLASHOK;
                            state     <= T_READY;
                        end else begin
                            uart_code   <= ST_FLID;
                            result      <= ST_FLID;
                            have_result <= 1'b1;
                            state       <= T_IDERR;
                        end
                    end
                end

                T_IDERR: ;

                T_READY: begin
                    stream_en <= 1'b0;
                    fifo_rst  <= 1'b1;
                    jtag_oe   <= 1'b0;
                    abort_req <= 1'b0;
                    if (start || (auto_start && !auto_done)) begin
                        auto_done   <= 1'b1;
                        have_result <= 1'b0;
                        pass2       <= skip_check;
                        cnt         <= 8'd0;
                        state       <= T_SETUP;
                    end
                end

                // Flush the FIFO, restart the flash stream, start a pass.
                T_SETUP: begin
                    cnt <= cnt + 8'd1;
                    stream_en <= 1'b0;
                    fifo_rst  <= (cnt < 8'd16);
                    jtag_oe   <= pass2;
                    if (abort) begin
                        result      <= ST_ABORT;
                        have_result <= 1'b1;
                        uart_send   <= 1'b1;
                        uart_code   <= ST_ABORT;
                        uart_info   <= 64'd0;
                        state       <= T_READY;
                    end else if (cnt == 8'(SETUP_CYCLES - 1)) begin
                        stream_en <= 1'b1;
                        dec_dry   <= !pass2;
                        dec_start <= 1'b1;
                        state     <= T_RUN;
                    end
                end

                T_RUN: begin
                    if (abort)
                        abort_req <= 1'b1;
                    if (dec_done) begin
                        if (dec_status == ST_OK && !pass2 && !abort_req) begin
                            pass2 <= 1'b1;
                            cnt   <= 8'd0;
                            state <= T_SETUP;
                        end else begin
                            result      <= fin_status;
                            have_result <= 1'b1;
                            uart_send   <= 1'b1;
                            uart_code   <= fin_status;
                            uart_info   <= dec_info;
                            stream_en   <= 1'b0;
                            jtag_oe     <= 1'b0;
                            state       <= T_READY;
                        end
                    end
                end

                default: state <= T_ID;
            endcase
        end
    end

    // Progress bar: LED 8+k lights when tck_issued >= (k+1)/8 of total_tck.
    always_ff @(posedge clk) begin
        for (int k = 0; k < 8; k++)
            progress[k] <= dec_hdr_valid && (total_tck != 64'd0) &&
                           ({tck_issued, 3'd0} >= ({3'd0, total_tck} * 67'(k + 1)));
    end

    logic busy;
    assign busy = (state == T_SETUP) || (state == T_RUN);

    always_ff @(posedge clk) begin
        if (rst) begin
            led <= 16'd0;
        end else begin
            led[0] <= (state == T_READY);
            led[1] <= busy;
            led[2] <= have_result && (result == ST_OK);
            led[3] <= have_result && (result == ST_TDO);
            led[4] <= have_result && (result != ST_OK) && (result != ST_TDO) &&
                      (result != ST_ABORT) && (result != ST_FLID);
            led[5] <= (result == ST_FLID);
            led[6] <= have_result && (result == ST_ABORT);
            led[7] <= busy && !pass2;
            if (busy)
                led[15:8] <= progress;
            else if (!have_result)
                led[15:8] <= 8'd0;
            else if (result == ST_OK)
                led[15:8] <= 8'hFF;
            else if (result == ST_FLID)
                led[15:8] <= jedec_id[23:16];
            else
                led[15:8] <= {4'd0, result};
        end
    end

endmodule
