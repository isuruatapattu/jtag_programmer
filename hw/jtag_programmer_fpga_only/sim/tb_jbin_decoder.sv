`timescale 1ns / 1ps
// Unit test for jbin_decoder (with crc32 and byte_fifo).
//
// Every case from sim/gen_vectors.py is run twice, as a dry pass and as a
// play pass. The bytes enter a small FIFO with random gaps; a stub engine
// accepts items with random delays and stays busy for a random time after
// each item. Checks:
//   * final status of both passes
//   * play pass of a valid stream: every clock item (TMS, TDI with holds
//     resolved, check and expected TDO) equals the jbin_model.py trace,
//     WAIT items come at the right TCK index with the right time, and the
//     divider from SET_DIV is in effect at the right TCK index
//   * a dry pass sends nothing to the engine and counts the same TCKs
//   * after a TDO mismatch or a format error during play, the last five
//     clocks have TMS = 1
`ifndef VEC_DIR
`define VEC_DIR "build/sim/vectors"
`endif

module tb_jbin_decoder #(
    parameter int FIFO_XPM = 0
);

    localparam int MAXB = 4096;
    localparam int MAXT = 4096;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    // FIFO feed.
    logic       fifo_rst = 1'b1;
    logic       wr_en = 1'b0;
    logic [7:0] din = 8'd0;
    logic       fifo_rd, fifo_empty, fifo_room, fifo_ovf;
    logic [7:0] fifo_dout;

    byte_fifo #(.DEPTH(64), .ROOM(4), .USE_XPM(FIFO_XPM)) u_fifo (
        .clk (clk), .rst (rst || fifo_rst), .wr_en (wr_en), .din (din),
        .rd_en (fifo_rd), .dout (fifo_dout), .empty (fifo_empty),
        .room (fifo_room), .overflow (fifo_ovf)
    );

    // DUT.
    logic        start = 1'b0, dry = 1'b0, abort = 1'b0;
    logic        busy, done;
    logic [3:0]  status;
    logic [63:0] err_info;
    logic        hdr_valid;
    logic [31:0] payload_len;
    logic [63:0] total_tck, tck_issued;
    logic [15:0] div_file;
    logic        e_valid, e_ready, e_wait, e_tms, e_tdi, e_hold, e_chk, e_exp;
    logic [31:0] e_us;
    logic        e_cancel, e_idle, e_err;
    logic [63:0] e_err_tck;

    jbin_decoder #(.TIMEOUT_CYCLES(3000)) u_dut (
        .clk (clk), .rst (rst), .start (start), .dry (dry), .abort (abort),
        .busy (busy), .done (done), .status (status), .err_info (err_info),
        .hdr_valid (hdr_valid), .payload_len (payload_len),
        .total_tck (total_tck), .tck_issued (tck_issued),
        .div_file (div_file),
        .fifo_dout (fifo_dout), .fifo_empty (fifo_empty), .fifo_rd (fifo_rd),
        .e_valid (e_valid), .e_ready (e_ready), .e_wait (e_wait),
        .e_tms (e_tms), .e_tdi (e_tdi), .e_hold (e_hold), .e_chk (e_chk),
        .e_exp (e_exp), .e_us (e_us), .e_cancel (e_cancel),
        .e_idle (e_idle), .e_err (e_err), .e_err_tck (e_err_tck)
    );

    int errors = 0;

    // Vectors.
    logic [31:0] cases [0:255];
    logic [7:0]  bytes_mem [0:MAXB-1];
    logic [7:0]  trace [0:MAXT-1];
    logic [31:0] events [0:299];
    int nbytes, exp_dry, exp_play, ntck, nev, idc_err;

    // Feeder.
    int  feed_idx;
    logic feed_on = 1'b0;
    always @(posedge clk) begin
        wr_en <= 1'b0;
        if (feed_on && feed_idx < nbytes && fifo_room &&
            $urandom_range(99) < 60) begin
            wr_en    <= 1'b1;
            din      <= bytes_mem[feed_idx];
            feed_idx <= feed_idx + 1;
        end
    end

    // Stub engine.
    int   busy_left;
    int   n_items;
    int   n_clk;
    int   ev_idx;
    logic tdi_pin;
    logic [7:0] tr [0:MAXT+15];
    int   cur_div;
    int   inject_err;

    logic rnd_ready = 1'b0;
    always @(posedge clk)
        rnd_ready <= ($urandom_range(99) < 50);
    assign e_ready = rnd_ready && busy_left == 0;
    assign e_idle  = (busy_left == 0);

    always @(posedge clk) begin
        if (busy_left > 0)
            busy_left <= busy_left - 1;
        if (e_valid && e_ready) begin
            busy_left <= $urandom_range(3);
            n_items   = n_items + 1;
            if (e_wait) begin
                if (ev_idx >= nev || events[3*ev_idx+1] != 1 ||
                    events[3*ev_idx] != n_clk || events[3*ev_idx+2] != e_us) begin
                    $display("ERROR: unexpected WAIT %0d us at TCK %0d", e_us, n_clk);
                    errors = errors + 1;
                end
                ev_idx = ev_idx + 1;
            end else begin
                while (ev_idx < nev && events[3*ev_idx+1] == 2 &&
                       events[3*ev_idx] <= n_clk) begin
                    cur_div = events[3*ev_idx+2];
                    ev_idx  = ev_idx + 1;
                end
                if (ntck > 0 && div_file != cur_div) begin
                    $display("ERROR: TCK %0d: div_file %0d expected %0d",
                             n_clk, div_file, cur_div);
                    errors = errors + 1;
                end
                if (!e_hold)
                    tdi_pin = e_tdi;
                tr[n_clk] = {4'd0, e_chk, e_exp, tdi_pin, e_tms};
                if (inject_err && e_chk && !e_err) begin
                    e_err     <= 1'b1;
                    e_err_tck <= 64'(n_clk);
                end
                if (n_clk < MAXT + 15)
                    n_clk = n_clk + 1;
            end
        end
    end

    logic saw_valid_dry;
    always @(posedge clk)
        if (busy && dry && e_valid)
            saw_valid_dry = 1'b1;

    task automatic run_pass(input int ci, input logic dry_mode,
                            input int exp_st);
        int exp_tck;
        fifo_rst = 1'b1;
        feed_on  = 1'b0;
        repeat (3) @(posedge clk);
        fifo_rst = 1'b0;
        feed_idx = 0;
        n_items  = 0;
        n_clk    = 0;
        ev_idx   = 0;
        tdi_pin  = 1'b0;
        cur_div  = 5;
        busy_left = 0;
        saw_valid_dry = 1'b0;
        e_err     = 1'b0;
        e_err_tck = 64'd0;
        inject_err = idc_err && !dry_mode;
        @(negedge clk);
        feed_on = 1'b1;
        dry     = dry_mode;
        start   = 1'b1;
        @(negedge clk);
        start   = 1'b0;
        wait (done);
        @(negedge clk);
        if (status != exp_st) begin
            $display("ERROR: case %0d %s: status %0d expected %0d (info %0d)",
                     ci, dry_mode ? "dry" : "play", status, exp_st, err_info);
            errors = errors + 1;
        end
        if (dry_mode && saw_valid_dry) begin
            $display("ERROR: case %0d: engine item during dry pass", ci);
            errors = errors + 1;
        end
        if (exp_st == 1) begin
            if (tck_issued != 64'(ntck)) begin
                $display("ERROR: case %0d: %0d TCK issued, %0d expected", ci,
                         tck_issued, ntck);
                errors = errors + 1;
            end
            if (!dry_mode) begin
                if (n_clk != ntck) begin
                    $display("ERROR: case %0d: engine saw %0d clocks, %0d expected",
                             ci, n_clk, ntck);
                    errors = errors + 1;
                end
                for (int i = 0; i < ntck && i < n_clk; i++) begin
                    if (tr[i] !== trace[i]) begin
                        if (errors < 20)
                            $display("ERROR: case %0d TCK %0d: got %02x expected %02x",
                                     ci, i, tr[i], trace[i]);
                        errors = errors + 1;
                    end
                end
                if (ev_idx != nev) begin
                    $display("ERROR: case %0d: %0d of %0d events seen", ci,
                             ev_idx, nev);
                    errors = errors + 1;
                end
            end
        end
        if (!dry_mode && exp_st != 1 && exp_st != 3 && exp_st != 6 &&
            exp_st != 7) begin
            if (n_clk < 5) begin
                $display("ERROR: case %0d: no TAP reset after error", ci);
                errors = errors + 1;
            end else begin
                for (int i = n_clk - 5; i < n_clk; i++)
                    if (tr[i][0] !== 1'b1) begin
                        $display("ERROR: case %0d: TCK %0d of the reset has TMS 0",
                                 ci, i);
                        errors = errors + 1;
                    end
            end
            if (exp_st == 2) begin
                exp_tck = -1;
                for (int i = ntck - 1; i >= 0; i--)
                    if (trace[i][3])
                        exp_tck = i;
                if (err_info != 64'(exp_tck)) begin
                    $display("ERROR: case %0d: TDO error index %0d expected %0d",
                             ci, err_info, exp_tck);
                    errors = errors + 1;
                end
            end
        end
        if (exp_st == 3 && n_clk != 0) begin
            $display("ERROR: case %0d: JTAG clocks after a header error", ci);
            errors = errors + 1;
        end
        $display("case %0d %-4s status %0d, %0d TCK, %0d items", ci,
                 dry_mode ? "dry" : "play", status, tck_issued, n_items);
    endtask

    initial begin
        string f;
        string vec;
        if (!$value$plusargs("VEC=%s", vec))
            vec = `VEC_DIR;
        $readmemh({vec, "/cases.hex"}, cases);
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        for (int ci = 0; ci < cases[0]; ci++) begin
            nbytes   = cases[1 + 6*ci];
            exp_dry  = cases[2 + 6*ci];
            exp_play = cases[3 + 6*ci];
            ntck     = cases[4 + 6*ci];
            nev      = cases[5 + 6*ci];
            idc_err  = cases[6 + 6*ci];
            f = $sformatf("%s/case_%0d.hex", vec, ci);
            $readmemh(f, bytes_mem, 0, nbytes - 1);
            f = $sformatf("%s/case_%0d_trace.hex", vec, ci);
            if (ntck > 0)
                $readmemh(f, trace, 0, ntck - 1);
            f = $sformatf("%s/case_%0d_events.hex", vec, ci);
            if (nev > 0)
                $readmemh(f, events, 0, 3 * nev - 1);
            run_pass(ci, 1'b1, exp_dry);
            run_pass(ci, 1'b0, exp_play);
        end
        if (fifo_ovf) begin
            $display("ERROR: FIFO overflow");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TEST PASSED: tb_jbin_decoder");
        else
            $display("TEST FAILED: tb_jbin_decoder (%0d errors)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("TEST FAILED: tb_jbin_decoder timeout");
        $finish;
    end

endmodule
