`timescale 1ns / 1ps
// Unit test for jtag_engine.
//
// A random item stream (clock items with random TMS/TDI/hold/check, random
// half periods and stalls, short waits) is played against a target that
// drives TDO TDO_DELAY_NS after each TCK falling edge. Checks:
//   * TCK low time = half * 10 ns, high time >= half * 10 ns, and exactly
//     that when items are back to back; TCK stays high during stalls
//   * TMS/TDI at each rising edge (TDI held when requested)
//   * waits keep TCK high for at least the requested time; cancel works
//   * TDO compare: no false mismatch at the worst delay, and the first
//     injected mismatch is reported with its exact TCK index
module tb_jtag_engine #(
    parameter real TDO_DELAY_NS = 35.0
);

    localparam int N = 600;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic        clear = 1'b0;
    logic [15:0] half = 16'd5;
    logic        item_valid = 1'b0;
    logic        item_ready;
    logic        item_wait = 1'b0, item_tms = 1'b0, item_tdi = 1'b0;
    logic        item_hold = 1'b0, item_chk = 1'b0, item_exp = 1'b0;
    logic [31:0] item_us = 32'd0;
    logic        cancel_wait = 1'b0;
    logic        idle, err;
    logic [63:0] tck_count, err_tck;
    logic        tck_o, tms_o, tdi_o;
    logic        tdo = 1'b0;

    jtag_engine u_dut (
        .clk (clk), .rst (rst), .clear (clear), .half (half),
        .item_valid (item_valid), .item_ready (item_ready),
        .item_wait (item_wait), .item_tms (item_tms), .item_tdi (item_tdi),
        .item_hold (item_hold), .item_chk (item_chk), .item_exp (item_exp),
        .item_us (item_us), .cancel_wait (cancel_wait),
        .idle (idle), .tck_count (tck_count), .err (err), .err_tck (err_tck),
        .tck_o (tck_o), .tms_o (tms_o), .tdi_o (tdi_o), .tdo_i (tdo)
    );

    int errors = 0;

    // Item list.
    logic        it_wait [0:N-1];
    logic        it_tms  [0:N-1];
    logic        it_tdi  [0:N-1];
    logic        it_hold [0:N-1];
    logic        it_chk  [0:N-1];
    logic        it_exp  [0:N-1];
    logic [15:0] it_half [0:N-1];
    logic [31:0] it_us   [0:N-1];
    // Per clock index.
    logic        c_tms  [0:N-1];
    logic        c_tdi  [0:N-1];
    logic [15:0] c_half [0:N-1];
    int          c_wait_before [0:N-1];
    logic        tdo_pat [0:N-1];
    int          n_clk;
    int          inject_at;

    task automatic gen(input int inject, input int max_half,
                       input int wait_pct);
        logic tdi_pin;
        int   c;
        int   wsum;
        tdi_pin = 1'b0;
        c = 0;
        wsum = 0;
        inject_at = -1;
        for (int i = 0; i < N; i++) begin
            it_wait[i] = ($urandom_range(99) < wait_pct);
            it_us[i]   = $urandom_range(3, 1);
            it_tms[i]  = $urandom_range(1);
            it_tdi[i]  = $urandom_range(1);
            it_hold[i] = $urandom_range(1);
            it_half[i] = $urandom_range(max_half, 2);
            if (it_wait[i]) begin
                wsum = wsum + it_us[i];
                it_chk[i] = 1'b0;
                it_exp[i] = 1'b0;
            end else begin
                tdo_pat[c] = $urandom_range(1);
                it_chk[i]  = $urandom_range(1);
                it_exp[i]  = it_chk[i] & tdo_pat[c];
                if (inject && inject_at < 0 && it_chk[i] && c > N / 3) begin
                    it_exp[i] = ~tdo_pat[c];
                    inject_at = c;
                end
                if (!it_hold[i])
                    tdi_pin = it_tdi[i];
                c_tms[c]  = it_tms[i];
                c_tdi[c]  = tdi_pin;
                c_half[c] = it_half[i];
                c_wait_before[c] = wsum;
                wsum = 0;
                c = c + 1;
            end
        end
        n_clk = c;
    endtask

    // Driver with random stalls.
    int  idx;
    int  stall_pct;
    logic drive_on = 1'b0;
    logic manual = 1'b0;

    always @(posedge clk) begin
        if (!manual && (!item_valid || item_ready)) begin
            if (drive_on && idx < N && $urandom_range(99) >= stall_pct) begin
                item_valid <= 1'b1;
                item_wait  <= it_wait[idx];
                item_tms   <= it_tms[idx];
                item_tdi   <= it_tdi[idx];
                item_hold  <= it_hold[idx];
                item_chk   <= it_chk[idx];
                item_exp   <= it_exp[idx];
                item_us    <= it_us[idx];
                half       <= it_half[idx];
                idx        <= idx + 1;
            end else begin
                item_valid <= 1'b0;
            end
        end
    end

    // Target: TDO follows each falling edge.
    int tgt_idx;
    always @(negedge tck_o) begin
        if (!rst && !clear) begin
            tdo <= #(TDO_DELAY_NS) tdo_pat[tgt_idx];
            tgt_idx = tgt_idx + 1;
        end
    end

    // Monitor.
    int      mon_idx;
    realtime t_fall, t_rise, t_prev_rise;
    logic    b2b;   // previous item was accepted back to back

    always @(negedge tck_o) begin
        t_fall = $realtime;
        if (mon_idx > 0) begin
            if (t_fall - t_rise < c_half[mon_idx-1] * 10.0 - 0.01) begin
                $display("ERROR: clock %0d high time %0.1f ns < %0d0 ns",
                         mon_idx - 1, t_fall - t_rise, c_half[mon_idx-1]);
                errors = errors + 1;
            end
            if (t_fall - t_rise < c_wait_before[mon_idx] * 1000.0) begin
                $display("ERROR: wait before clock %0d too short", mon_idx);
                errors = errors + 1;
            end
        end
    end

    always @(posedge tck_o) begin
        if (!rst && !clear && mon_idx < n_clk) begin
            t_rise = $realtime;
            if (t_rise - t_fall < c_half[mon_idx] * 10.0 - 0.01 ||
                t_rise - t_fall > c_half[mon_idx] * 10.0 + 0.01) begin
                $display("ERROR: clock %0d low time %0.1f ns, expected %0d0",
                         mon_idx, t_rise - t_fall, c_half[mon_idx]);
                errors = errors + 1;
            end
            if (tms_o !== c_tms[mon_idx] || tdi_o !== c_tdi[mon_idx]) begin
                $display("ERROR: clock %0d TMS/TDI %b%b expected %b%b", mon_idx,
                         tms_o, tdi_o, c_tms[mon_idx], c_tdi[mon_idx]);
                errors = errors + 1;
            end
            mon_idx = mon_idx + 1;
        end
    end

    task automatic run(input int inject, input int max_half, input int wait_pct,
                       input int stall);
        drive_on = 1'b0;
        @(posedge clk);
        clear <= 1'b1;
        @(posedge clk);
        clear <= 1'b0;
        gen(inject, max_half, wait_pct);
        idx       = 0;
        tgt_idx   = 0;
        mon_idx   = 0;
        stall_pct = stall;
        @(posedge clk);
        drive_on = 1'b1;
        wait (idx == N);
        @(posedge clk);
        @(posedge clk);
        wait (idle && !item_valid);
        if (mon_idx != n_clk || tck_count != 64'(n_clk)) begin
            $display("ERROR: %0d clocks seen, %0d counted, %0d expected",
                     mon_idx, tck_count, n_clk);
            errors = errors + 1;
        end
        if (inject) begin
            if (!err || err_tck != 64'(inject_at)) begin
                $display("ERROR: mismatch injected at %0d: err=%b err_tck=%0d",
                         inject_at, err, err_tck);
                errors = errors + 1;
            end
        end else if (err) begin
            $display("ERROR: false TDO mismatch at TCK %0d", err_tck);
            errors = errors + 1;
        end
        $display("run: inject=%0d max_half=%0d waits=%0d%% stalls=%0d%%: %0d clocks, err=%b @%0d",
                 inject, max_half, wait_pct, stall, n_clk, err, err_tck);
    endtask

    initial begin
        idx = 0; tgt_idx = 0; mon_idx = 0; n_clk = 0; stall_pct = 0;
        t_fall = 0; t_rise = 0;
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        if (tck_o !== 1'b1 || tms_o !== 1'b1 || tdi_o !== 1'b0) begin
            $display("ERROR: reset pin state TCK/TMS/TDI = %b%b%b", tck_o,
                     tms_o, tdi_o);
            errors = errors + 1;
        end

        // Fastest TCK back to back, worst-case TDO delay.
        for (int i = 0; i < N; i++) it_half[i] = 2;
        run(0, 2, 0, 0);
        run(1, 2, 0, 0);
        // Random half periods, stalls and waits.
        run(0, 9, 2, 30);
        run(1, 9, 2, 30);
        run(0, 3, 0, 70);

        // Cancel a long wait.
        drive_on = 1'b0;
        manual   = 1'b1;
        @(posedge clk);
        item_valid <= 1'b1;
        item_wait  <= 1'b1;
        item_us    <= 32'd100000;
        @(posedge clk);
        while (!item_ready) @(posedge clk);
        item_valid <= 1'b0;
        #2000;
        if (idle) begin
            $display("ERROR: engine idle during a wait");
            errors = errors + 1;
        end
        @(negedge clk);
        cancel_wait = 1'b1;
        @(negedge clk);
        cancel_wait = 1'b0;
        repeat (3) @(posedge clk);
        if (!idle) begin
            $display("ERROR: cancel_wait did not end the wait (state %0d, valid %b)",
                     u_dut.state, item_valid);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST PASSED: tb_jtag_engine");
        else
            $display("TEST FAILED: tb_jtag_engine (%0d errors)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("TEST FAILED: tb_jtag_engine timeout");
        $finish;
    end

endmodule
