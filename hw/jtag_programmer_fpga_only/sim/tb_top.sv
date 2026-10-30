`timescale 1ns / 1ps
// End-to-end test: spi_flash_model -> top -> tap_model (or scripted TDO).
//
// Select the scenario with +SCEN=<n>:
//   0 idcode       TAP model, switches 0: file TCK (10 MHz, then 1 MHz)   OK
//   1 short_prog   TAP model, SW15 override 25 MHz; DONE must go high     OK
//   2 features     scripted TDO, file TCK 2.5 MHz, FIFO stall injection   OK
//   3 idcode       TAP model returns a wrong IDCODE                       TDO
//   4 bad CRC      pass 1 rejects, no JTAG activity                       CRC
//   5 bad CRC      SW14 skip check: played, CRC reported at the end       CRC
//   6 short_prog   BTNU pressed during pass 2 at 1 MHz                    ABORT
//   7 idcode       flash answers JEDEC FFFFFF                             FLID
//   8 bad magic    header error, no JTAG activity                         HDR
//   9 idcode       SW13 auto start, no button press                       OK
// Checks: final status, status LEDs, UART line, TCK/TMS/TDI trace against
// jbin_model.py, TCK low time per clock (half period from file/switches),
// target end state.
`ifndef VEC_DIR
`define VEC_DIR "build/sim/vectors"
`endif

