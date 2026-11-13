`timescale 1ns / 1ps

// Minimal IEEE 1149.1 TAP: 6-bit IR, IDCODE (0x09, the reset instruction)
// and BYPASS for every other instruction.
module tap_model #(
    parameter logic [31:0] IDCODE = 32'h03631093
) (
    input  logic tck,
    input  logic tms,
    input  logic tdi,
    output logic tdo
);

    typedef enum logic [3:0] {
        TLR, RTI, SDS, CDR, SDR, E1D, PDR, E2D, UDR,
        SIS, CIR, SIR, E1I, PIR, E2I, UIR
    } tap_t;

    tap_t        st = TLR;
    logic [5:0]  ir = 6'h09;
    logic [5:0]  ir_sr = '0;
    logic [31:0] dr_sr = '0;
    logic        byp_sr = 1'b0;

    function automatic tap_t next_state(tap_t s, logic m);
        case (s)
            TLR: return m ? TLR : RTI;
            RTI: return m ? SDS : RTI;
            SDS: return m ? SIS : CDR;
            CDR: return m ? E1D : SDR;
            SDR: return m ? E1D : SDR;
            E1D: return m ? UDR : PDR;
            PDR: return m ? E2D : PDR;
            E2D: return m ? UDR : SDR;
            UDR: return m ? SDS : RTI;
            SIS: return m ? TLR : CIR;
            CIR: return m ? E1I : SIR;
            SIR: return m ? E1I : SIR;
            E1I: return m ? UIR : PIR;
            PIR: return m ? E2I : PIR;
            E2I: return m ? UIR : SIR;
            UIR: return m ? SDS : RTI;
            default: return TLR;
        endcase
    endfunction

    initial tdo = 1'b1;

    always @(posedge tck) begin
        case (st)
            CIR: ir_sr <= 6'b000001;
            SIR: ir_sr <= {tdi, ir_sr[5:1]};
            CDR: begin
                if (ir == 6'h09) dr_sr <= IDCODE;
                else             byp_sr <= 1'b0;
            end
            SDR: begin
                if (ir == 6'h09) dr_sr <= {tdi, dr_sr[31:1]};
                else             byp_sr <= tdi;
            end
            default: ;
        endcase
        st <= next_state(st, tms);
    end

    always @(negedge tck) begin
        if (st == TLR) ir <= 6'h09;
        if (st == UIR) ir <= ir_sr;
        case (st)
            SIR:     tdo <= ir_sr[0];
            SDR:     tdo <= (ir == 6'h09) ? dr_sr[0] : byp_sr;
            default: tdo <= 1'b1;
        endcase
    end

endmodule


module tb_jtag_shifter;

    localparam logic [7:0] A_CTRL   = 8'h00;
    localparam logic [7:0] A_STATUS = 8'h04;
    localparam logic [7:0] A_CLKDIV = 8'h08;
    localparam logic [7:0] A_CFG    = 8'h0C;
    localparam logic [7:0] A_DATA   = 8'h10;
    localparam logic [7:0] A_TDO    = 8'h14;
    localparam logic [7:0] A_CYCLES = 8'h18;
    localparam logic [7:0] A_ID     = 8'h1C;

    // Encodings of tap_model::tap_t
    localparam logic [31:0] TAP_RTI = 32'd1;
    localparam logic [31:0] TAP_SDR = 32'd4;

    localparam int ST_BUSY     = 0;
    localparam int ST_TX_FULL  = 1;
    localparam int ST_RX_EMPTY = 2;
    localparam int ST_TX_EMPTY = 3;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;

    logic [7:0]  awaddr = '0;
    logic        awvalid = 1'b0;
    logic        awready;
    logic [31:0] wdata = '0;
    logic [3:0]  wstrb = 4'hF;
    logic        wvalid = 1'b0;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready = 1'b0;
    logic [7:0]  araddr = '0;
    logic        arvalid = 1'b0;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready = 1'b0;

    logic [3:0]  gpio_bypass = 4'h0;
    logic [3:0]  jtag_o;
    logic        tap_tdo;
    logic        tdo_pin;

    int          errors = 0;

    // Pin activity seen by the target on each rising TCK edge.
    bit          mon_tms[$];
    bit          mon_tdi[$];
    realtime     t_rise;
    realtime     t_fall;
    realtime     high_ns;
    realtime     low_ns;

    always #5 clk = ~clk;

    jtag_shifter_top dut (
        .s_axi_aclk   (clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr (awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata  (wdata),
        .s_axi_wstrb  (wstrb),
        .s_axi_wvalid (wvalid),
        .s_axi_wready (wready),
        .s_axi_bresp  (bresp),
        .s_axi_bvalid (bvalid),
        .s_axi_bready (bready),
        .s_axi_araddr (araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata  (rdata),
        .s_axi_rresp  (rresp),
        .s_axi_rvalid (rvalid),
        .s_axi_rready (rready),
        .gpio_bypass_i(gpio_bypass),
        .jtag_i       ({3'b000, tdo_pin}),
        .jtag_o       (jtag_o)
    );

    tap_model u_tap (
        .tck(jtag_o[0]),
        .tms(jtag_o[1]),
        .tdi(jtag_o[2]),
        .tdo(tap_tdo)
    );

    // Target clock-to-out plus wire delay.
    assign #8 tdo_pin = tap_tdo;

    always @(posedge jtag_o[0]) begin
        mon_tms.push_back(jtag_o[1]);
        mon_tdi.push_back(jtag_o[2]);
        t_rise = $realtime;
        low_ns = t_rise - t_fall;
    end

    always @(negedge jtag_o[0]) begin
        t_fall  = $realtime;
        high_ns = t_fall - t_rise;
    end

    // ---------------- AXI4-Lite tasks ----------------
    // Inputs change on the falling clock edge. READY is a function of DUT
    // registers only, so a VALID && READY seen at a falling edge is the
    // handshake of the next rising edge.
    task automatic axi_write(input logic [7:0] a, input logic [31:0] d);
        logic aw_hs;
        logic w_hs;
        @(negedge clk);
        awaddr  = a;
        awvalid = 1'b1;
        wdata   = d;
        wvalid  = 1'b1;
        bready  = 1'b1;
        while (awvalid || wvalid) begin
            aw_hs = awvalid && awready;
            w_hs  = wvalid && wready;
            @(negedge clk);
            if (aw_hs) awvalid = 1'b0;
            if (w_hs)  wvalid  = 1'b0;
        end
        while (!bvalid) @(negedge clk);
        if (bresp != 2'b00) begin
            $error("BRESP %0b at 0x%02h", bresp, a);
            errors++;
        end
        @(negedge clk);
        bready = 1'b0;
    endtask

    task automatic axi_read(input logic [7:0] a, output logic [31:0] d);
        logic hs;
        @(negedge clk);
        araddr  = a;
        arvalid = 1'b1;
        rready  = 1'b1;
        forever begin
            hs = arready;
            @(negedge clk);
            if (hs) begin
                arvalid = 1'b0;
                break;
            end
        end
        while (!rvalid) @(negedge clk);
        d = rdata;
        if (rresp != 2'b00) begin
            $error("RRESP %0b at 0x%02h", rresp, a);
            errors++;
        end
        @(negedge clk);
        rready = 1'b0;
    endtask

    // ---------------- Driver helpers ----------------
    function automatic logic [31:0] cfg_word(int nbits, bit mode, bit tms_last,
                                             bit capture);
        return {21'd0, capture, tms_last, mode, 3'd0, 5'(nbits - 1)};
    endfunction

    task automatic push(int nbits, bit mode, bit tms_last, bit capture,
                        logic [31:0] data);
        axi_write(A_CFG, cfg_word(nbits, mode, tms_last, capture));
        axi_write(A_DATA, data);
    endtask

    task automatic wait_idle();
        logic [31:0] s;
        do begin
            axi_read(A_STATUS, s);
        end while (s[ST_BUSY]);
    endtask

    task automatic pop_tdo(output logic [31:0] d);
        logic [31:0] s;
        do begin
            axi_read(A_STATUS, s);
        end while (s[ST_RX_EMPTY]);
        axi_read(A_TDO, d);
    endtask

    task automatic check(string what, logic [31:0] got, logic [31:0] exp);
        if (got !== exp) begin
            $error("%s: got 0x%08h, expected 0x%08h", what, got, exp);
            errors++;
        end else begin
            $display("PASS %s = 0x%08h", what, got);
        end
    endtask

    task automatic check_tms(string what, bit exp[$]);
        if (mon_tms.size() != exp.size()) begin
            $error("%s: %0d TCK edges, expected %0d", what, mon_tms.size(),
                   exp.size());
            errors++;
            return;
        end
        foreach (exp[i]) begin
            if (mon_tms[i] != exp[i]) begin
                $error("%s: TMS bit %0d is %0b", what, i, mon_tms[i]);
                errors++;
                return;
            end
        end
        $display("PASS %s (%0d TMS bits)", what, exp.size());
    endtask

    task automatic tms_walk(int nbits, logic [31:0] bits);
        push(nbits, 1'b1, 1'b0, 1'b0, bits);
    endtask

    // ---------------- Tests ----------------
    logic [31:0] r;
    logic [31:0] w;
    bit          exp_tms[$];
    bit          sent[$];
    bit          got[$];
    int          nb[$];
    realtime     t0;
    int          k;
    int          n;

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ID and reset values
        axi_read(A_ID, r);
        check("ID", r, 32'h4A534831);
        axi_read(A_CLKDIV, r);
        check("CLKDIV reset", r, 32'd5);
        axi_read(A_CFG, r);
        check("CFG reset", r, 32'h0000001F);
        axi_read(A_STATUS, r);
        check("STATUS reset", r & 32'h1F, 32'h0000000C);
        axi_read(A_TDO, r);
        check("TDO read when empty", r, 32'd0);

        // Bypass: jtag_o follows axi_gpio_0 when ENGINE_EN = 0
        for (k = 0; k < 16; k++) begin
            @(negedge clk);
            gpio_bypass = 4'(k);
            repeat (2) @(negedge clk);
            check("bypass", {28'd0, jtag_o}, {28'd0, 4'(k)});
        end
        gpio_bypass = 4'h0;
        repeat (2) @(negedge clk);

        // Engine on, CLKDIV = 5: TCK high and low are 50 ns each
        axi_write(A_CTRL, 32'h3);
        axi_write(A_CTRL, 32'h1);
        mon_tms.delete();
        mon_tdi.delete();

        tms_walk(6, 32'b011111);
        wait_idle();
        exp_tms = '{1, 1, 1, 1, 1, 0};
        check_tms("TAP reset walk", exp_tms);
        check("TAP state RTI", {28'd0, u_tap.st}, TAP_RTI);
        check("TCK high ns", 32'(int'(high_ns)), 32'd50);
        check("TCK low ns", 32'(int'(low_ns)), 32'd50);

        axi_write(A_CLKDIV, 32'd2);

        // IR scan: load IDCODE (0x09) and capture the IR
        mon_tms.delete();
        mon_tdi.delete();
        tms_walk(4, 32'b0011);
        push(6, 1'b0, 1'b1, 1'b1, 32'h09);
        tms_walk(2, 32'b01);
        pop_tdo(r);
        check("IR capture", r, 32'h00000001);
        wait_idle();
        exp_tms = '{1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0};
        check_tms("IR scan TMS incl. TMS_LAST", exp_tms);

        // DR scan: read IDCODE
        tms_walk(3, 32'b001);
        push(32, 1'b0, 1'b1, 1'b1, 32'h0);
        tms_walk(2, 32'b01);
        pop_tdo(r);
        check("IDCODE", r, 32'h03631093);
        wait_idle();

        // Load BYPASS, enter Shift-DR and stay there
        tms_walk(4, 32'b0011);
        push(6, 1'b0, 1'b1, 1'b0, 32'h3F);
        tms_walk(2, 32'b01);
        tms_walk(3, 32'b001);
        wait_idle();
        check("TAP state Shift-DR", {28'd0, u_tap.st}, TAP_SDR);

        // Bit order, NBITS 1..32 and capture across words. In BYPASS the
        // target returns TDI delayed by one bit, after a captured 0.
        mon_tms.delete();
        mon_tdi.delete();
        sent.delete();
        got.delete();
        nb.delete();
        for (k = 1; k <= 32; k++) begin
            w = $urandom();
            push(k, 1'b0, 1'b0, 1'b1, w);
            nb.push_back(k);
            for (n = 0; n < k; n++) sent.push_back(w[n]);
        end
        foreach (nb[i]) begin
            pop_tdo(r);
            for (n = 0; n < nb[i]; n++) got.push_back(r[n]);
            if (nb[i] < 32 && (r >> nb[i]) != 0) begin
                $error("TDO word %0d has bits above NBITS", i);
                errors++;
            end
        end
        wait_idle();
        if (mon_tdi.size() != sent.size()) begin
            $error("TDI edges %0d, expected %0d", mon_tdi.size(), sent.size());
            errors++;
        end else begin
            foreach (sent[i]) begin
                if (mon_tdi[i] != sent[i]) begin
                    $error("TDI bit %0d wrong", i);
                    errors++;
                    break;
                end
                if (mon_tms[i] != 1'b0) begin
                    $error("TMS high at bit %0d", i);
                    errors++;
                    break;
                end
            end
            $display("PASS TDI bit order over %0d bits", sent.size());
        end
        if (got[0] != 1'b0) begin
            $error("first BYPASS bit not 0");
            errors++;
        end
        for (n = 1; n < got.size(); n++) begin
            if (got[n] != sent[n - 1]) begin
                $error("TDO loopback bit %0d wrong", n);
                errors++;
                break;
            end
        end
        $display("PASS TDO capture over %0d bits", got.size());

        // MODE 1 holds TDI
        mon_tms.delete();
        mon_tdi.delete();
        push(1, 1'b0, 1'b0, 1'b0, 32'h1);
        tms_walk(4, 32'b0000);
        wait_idle();
        check("TDI held in MODE 1", {27'd0, mon_tdi[1], mon_tdi[2],
                                    mon_tdi[3], mon_tdi[4]}, 32'hF);

        // TX FIFO full: one word in the engine plus 512 queued
        axi_write(A_CLKDIV, 32'd100);
        axi_write(A_CFG, cfg_word(32, 1'b0, 1'b0, 1'b0));
        for (k = 0; k < 513; k++) axi_write(A_DATA, k);
        axi_read(A_STATUS, r);
        check("TX_FULL", {31'd0, r[ST_TX_FULL]}, 32'd1);
        check("TX level saturated", {24'd0, r[15:8]}, 32'd255);
        t0 = $realtime;
        axi_write(A_DATA, 32'hDEADBEEF);
        if ($realtime - t0 < 1000.0) begin
            $error("DATA write did not stall on a full FIFO");
            errors++;
        end else begin
            $display("PASS DATA write stalled %0t ns", $realtime - t0);
        end
        axi_write(A_CTRL, 32'h3);
        axi_read(A_STATUS, r);
        check("FLUSH empties", r & 32'hF, 32'h0000000C);

        // Back to bypass
        axi_write(A_CTRL, 32'h0);
        @(negedge clk);
        gpio_bypass = 4'h5;
        repeat (2) @(negedge clk);
        check("bypass after engine", {28'd0, jtag_o}, 32'h5);

        axi_read(A_CYCLES, r);
        if (r == 0) begin
            $error("CYCLES not counting");
            errors++;
        end

        if (errors == 0) $display("TB RESULT: PASS");
        else             $display("TB RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #50ms;
        $display("TB RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
