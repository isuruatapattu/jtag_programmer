`timescale 1ns / 1ps
// FPGA-only JTAG programmer for the Nexys A7-100T.
//
// Plays the JBIN stream stored in the configuration flash at 0x00400000
// onto PMOD JA: JA1 = TCK, JA2 = TMS, JA3 = TDI, JA7 = TDO.
//
// Controls:
//   BTNC        start (pass 1 check, then pass 2 programming)
//   BTNU        abort
//   CPU_RESETN  reset
//   SW[2:0]     TCK limit, as a half period in 10 ns steps:
//               0: 5 (10 MHz)    1: 50 (1 MHz)     2: 10 (5 MHz)
//               3: 4 (12.5 MHz)  4: 3 (16.7 MHz)   5: 2 (25 MHz)
//               6: 500 (100 kHz) 7: 5000 (10 kHz)
//               The TCK used is the slower of this and the SVF FREQUENCY,
//               unless SW[15] is on, in which case the switches alone apply.
//   SW[13]      start once automatically after reset
//   SW[14]      skip the pass 1 check
//   SW[15]      switch TCK setting overrides the file
// LEDs: see top_ctrl.sv. UART (115200 8N1): one status line per result.
module top #(
    parameter int DEBOUNCE_CYCLES = 1_000_000,
    parameter int FIFO_XPM        = 1,
    parameter int TIMEOUT_CYCLES  = 50_000_000,
    parameter int UART_CLK_PER_BIT = 868
) (
    input  logic        CLK100MHZ,
    input  logic        CPU_RESETN,
    input  logic        BTNC,
    input  logic        BTNU,
    input  logic [2:0]  SW_DIV,
    input  logic        SW_AUTO,
    input  logic        SW_SKIP,
    input  logic        SW_OVR,
    output logic [15:0] LED,
    output logic        UART_RXD_OUT,

    output wire         JA_TCK,
    output wire         JA_TMS,
    output wire         JA_TDI,
    input  logic        JA_TDO,

    output logic        QSPI_CSN,
    output logic        QSPI_DQ0,
    input  logic        QSPI_DQ1,
    output logic        QSPI_DQ2,
    output logic        QSPI_DQ3
);

    logic clk;
    assign clk = CLK100MHZ;

    // ---------------- reset ----------------
    logic rst;

    reset_gen u_reset (
        .clk         (clk),
        .rst_n_async (CPU_RESETN),
        .rst         (rst)
    );

    // ---------------- inputs ----------------
    logic start_rise, abort_lvl, auto_lvl, skip_lvl, ovr_lvl;
    logic [2:0] div_lvl;

    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_db_c (
        .clk (clk), .rst (rst), .din (BTNC), .level (), .rise (start_rise));
    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_db_u (
        .clk (clk), .rst (rst), .din (BTNU), .level (abort_lvl), .rise ());
    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_db_a (
        .clk (clk), .rst (rst), .din (SW_AUTO), .level (auto_lvl), .rise ());
    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_db_s (
        .clk (clk), .rst (rst), .din (SW_SKIP), .level (skip_lvl), .rise ());
    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_db_o (
        .clk (clk), .rst (rst), .din (SW_OVR), .level (ovr_lvl), .rise ());
    for (genvar i = 0; i < 3; i++) begin : g_db_div
        debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_db (
            .clk (clk), .rst (rst), .din (SW_DIV[i]), .level (div_lvl[i]),
            .rise ());
    end

    // ---------------- flash reader + FIFO ----------------
    logic        id_done, id_ok;
    logic [23:0] jedec_id;
    logic        stream_en;
    logic [23:0] start_addr;
    logic        fifo_rst, fifo_wr, fifo_rd, fifo_empty, fifo_room;
    logic [7:0]  fifo_din, fifo_dout;

    spi_flash_reader #(.BLOCK_BYTES(256)) u_flash_reader (
        .clk        (clk),
        .rst        (rst),
        .flash_cs_n (QSPI_CSN),
        .flash_mosi (QSPI_DQ0),
        .flash_miso (QSPI_DQ1),
        .id_done    (id_done),
        .id_ok      (id_ok),
        .jedec_id   (jedec_id),
        .stream_en  (stream_en),
        .start_addr (start_addr),
        .fifo_wr    (fifo_wr),
        .fifo_din   (fifo_din),
        .fifo_room  (fifo_room)
    );

    // Write protect and hold/reset inactive.
    assign QSPI_DQ2 = 1'b1;
    assign QSPI_DQ3 = 1'b1;

    byte_fifo #(.DEPTH(4096), .ROOM(320), .USE_XPM(FIFO_XPM)) u_fifo (
        .clk      (clk),
        .rst      (rst || fifo_rst),
        .wr_en    (fifo_wr),
        .din      (fifo_din),
        .rd_en    (fifo_rd),
        .dout     (fifo_dout),
        .empty    (fifo_empty),
        .room     (fifo_room),
        .overflow ()
    );

    // ---------------- decoder + engine ----------------
    logic        dec_start, dec_dry, dec_abort, dec_busy, dec_done;
    logic [3:0]  dec_status;
    logic [63:0] dec_info;
    logic        hdr_valid;
    logic [31:0] payload_len;
    logic [63:0] total_tck, tck_issued;
    logic [15:0] div_file;
    logic        e_valid, e_ready, e_wait, e_tms, e_tdi, e_hold, e_chk, e_exp;
    logic [31:0] e_us;
    logic        e_cancel, e_idle, e_err;
    logic [63:0] e_err_tck, e_tck_count;
    logic        eng_clear;

    jbin_decoder #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_decoder (
        .clk (clk), .rst (rst),
        .start (dec_start), .dry (dec_dry), .abort (dec_abort),
        .busy (dec_busy), .done (dec_done), .status (dec_status),
        .err_info (dec_info),
        .hdr_valid (hdr_valid), .payload_len (payload_len),
        .total_tck (total_tck), .tck_issued (tck_issued),
        .div_file (div_file),
        .fifo_dout (fifo_dout), .fifo_empty (fifo_empty), .fifo_rd (fifo_rd),
        .e_valid (e_valid), .e_ready (e_ready), .e_wait (e_wait),
        .e_tms (e_tms), .e_tdi (e_tdi), .e_hold (e_hold), .e_chk (e_chk),
        .e_exp (e_exp), .e_us (e_us), .e_cancel (e_cancel),
        .e_idle (e_idle), .e_err (e_err), .e_err_tck (e_err_tck)
    );

    logic [15:0] half;

    tck_rate_selector u_tck_rate_selector (
        .clk         (clk),
        .div_sw_sel  (div_lvl),
        .override_en (ovr_lvl),
        .div_file    (div_file),
        .half        (half)
    );

    logic tck, tms, tdi;

    jtag_engine u_engine (
        .clk (clk), .rst (rst), .clear (eng_clear), .half (half),
        .item_valid (e_valid), .item_ready (e_ready), .item_wait (e_wait),
        .item_tms (e_tms), .item_tdi (e_tdi), .item_hold (e_hold),
        .item_chk (e_chk), .item_exp (e_exp), .item_us (e_us),
        .cancel_wait (e_cancel),
        .idle (e_idle), .tck_count (e_tck_count), .err (e_err),
        .err_tck (e_err_tck),
        .tck_o (tck), .tms_o (tms), .tdi_o (tdi), .tdo_i (JA_TDO)
    );

    // ---------------- control ----------------
    logic        jtag_oe;
    logic        uart_send;
    logic [3:0]  uart_code;
    logic [63:0] uart_info;

    top_ctrl u_ctrl (
        .clk (clk), .rst (rst),
        .start (start_rise), .abort (abort_lvl), .auto_start (auto_lvl),
        .skip_check (skip_lvl),
        .id_done (id_done), .id_ok (id_ok), .jedec_id (jedec_id),
        .stream_en (stream_en), .start_addr (start_addr),
        .fifo_rst (fifo_rst),
        .dec_start (dec_start), .dec_dry (dec_dry), .dec_abort (dec_abort),
        .dec_done (dec_done), .dec_status (dec_status), .dec_info (dec_info),
        .dec_hdr_valid (hdr_valid), .total_tck (total_tck),
        .tck_issued (tck_issued),
        .jtag_oe (jtag_oe), .eng_clear (eng_clear),
        .uart_send (uart_send), .uart_code (uart_code),
        .uart_info (uart_info),
        .led (LED)
    );

    // Pins are high impedance (pulled up) unless a play pass is running.
    assign JA_TCK = jtag_oe ? tck : 1'bz;
    assign JA_TMS = jtag_oe ? tms : 1'bz;
    assign JA_TDI = jtag_oe ? tdi : 1'bz;

    uart_tx_status #(.CLK_PER_BIT(UART_CLK_PER_BIT)) u_uart (
        .clk (clk), .rst (rst), .send (uart_send), .code (uart_code),
        .info (uart_info), .tx (UART_RXD_OUT), .busy ()
    );

endmodule