module tb_top #(
    parameter int FIFO_XPM = 0
);

    localparam int UART_CPB = 8;
    localparam int MAXT     = 4096;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic       resetn = 1'b0;
    logic       btnc = 1'b0, btnu = 1'b0;
    logic [2:0] sw_div = 3'd0;
    logic       sw_auto = 1'b0, sw_skip = 1'b0, sw_ovr = 1'b0;
    wire [15:0] led;
    wire        uart_tx;
    wire        ja_tck, ja_tms, ja_tdi, ja_tdo;
    wire        qspi_csn, qspi_dq0, qspi_dq1, qspi_dq2, qspi_dq3;

    pullup (ja_tck);
    pullup (ja_tms);
    pullup (ja_tdi);
    pullup (ja_tdo);
    pullup (qspi_dq1);

    top #(
        .DEBOUNCE_CYCLES  (4),
        .FIFO_XPM         (FIFO_XPM),
        .TIMEOUT_CYCLES   (100_000),
        .UART_CLK_PER_BIT (UART_CPB)
    ) dut (
        .CLK100MHZ (clk), .CPU_RESETN (resetn), .BTNC (btnc), .BTNU (btnu),
        .SW_DIV (sw_div), .SW_AUTO (sw_auto), .SW_SKIP (sw_skip),
        .SW_OVR (sw_ovr), .LED (led), .UART_RXD_OUT (uart_tx),
        .JA_TCK (ja_tck), .JA_TMS (ja_tms), .JA_TDI (ja_tdi), .JA_TDO (ja_tdo),
        .QSPI_CSN (qspi_csn), .QSPI_DQ0 (qspi_dq0), .QSPI_DQ1 (qspi_dq1),
        .QSPI_DQ2 (qspi_dq2), .QSPI_DQ3 (qspi_dq3)
    );

    wire flash_sck = dut.u_flash_reader.u_sck.cclk;

    spi_flash_model #(.BASE(32'h0040_0000), .SIZE(4096)) u_flash (
        .sck (flash_sck), .cs_n (qspi_csn), .mosi (qspi_dq0), .miso (qspi_dq1)
    );

    // Target: TAP model, or a script that answers the expected TDO.
    wire  tap_tdo;
    logic scripted = 1'b0;
    logic script_tdo = 1'b1;

    tap_model #(.TDO_DELAY_NS(15.0)) u_tap (
        .tck (ja_tck), .tms (ja_tms), .tdi (ja_tdi), .tdo (tap_tdo)
    );

    assign ja_tdo = scripted ? script_tdo : tap_tdo;

    // ---------------- vectors ----------------
    logic [31:0] cases [0:255];
    logic [7:0]  trace [0:MAXT-1];
    logic [31:0] events [0:299];
    int ntck, nev;

    // ---------------- monitors ----------------
    int      n_rise = 0;
    int      n_fall = 0;
    int      errors = 0;
    logic [7:0] seen [0:MAXT-1];
    realtime t_fall;
    int      exp_sw_half;
    logic    check_trace = 1'b0;

    function automatic int file_half(input int k);
        int d;
        d = 5;
        for (int e = 0; e < nev; e++)
            if (events[3*e+1] == 2 && events[3*e] <= k)
                d = events[3*e+2];
        return d;
    endfunction

    always @(negedge ja_tck) if (resetn) begin
        t_fall = $realtime;
        if (scripted)
            script_tdo <= #(15.0) (n_fall < ntck && trace[n_fall][3]) ?
                                  trace[n_fall][2] : $urandom_range(1);
        n_fall = n_fall + 1;
    end

    always @(posedge ja_tck) if (resetn) begin : mon_rise
        int h;
        if (n_rise < MAXT)
            seen[n_rise] = {6'd0, ja_tdi, ja_tms};
        if (check_trace && n_rise < ntck) begin
            h = sw_ovr ? exp_sw_half :
                (file_half(n_rise) > exp_sw_half ? file_half(n_rise) : exp_sw_half);
            if ($realtime - t_fall < h * 10.0 - 0.01 ||
                $realtime - t_fall > h * 10.0 + 0.01) begin
                if (errors < 20)
                    $display("ERROR: TCK %0d low for %0.1f ns, expected %0d0 ns",
                             n_rise, $realtime - t_fall, h);
                errors = errors + 1;
            end
        end
        n_rise = n_rise + 1;
    end

    // ---------------- UART receiver ----------------
    string line = "";
    string last_line = "";
    int    n_lines = 0;

    initial begin
        logic [7:0] ch;
        forever begin
            @(negedge uart_tx);
            #(UART_CPB * 10 * 1.5);
            for (int b = 0; b < 8; b++) begin
                ch[b] = uart_tx;
                #(UART_CPB * 10);
            end
            if (ch == 8'h0A) begin
                $display("%0t ns UART: %s", $time / 1000, line);
                last_line = line;
                n_lines   = n_lines + 1;
                line      = "";
            end else if (ch != 8'h0D) begin
                line = {line, string'(ch)};
            end
        end
    end

    // ---------------- FIFO stall injection ----------------
    logic stalls = 1'b0;
    initial begin
        forever begin
            #($urandom_range(30000, 5000));
            if (stalls) begin
                force dut.fifo_room = 1'b0;
                #($urandom_range(40000, 1000));
                release dut.fifo_room;
            end
        end
    end

    // ---------------- scenario ----------------
    int scen;
    int ci;
    int exp_status;
    string exp_text;

    task automatic press_start();
        @(negedge clk);
        btnc = 1'b1;
        repeat (20) @(negedge clk);
        btnc = 1'b0;
    endtask

    task automatic press_abort();
        @(negedge clk);
        btnu = 1'b1;
        repeat (20) @(negedge clk);
        btnu = 1'b0;
    endtask

    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $display("ERROR: %s", msg);
            errors = errors + 1;
        end
    endtask

    initial begin
        string f;
        string vec;
        int    first_chk;
        if (!$value$plusargs("SCEN=%d", scen))
            scen = 0;
        if (!$value$plusargs("VEC=%s", vec))
            vec = `VEC_DIR;
        $readmemh({vec, "/cases.hex"}, cases);

        case (scen)
            0, 3, 7, 9: ci = 0;
            1, 6:       ci = 1;
            2:          ci = 2;
            4, 5:       ci = 7;
            default:    ci = 4;
        endcase
        ntck = cases[4 + 6*ci];
        nev  = cases[5 + 6*ci];
        f = $sformatf("%s/case_%0d.hex", vec, ci);
        u_flash.load(f, cases[1 + 6*ci]);
        if (ntck > 0) begin
            f = $sformatf("%s/case_%0d_trace.hex", vec, ci);
            $readmemh(f, trace, 0, ntck - 1);
        end
        if (nev > 0) begin
            f = $sformatf("%s/case_%0d_events.hex", vec, ci);
            $readmemh(f, events, 0, 3 * nev - 1);
        end

        exp_sw_half = 5;
        case (scen)
            0: begin exp_status = 1;  exp_text = "JTAG OK      "; end
            1: begin exp_status = 1;  exp_text = "JTAG OK      ";
                     sw_div = 3'd5; sw_ovr = 1'b1; exp_sw_half = 2; end
            2: begin exp_status = 1;  exp_text = "JTAG OK      ";
                     scripted = 1'b1; stalls = 1'b1; end
            3: begin exp_status = 2;  exp_text = "JTAG ERR TDO ";
                     u_tap.idcode = 32'h1363_1092; end
            4: begin exp_status = 6;  exp_text = "JTAG ERR CRC "; end
            5: begin exp_status = 6;  exp_text = "JTAG ERR CRC ";
                     sw_skip = 1'b1; end
            6: begin exp_status = 8;  exp_text = "JTAG ABORT   ";
                     sw_div = 3'd1; sw_ovr = 1'b1; exp_sw_half = 50; end
            7: begin exp_status = 10; exp_text = "JTAG ERR FLID";
                     u_flash.jedec_val = 24'hFFFFFF; end
            8: begin exp_status = 3;  exp_text = "JTAG ERR HDR "; end
            default: begin exp_status = 1; exp_text = "JTAG OK      ";
                     sw_auto = 1'b1; end
        endcase
        check_trace = (exp_status == 1) || (scen == 6);
        $display("scenario %0d: case %0d, %0d TCK, expect status %0d", scen, ci,
                 ntck, exp_status);

        repeat (10) @(posedge clk);
        resetn = 1'b1;

        wait (n_lines >= 1);
        if (scen == 7) begin
            check(last_line.substr(0, 12) == exp_text, "flash ID line");
            press_start();
            repeat (2000) @(posedge clk);
            check(led[5] && !led[0] && !led[1], "flash ID error LEDs");
            check(n_rise == 0, "JTAG activity after flash ID error");
        end else begin
            check(last_line.substr(0, 12) == "JTAG FLASH OK", "flash OK line");
            if (scen != 9) begin
                wait (led[0]);
                press_start();
            end
            if (scen == 6) begin
                wait (dut.u_engine.tck_count >= 300);
                press_abort();
            end
            wait (n_lines >= 2);
            repeat (100) @(posedge clk);

            check(dut.u_ctrl.result == exp_status,
                  $sformatf("status %0d, expected %0d", dut.u_ctrl.result,
                            exp_status));
            check(last_line.substr(0, 12) == exp_text,
                  $sformatf("UART line '%s'", last_line));
            check(led[0] && !led[1], "ready LED after the run");
            check(led[2] == (exp_status == 1), "OK LED");
            check(led[3] == (exp_status == 2), "TDO LED");
            check(led[4] == (exp_status == 3 || exp_status == 6), "error LED");
            check(led[6] == (exp_status == 8), "abort LED");
            check(dut.jtag_oe == 1'b0, "JTAG pins not released");

            if (exp_status == 1) begin
                check(n_rise == ntck, $sformatf("%0d TCK, expected %0d",
                                                n_rise, ntck));
                for (int i = 0; i < ntck && i < n_rise; i++)
                    if (seen[i] != (trace[i] & 8'h03)) begin
                        if (errors < 20)
                            $display("ERROR: TCK %0d TMS/TDI %b expected %b", i,
                                     seen[i][1:0], trace[i][1:0]);
                        errors = errors + 1;
                    end
                check(led[15:8] == 8'hFF, "progress LEDs");
            end
            if (scen == 0 || scen == 1 || scen == 9)
                check(u_tap.state == 4'd0, "target not in Test-Logic-Reset");
            if (scen == 1) begin
                check(u_tap.done == 1'b1, "target DONE not set");
                check(u_tap.cfg_bits == 360,
                      $sformatf("target got %0d CFG_IN bits", u_tap.cfg_bits));
            end
            if (scen == 3 || scen == 6) begin
                check(u_tap.state == 4'd0, "TAP not reset after the error");
                check(u_tap.resets >= 1, "no TAP reset");
            end
            if (scen == 3) begin
                first_chk = -1;
                for (int i = ntck - 1; i >= 0; i--)
                    if (trace[i][3])
                        first_chk = i;
                check(dut.u_ctrl.uart_info == 64'(first_chk),
                      $sformatf("TDO error at TCK %0d, expected %0d",
                                dut.u_ctrl.uart_info, first_chk));
            end
            if (scen == 4 || scen == 8)
                check(n_rise == 0, "JTAG activity although pass 1 failed");
            if (scen == 5)
                check(n_rise == 19, $sformatf("%0d TCK played, expected 19",
                                              n_rise));
        end

        if (errors == 0)
            $display("TEST PASSED: tb_top scenario %0d", scen);
        else
            $display("TEST FAILED: tb_top scenario %0d (%0d errors)", scen,
                     errors);
        $finish;
    end

    initial begin
        #30_000_000;
        $display("TEST FAILED: tb_top scenario %0d timeout", scen);
        $finish;
    end

endmodule
