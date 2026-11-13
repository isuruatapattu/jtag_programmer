`timescale 1ns / 1ps

// AXI4-Lite protocol checker for axi_gpio_jtag.
//
// Every assertion is named after the spec ID it checks
// (doc/axi_gpio_jtag_spec.md) and prints "ASSERT_FAIL <spec id> <text>".
// scripts/summarize.tcl counts those lines per ID. fail_count is read by the
// testbench to fail the test that was running.
//
// The counters below count handshakes since the last reset. A write is
// complete when both its AW and W handshakes have happened; "pairs" is the
// number of complete writes.

module axi_lite_checker (
    input logic        aclk,
    input logic        aresetn,
    input logic        awvalid,
    input logic        awready,
    input logic        wvalid,
    input logic        wready,
    input logic [1:0]  bresp,
    input logic        bvalid,
    input logic        bready,
    input logic        arvalid,
    input logic        arready,
    input logic [31:0] rdata,
    input logic [1:0]  rresp,
    input logic        rvalid,
    input logic        rready,
    input logic [3:0]  gpio_io_o
);

    int unsigned fail_count = 0;

    int unsigned aw_cnt = 0;
    int unsigned w_cnt  = 0;
    int unsigned b_cnt  = 0;
    int unsigned ar_cnt = 0;
    int unsigned r_cnt  = 0;
    bit          seen_reset = 1'b0;

    logic        aw_hs, w_hs, b_hs, ar_hs, r_hs;
    int unsigned pairs, pairs_next;
    logic        pair_now;

    function automatic void chk_fail(input string id, input string msg);
        fail_count++;
        $error("ASSERT_FAIL %s %s", id, msg);
    endfunction

    always_comb begin
        aw_hs      = awvalid && awready;
        w_hs       = wvalid  && wready;
        b_hs       = bvalid  && bready;
        ar_hs      = arvalid && arready;
        r_hs       = rvalid  && rready;
        pairs      = (aw_cnt < w_cnt) ? aw_cnt : w_cnt;
        pairs_next = ((aw_cnt + aw_hs) < (w_cnt + w_hs)) ? (aw_cnt + aw_hs)
                                                         : (w_cnt + w_hs);
        pair_now   = pairs_next > pairs;
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_cnt     <= 0;
            w_cnt      <= 0;
            b_cnt      <= 0;
            ar_cnt     <= 0;
            r_cnt      <= 0;
            seen_reset <= 1'b1;
        end else begin
            aw_cnt <= aw_cnt + aw_hs;
            w_cnt  <= w_cnt  + w_hs;
            b_cnt  <= b_cnt  + b_hs;
            ar_cnt <= ar_cnt + ar_hs;
            r_cnt  <= r_cnt  + r_hs;
        end
    end

    // ---------------------------------------------------------------- write

    a_axi_003: assert property (@(posedge aclk) disable iff (!aresetn)
        bvalid |-> pairs > b_cnt)
        else chk_fail("GPIO-AXI-003", "B response without a complete write");

    a_axi_004: assert property (@(posedge aclk) disable iff (!aresetn)
        bvalid && !bready |=> bvalid && $stable(bresp))
        else chk_fail("GPIO-AXI-004", "bvalid or bresp changed before the B handshake");

    a_axi_005_count: assert property (@(posedge aclk) disable iff (!aresetn)
        (aw_cnt - b_cnt) <= 1 && (w_cnt - b_cnt) <= 1)
        else chk_fail("GPIO-AXI-005", "more than one write in flight");

    a_axi_005_ready: assert property (@(posedge aclk) disable iff (!aresetn)
        bvalid |-> !awready && !wready)
        else chk_fail("GPIO-AXI-005", "awready or wready high while bvalid is high");

    a_axi_006_aw: assert property (@(posedge aclk) disable iff (!aresetn)
        $rose(awvalid) && aw_cnt == b_cnt && !bvalid |-> ##[0:2] awready)
        else chk_fail("GPIO-AXI-006", "awready not high within 2 cycles");

    a_axi_006_w: assert property (@(posedge aclk) disable iff (!aresetn)
        $rose(wvalid) && w_cnt == b_cnt && !bvalid |-> ##[0:2] wready)
        else chk_fail("GPIO-AXI-006", "wready not high within 2 cycles");

    a_axi_007: assert property (@(posedge aclk) disable iff (!aresetn)
        pair_now |=> ##[0:1] bvalid)
        else chk_fail("GPIO-AXI-007", "bvalid not high within 2 cycles of the last write handshake");

    // ----------------------------------------------------------------- read

    a_axi_010: assert property (@(posedge aclk) disable iff (!aresetn)
        rvalid |-> ar_cnt > r_cnt)
        else chk_fail("GPIO-AXI-010", "R response without an AR handshake");

    a_axi_011: assert property (@(posedge aclk) disable iff (!aresetn)
        rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp))
        else chk_fail("GPIO-AXI-011", "rvalid, rdata or rresp changed before the R handshake");

    a_axi_012_count: assert property (@(posedge aclk) disable iff (!aresetn)
        (ar_cnt - r_cnt) <= 1)
        else chk_fail("GPIO-AXI-012", "more than one read in flight");

    a_axi_012_ready: assert property (@(posedge aclk) disable iff (!aresetn)
        rvalid |-> !arready)
        else chk_fail("GPIO-AXI-012", "arready high while rvalid is high");

    a_axi_013: assert property (@(posedge aclk) disable iff (!aresetn)
        $rose(arvalid) && ar_cnt == r_cnt |-> ##[0:2] arready)
        else chk_fail("GPIO-AXI-013", "arready not high within 2 cycles");

    a_axi_014: assert property (@(posedge aclk) disable iff (!aresetn)
        ar_hs |=> ##[0:1] rvalid)
        else chk_fail("GPIO-AXI-014", "rvalid not high within 2 cycles of the AR handshake");

    // -------------------------------------------------------------- general

    a_axi_022_b: assert property (@(posedge aclk) disable iff (!aresetn)
        bvalid |-> bresp == 2'b00)
        else chk_fail("GPIO-AXI-022", "BRESP is not OKAY");

    a_axi_022_r: assert property (@(posedge aclk) disable iff (!aresetn)
        rvalid |-> rresp == 2'b00)
        else chk_fail("GPIO-AXI-022", "RRESP is not OKAY");

    // No disable here: this is the reset behaviour itself.
    a_rst_002: assert property (@(posedge aclk)
        !aresetn |=> !awready && !wready && !bvalid && !arready && !rvalid)
        else chk_fail("GPIO-RST-002", "handshake output high one cycle after reset was sampled");

    a_rst_003_known: assert property (@(posedge aclk)
        seen_reset && aresetn |-> !$isunknown({awready, wready, bvalid, bresp,
                                                arready, rvalid, rresp, rdata,
                                                gpio_io_o}))
        else chk_fail("GPIO-RST-003", "an output is X or Z after reset");

    // Covers show that the stall and same-cycle cases were really exercised.
    c_b_stall:    cover property (@(posedge aclk) disable iff (!aresetn) bvalid && !bready);
    c_r_stall:    cover property (@(posedge aclk) disable iff (!aresetn) rvalid && !rready);
    c_same_cycle: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && w_hs);

endmodule
