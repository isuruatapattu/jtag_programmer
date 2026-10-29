`timescale 1ns / 1ps
// JBIN v1 decoder (see doc/jbin_format.md).
//
// Reads the stream from a first-word-fall-through byte FIFO and turns it
// into work items for jtag_engine. It applies the same checks as
// tools/jbin_model.py.
//
// `start` begins a pass. With `dry` = 1 no item reaches the engine (every
// item is accepted at once), which checks the whole stream without JTAG
// activity. With `dry` = 0 the stream is played.
//
// After every opcode the decoder waits until the engine is idle and then
// looks at the sticky TDO mismatch flag and the abort request. On a TDO
// mismatch, abort, or any error during play, it clocks five TMS = 1 cycles
// (Test-Logic-Reset) before reporting. In a dry pass a format error is
// reported only after the remaining payload has been read: if the payload
// CRC is wrong, the CRC error is reported instead, because a corrupt stream
// explains the format error.
module jbin_decoder #(
    parameter logic [31:0] MAX_PAYLOAD    = 32'h00BF_FFE0,
    parameter int          TIMEOUT_CYCLES = 50_000_000
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic        dry,
    input  logic        abort,
    output logic        busy,
    output logic        done,
    output logic [3:0]  status,
    output logic [63:0] err_info,

    output logic        hdr_valid,
    output logic [31:0] payload_len,
    output logic [63:0] total_tck,
    output logic [63:0] tck_issued,
    output logic [15:0] div_file,

    input  logic [7:0]  fifo_dout,
    input  logic        fifo_empty,
    output logic        fifo_rd,

    output logic        e_valid,
    input  logic        e_ready,
    output logic        e_wait,
    output logic        e_tms,
    output logic        e_tdi,
    output logic        e_hold,
    output logic        e_chk,
    output logic        e_exp,
    output logic [31:0] e_us,
    output logic        e_cancel,
    input  logic        e_idle,
    input  logic        e_err,
    input  logic [63:0] e_err_tck
);

    // Status codes, shared with top_ctrl and uart_tx_status.
    localparam logic [3:0] ST_NONE    = 4'd0;
    localparam logic [3:0] ST_OK      = 4'd1;
    localparam logic [3:0] ST_TDO     = 4'd2;
    localparam logic [3:0] ST_HEADER  = 4'd3;
    localparam logic [3:0] ST_OPCODE  = 4'd4;
    localparam logic [3:0] ST_OVERRUN = 4'd5;
    localparam logic [3:0] ST_CRC     = 4'd6;
    localparam logic [3:0] ST_TCK     = 4'd7;
    localparam logic [3:0] ST_ABORT   = 4'd8;
    localparam logic [3:0] ST_ARG     = 4'd9;
    localparam logic [3:0] ST_TIMEOUT = 4'd11;

    localparam logic [7:0] OP_TMS     = 8'h01;
    localparam logic [7:0] OP_SHIFT   = 8'h02;
    localparam logic [7:0] OP_RUNCLK  = 8'h03;
    localparam logic [7:0] OP_WAIT_US = 8'h04;
    localparam logic [7:0] OP_SET_DIV = 8'h05;
    localparam logic [7:0] OP_TRST    = 8'h06;
    localparam logic [7:0] OP_END     = 8'hFF;

    typedef enum logic [4:0] {
        D_IDLE,
        D_HDR,
        D_HCHK,
        D_OP,
        D_ARG,
        D_EXEC,
        D_TMS,
        D_SHIFT,
        D_GRP,
        D_GBITS,
        D_RUN,
        D_WAITI,
        D_SYNC,
        D_FIN,
        D_DRAIN,
        D_RESET,
        D_RDRAIN
    } state_t;

    state_t       state;
    logic         dry_q;
    logic         abort_q;
    logic [255:0] hdr;
    logic [4:0]   hdr_idx;
    logic [31:0]  byte_cnt;
    logic [7:0]   op;
    logic [39:0]  arg;
    logic [2:0]   arg_idx;
    logic [2:0]   arg_len;
    logic [31:0]  bi;
    logic [31:0]  bn;
    logic         last_tms;
    logic [7:0]   g_tdi;
    logic [7:0]   g_tdo;
    logic [7:0]   g_msk;
    logic [1:0]   g_idx;
    logic [2:0]   rst_cnt;
    logic [3:0]   pend;
    logic [31:0]  wd;

    logic [31:0] hdr_magic, hdr_plen, hdr_pcrc, hdr_resv, hdr_hcrc;
    logic [15:0] hdr_ver, hdr_flags;
    logic [63:0] hdr_ttck;
    logic [31:0] payload_crc;

    assign hdr_magic = hdr[31:0];
    assign hdr_ver   = hdr[47:32];
    assign hdr_flags = hdr[63:48];
    assign hdr_plen  = hdr[95:64];
    assign hdr_pcrc  = hdr[127:96];
    assign hdr_ttck  = hdr[191:128];
    assign hdr_resv  = hdr[223:192];
    assign hdr_hcrc  = hdr[255:224];

    // CRC: header bytes 0..27, then the payload.
    logic        crc_init;
    logic        crc_en;
    logic [31:0] crc;

    crc32 u_crc (
        .clk  (clk),
        .init (crc_init),
        .en   (crc_en),
        .data (fifo_dout),
        .crc  (crc)
    );

    // ------------------------------------------------------------------
    // Combinational part: FIFO reads, engine items.
    // ------------------------------------------------------------------
    logic pay_left;     // payload bytes remain
    logic want_pay;     // state needs a payload byte this cycle
    logic byte_ok;      // that byte is available
    logic item_v;       // an item is offered
    logic xfer;         // item accepted (engine, or at once when dry)
    logic consume;      // payload byte popped this cycle
    logic last_bit;

    assign pay_left = (byte_cnt != payload_len);
    assign last_bit = (bi == bn - 32'd1);

    always_comb begin
        want_pay = 1'b0;
        case (state)
            D_OP, D_ARG, D_TMS, D_SHIFT, D_GRP, D_DRAIN: want_pay = !abort_q;
            default: ;
        endcase
    end
    assign byte_ok = want_pay && pay_left && !fifo_empty;

    always_comb begin
        item_v = 1'b0;
        e_wait = 1'b0;
        e_tms  = 1'b0;
        e_tdi  = 1'b0;
        e_hold = 1'b1;
        e_chk  = 1'b0;
        e_exp  = 1'b0;
        e_us   = arg[31:0];
        case (state)
            D_TMS: begin
                item_v = byte_ok;
                e_tms  = fifo_dout[bi[2:0]];
            end
            D_SHIFT: begin
                item_v = byte_ok;
                e_hold = 1'b0;
                e_tdi  = fifo_dout[bi[2:0]];
                e_tms  = last_tms && last_bit;
            end
            D_GBITS: begin
                item_v = !abort_q;
                e_hold = 1'b0;
                e_tdi  = g_tdi[bi[2:0]];
                e_chk  = g_msk[bi[2:0]];
                e_exp  = g_msk[bi[2:0]] & g_tdo[bi[2:0]];
                e_tms  = last_tms && last_bit;
            end
            D_RUN: begin
                item_v = !abort_q;
            end
            D_WAITI: begin
                item_v = !abort_q;
                e_wait = 1'b1;
            end
            D_RESET: begin
                item_v = 1'b1;
                e_tms  = 1'b1;
            end
            default: ;
        endcase
    end

    assign e_valid  = item_v && !dry_q;
    assign xfer     = item_v && (dry_q || e_ready);
    assign e_cancel = abort_q;

    always_comb begin
        consume = 1'b0;
        case (state)
            D_OP, D_ARG, D_GRP, D_DRAIN: consume = byte_ok;
            D_TMS, D_SHIFT: consume = xfer && ((bi[2:0] == 3'd7) || last_bit);
            default: ;
        endcase
    end

    assign fifo_rd  = consume || ((state == D_HDR) && !fifo_empty && !abort_q);
    assign crc_init = (state == D_IDLE) || (state == D_HCHK);
    assign crc_en   = consume ||
                      ((state == D_HDR) && !fifo_empty && !abort_q &&
                       (hdr_idx < 5'd28));

    // ------------------------------------------------------------------
    // Sequential part.
    // ------------------------------------------------------------------
    logic xfer_clk;
    assign xfer_clk = xfer && !e_wait;

    // Error entry: in a dry pass, drain the payload for the CRC verdict;
    // during play, return the TAP to Test-Logic-Reset first.
    task automatic fail_pass(input logic [3:0] code);
        pend <= code;
        if (dry_q)
            state <= D_DRAIN;
        else
            state <= D_RESET;
    endtask

    task automatic finish_pass(input logic [3:0] code, input logic [63:0] info);
        status   <= code;
        err_info <= info;
        done     <= 1'b1;
        busy     <= 1'b0;
        state    <= D_IDLE;
    endtask

    logic waiting_byte;
    assign waiting_byte = (want_pay && pay_left && fifo_empty) ||
                          ((state == D_HDR) && fifo_empty);

    always_ff @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            state       <= D_IDLE;
            busy        <= 1'b0;
            status      <= ST_NONE;
            err_info    <= 64'd0;
            dry_q       <= 1'b0;
            abort_q     <= 1'b0;
            hdr         <= 256'd0;
            hdr_idx     <= 5'd0;
            hdr_valid   <= 1'b0;
            payload_len <= 32'd0;
            payload_crc <= 32'd0;
            total_tck   <= 64'd0;
            byte_cnt    <= 32'd0;
            tck_issued  <= 64'd0;
            div_file    <= 16'd5;
            op          <= 8'd0;
            arg         <= 40'd0;
            arg_idx     <= 3'd0;
            arg_len     <= 3'd0;
            bi          <= 32'd0;
            bn          <= 32'd0;
            last_tms    <= 1'b0;
            g_tdi       <= 8'd0;
            g_tdo       <= 8'd0;
            g_msk       <= 8'd0;
            g_idx       <= 2'd0;
            rst_cnt     <= 3'd0;
            pend        <= ST_NONE;
            wd          <= 32'd0;
        end else begin
            if (abort && busy)
                abort_q <= 1'b1;

            if (consume)
                byte_cnt <= byte_cnt + 32'd1;
            if (xfer_clk)
                tck_issued <= tck_issued + 64'd1;

            if (waiting_byte)
                wd <= wd + 32'd1;
            else
                wd <= 32'd0;

            case (state)
                D_IDLE: begin
                    if (start) begin
                        busy        <= 1'b1;
                        status      <= ST_NONE;
                        err_info    <= 64'd0;
                        dry_q       <= dry;
                        abort_q     <= 1'b0;
                        hdr_idx     <= 5'd0;
                        hdr_valid   <= 1'b0;
                        payload_len <= 32'd0;
                        total_tck   <= 64'd0;
                        byte_cnt    <= 32'd0;
                        tck_issued  <= 64'd0;
                        div_file    <= 16'd5;
                        pend        <= ST_NONE;
                        wd          <= 32'd0;
                        state       <= D_HDR;
                    end
                end

                D_HDR: begin
                    if (!fifo_empty && !abort_q) begin
                        hdr     <= {fifo_dout, hdr[255:8]};
                        hdr_idx <= hdr_idx + 5'd1;
                        if (hdr_idx == 5'd31)
                            state <= D_HCHK;
                    end
                end

                D_HCHK: begin
                    if (hdr_magic != 32'h4E49_424A || hdr_ver != 16'd1 ||
                        hdr_flags != 16'd0 || hdr_resv != 32'd0 ||
                        hdr_hcrc != crc || hdr_plen == 32'd0 ||
                        hdr_plen > MAX_PAYLOAD) begin
                        finish_pass(ST_HEADER, 64'd0);
                    end else begin
                        payload_len <= hdr_plen;
                        payload_crc <= hdr_pcrc;
                        total_tck   <= hdr_ttck;
                        hdr_valid   <= 1'b1;
                        byte_cnt    <= 32'd0;
                        state       <= D_OP;
                    end
                end

                D_OP: begin
                    arg     <= 40'd0;
                    arg_idx <= 3'd0;
                    if (byte_ok) begin
                        op <= fifo_dout;
                        state <= D_ARG;
                        case (fifo_dout)
                            OP_TMS:     arg_len <= 3'd1;
                            OP_SHIFT:   arg_len <= 3'd5;
                            OP_RUNCLK:  arg_len <= 3'd4;
                            OP_WAIT_US: arg_len <= 3'd4;
                            OP_SET_DIV: arg_len <= 3'd2;
                            OP_TRST:    arg_len <= 3'd1;
                            OP_END: begin
                                if (byte_cnt + 32'd1 == payload_len)
                                    state <= D_FIN;
                                else
                                    fail_pass(ST_OPCODE);
                            end
                            default: fail_pass(ST_OPCODE);
                        endcase
                    end else if (want_pay && !pay_left) begin
                        fail_pass(ST_OVERRUN);
                    end
                end

                D_ARG: begin
                    if (byte_ok) begin
                        arg[8*arg_idx +: 8] <= fifo_dout;
                        arg_idx <= arg_idx + 3'd1;
                        if (arg_idx + 3'd1 == arg_len)
                            state <= D_EXEC;
                    end else if (want_pay && !pay_left) begin
                        fail_pass(ST_OVERRUN);
                    end
                end

                D_EXEC: begin
                    bi       <= 32'd0;
                    g_idx    <= 2'd0;
                    last_tms <= arg[32];
                    state    <= D_SYNC;
                    case (op)
                        OP_TMS: begin
                            bn <= {24'd0, arg[7:0]};
                            if (arg[7:0] == 8'd0)
                                fail_pass(ST_ARG);
                            else
                                state <= D_TMS;
                        end
                        OP_SHIFT: begin
                            bn <= arg[31:0];
                            if (arg[31:0] == 32'd0 || arg[39:34] != 6'd0)
                                fail_pass(ST_ARG);
                            else if (arg[33])
                                state <= D_GRP;
                            else
                                state <= D_SHIFT;
                        end
                        OP_RUNCLK: begin
                            bn <= arg[31:0];
                            if (arg[31:0] != 32'd0)
                                state <= D_RUN;
                        end
                        OP_WAIT_US: begin
                            if (arg[31:0] != 32'd0 && !dry_q)
                                state <= D_WAITI;
                        end
                        OP_SET_DIV: begin
                            if (arg[15:0] < 16'd2)
                                fail_pass(ST_ARG);
                            else
                                div_file <= arg[15:0];
                        end
                        default: ;
                    endcase
                end

                D_TMS, D_SHIFT, D_RUN: begin
                    if (xfer) begin
                        bi <= bi + 32'd1;
                        if (last_bit)
                            state <= D_SYNC;
                    end else if (want_pay && !pay_left) begin
                        fail_pass(ST_OVERRUN);
                    end
                end

                D_GRP: begin
                    if (byte_ok) begin
                        case (g_idx)
                            2'd0:    g_tdi <= fifo_dout;
                            2'd1:    g_tdo <= fifo_dout;
                            default: g_msk <= fifo_dout;
                        endcase
                        g_idx <= g_idx + 2'd1;
                        if (g_idx == 2'd2) begin
                            g_idx <= 2'd0;
                            state <= D_GBITS;
                        end
                    end else if (want_pay && !pay_left) begin
                        fail_pass(ST_OVERRUN);
                    end
                end

                D_GBITS: begin
                    if (xfer) begin
                        bi <= bi + 32'd1;
                        if (last_bit)
                            state <= D_SYNC;
                        else if (bi[2:0] == 3'd7)
                            state <= D_GRP;
                    end
                end

                D_WAITI: begin
                    if (xfer)
                        state <= D_SYNC;
                end

                D_SYNC: begin
                    if (dry_q || e_idle) begin
                        if (abort_q) begin
                            if (dry_q)
                                finish_pass(ST_ABORT, tck_issued);
                            else begin
                                pend  <= ST_ABORT;
                                state <= D_RESET;
                            end
                        end else if (!dry_q && e_err) begin
                            pend  <= ST_TDO;
                            state <= D_RESET;
                        end else begin
                            state <= D_OP;
                        end
                    end
                end

                D_FIN: begin
                    if (dry_q || e_idle) begin
                        if (!dry_q && e_err) begin
                            pend  <= ST_TDO;
                            state <= D_RESET;
                        end else if (crc != payload_crc)
                            finish_pass(ST_CRC, {32'd0, crc});
                        else if (tck_issued != total_tck)
                            finish_pass(ST_TCK, tck_issued);
                        else
                            finish_pass(ST_OK, tck_issued);
                    end
                end

                // Dry pass only: read the rest of the payload for the CRC.
                D_DRAIN: begin
                    if (!pay_left) begin
                        if (crc != payload_crc)
                            finish_pass(ST_CRC, {32'd0, crc});
                        else
                            finish_pass(pend, {32'd0, byte_cnt});
                    end
                end

                D_RESET: begin
                    if (xfer) begin
                        rst_cnt <= rst_cnt + 3'd1;
                        if (rst_cnt == 3'd4) begin
                            rst_cnt <= 3'd0;
                            state   <= D_RDRAIN;
                        end
                    end
                end

                D_RDRAIN: begin
                    if (e_idle) begin
                        if (pend == ST_TDO)
                            finish_pass(pend, e_err_tck);
                        else if (pend == ST_ABORT)
                            finish_pass(pend, tck_issued);
                        else
                            finish_pass(pend, {32'd0, byte_cnt});
                    end
                end

                default: state <= D_IDLE;
            endcase

            // Abort while waiting for data or issuing items: stop at once.
            if (abort_q) begin
                case (state)
                    D_HDR, D_OP, D_ARG, D_EXEC, D_TMS, D_SHIFT, D_GRP,
                    D_GBITS, D_RUN, D_WAITI, D_DRAIN: state <= D_SYNC;
                    default: ;
                endcase
            end

            // Stream watchdog.
            if (waiting_byte && wd == 32'(TIMEOUT_CYCLES)) begin
                if (dry_q || state == D_HDR)
                    finish_pass(ST_TIMEOUT, {32'd0, byte_cnt});
                else
                    fail_pass(ST_TIMEOUT);
            end
        end
    end

endmodule
