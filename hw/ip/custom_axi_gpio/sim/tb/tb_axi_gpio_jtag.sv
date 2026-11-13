`timescale 1ns / 1ps

// Self-checking testbench for axi_gpio_jtag.
//
// The spec is doc/axi_gpio_jtag_spec.md and the test-to-requirement map is
// doc/traceability.md. The scoreboard (m_*) follows tools/gpio_reg_model.py
// rule for rule. t_random also replays vectors generated from that model.
//
// Plusargs
//   +TEST=<name>|all   test to run (default all)
//   +SEED=<n>          random seed (default 1)
//   +VEC=<file>        vector file for t_random (sim/vectors/random_seed<n>.txt)
//   +TIMEOUT_NS=<n>    per-test watchdog in ns (default 5000000)
//   +DUMP              write tb_axi_gpio_jtag.vcd
//
// Lines read by scripts/summarize.tcl
//   TEST_START <name>
//   TEST_RESULT <name> PASS|FAIL
//   ERROR <name> <message>
//   SIM_SUMMARY tests=<n> pass=<n> fail=<n> assert_fail=<n>

module tb_axi_gpio_jtag;

    localparam logic [8:0] A_DATA  = 9'h000;
    localparam logic [8:0] A_TRI   = 9'h004;
    localparam logic [8:0] A_DATA2 = 9'h008;
    localparam logic [8:0] A_TRI2  = 9'h00C;

    localparam int ORDER_RANDOM = -1;
    localparam int ORDER_SAME   = 0;
    localparam int ORDER_AW     = 1;
    localparam int ORDER_W      = 2;

    // ------------------------------------------------------------------
    // Clock, DUT, BFM and checker
    // ------------------------------------------------------------------
    logic aclk = 1'b0;
    always #5 aclk = ~aclk;

    wire  [3:0] gpio_io_o;
    logic [3:0] gpio2_io_i = 4'h0;

    axi_lite_if axi (.aclk(aclk), .gpio_io_o(gpio_io_o));

    axi_gpio_jtag dut (
        .s_axi_aclk    (aclk),
        .s_axi_aresetn (axi.aresetn),
        .s_axi_awaddr  (axi.awaddr),
        .s_axi_awvalid (axi.awvalid),
        .s_axi_awready (axi.awready),
        .s_axi_wdata   (axi.wdata),
        .s_axi_wstrb   (axi.wstrb),
        .s_axi_wvalid  (axi.wvalid),
        .s_axi_wready  (axi.wready),
        .s_axi_bresp   (axi.bresp),
        .s_axi_bvalid  (axi.bvalid),
        .s_axi_bready  (axi.bready),
        .s_axi_araddr  (axi.araddr),
        .s_axi_arvalid (axi.arvalid),
        .s_axi_arready (axi.arready),
        .s_axi_rdata   (axi.rdata),
        .s_axi_rresp   (axi.rresp),
        .s_axi_rvalid  (axi.rvalid),
        .s_axi_rready  (axi.rready),
        .gpio_io_o     (gpio_io_o),
        .gpio2_io_i    (gpio2_io_i)
    );

    axi_lite_checker u_chk (
        .aclk      (aclk),
        .aresetn   (axi.aresetn),
        .awvalid   (axi.awvalid),
        .awready   (axi.awready),
        .wvalid    (axi.wvalid),
        .wready    (axi.wready),
        .bresp     (axi.bresp),
        .bvalid    (axi.bvalid),
        .bready    (axi.bready),
        .arvalid   (axi.arvalid),
        .arready   (axi.arready),
        .rdata     (axi.rdata),
        .rresp     (axi.rresp),
        .rvalid    (axi.rvalid),
        .rready    (axi.rready),
        .gpio_io_o (gpio_io_o)
    );

    // ------------------------------------------------------------------
    // Test state
    // ------------------------------------------------------------------
    string           cur_test = "none";
    int unsigned     test_errors = 0;
    int unsigned     n_tests = 0;
    int unsigned     n_pass  = 0;
    int unsigned     n_fail  = 0;
    longint unsigned timeout_ns = 64'd5_000_000;

    // axi.edges when gpio2_io_i last changed (always between two edges)
    int unsigned pins_edge = 0;

    event ev_aw_hs, ev_w_hs, ev_bvalid, ev_rvalid;
    always @(posedge aclk) begin
        if (axi.awvalid && axi.awready) -> ev_aw_hs;
        if (axi.wvalid  && axi.wready)  -> ev_w_hs;
        if (axi.bvalid)                 -> ev_bvalid;
        if (axi.rvalid)                 -> ev_rvalid;
    end

    string test_names[] = '{
        "t_reset_values", "t_data_rw", "t_tri_rw", "t_data2_read",
        "t_upper_bits", "t_wstrb", "t_addr_low_bits", "t_unmapped",
        "t_aw_w_order", "t_backpressure", "t_concurrent_rw",
        "t_sync_latency", "t_reset_mid_txn", "t_random",
        "t_sw_configure", "t_sw_test_outputs", "t_sw_write_read_tdo",
        "t_sw_loopback", "t_sw_stream"
    };

    // ------------------------------------------------------------------
    // Scoreboard: the spec register model
    // ------------------------------------------------------------------
    logic [3:0] m_data = 4'h0;
    logic [3:0] m_tri  = 4'h0;
    logic [3:0] m_tri2 = 4'hF;

    function automatic void m_reset();
        m_data = 4'h0;
        m_tri  = 4'h0;
        m_tri2 = 4'hF;
    endfunction

    function automatic void m_write(input logic [8:0] a, input logic [31:0] d,
                                    input logic [3:0] s);
        if (s[0]) begin
            case (a[8:2])
                7'd0: m_data = d[3:0];
                7'd1: m_tri  = d[3:0];
                7'd3: m_tri2 = d[3:0];
                default: ;
            endcase
        end
    endfunction

    // DATA2 is only valid after the inputs are settled (checked by callers).
    function automatic logic [31:0] m_read(input logic [8:0] a);
        case (a[8:2])
            7'd0:    return {28'd0, m_data};
            7'd1:    return {28'd0, m_tri};
            7'd2:    return {28'd0, gpio2_io_i};
            7'd3:    return {28'd0, m_tri2};
            default: return 32'd0;
        endcase
    endfunction

    function automatic int kind_of(input logic [8:0] a);
        return (a[8:2] < 7'd4) ? int'(a[8:2]) : 4;
    endfunction

    function automatic logic [8:0] pick_rw_addr();
        case ($urandom_range(0, 2))
            0:       return A_DATA;
            1:       return A_TRI;
            default: return A_TRI2;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Functional coverage
    // ------------------------------------------------------------------
    covergroup cg_access with function sample(int kind, bit is_write, bit strb0);
        cp_kind: coverpoint kind {
            bins k_data     = {0};
            bins k_tri      = {1};
            bins k_data2    = {2};
            bins k_tri2     = {3};
            bins k_unmapped = {4};
        }
        cp_dir: coverpoint is_write {
            bins rd = {0};
            bins wr = {1};
        }
        cp_strb0: coverpoint strb0 {
            bins off = {0};
            bins on  = {1};
        }
        x_access: cross cp_kind, cp_dir, cp_strb0 {
            ignore_bins read_no_strobe = binsof(cp_dir.rd) && binsof(cp_strb0.off);
        }
    endgroup

    covergroup cg_order with function sample(int order);
        cp_order: coverpoint order {
            bins same     = {ORDER_SAME};
            bins aw_first = {ORDER_AW};
            bins w_first  = {ORDER_W};
        }
    endgroup

    covergroup cg_stall with function sample(int kind);
        cp_stall: coverpoint kind {
            bins no_stall = {0};
            bins b_stall  = {1};
            bins r_stall  = {2};
        }
    endgroup

    covergroup cg_reset with function sample(int point);
        cp_point: coverpoint point {
            bins idle      = {0};
            bins aw_taken  = {1};
            bins w_taken   = {2};
            bins b_pending = {3};
            bins r_pending = {4};
        }
    endgroup

    covergroup cg_inputs with function sample(logic [3:0] value);
        cp_value: coverpoint value;
    endgroup

    cg_access cov_access = new();
    cg_order  cov_order  = new();
    cg_stall  cov_stall  = new();
    cg_reset  cov_reset  = new();
    cg_inputs cov_inputs = new();

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    function automatic void fail(input string msg);
        test_errors++;
        $display("ERROR %s %s", cur_test, msg);
    endfunction

    function automatic void expect32(input logic [31:0] got, input logic [31:0] exp,
                                     input string what);
        if (got !== exp)
            fail($sformatf("%s: got 0x%08h, expected 0x%08h", what, got, exp));
    endfunction

    function automatic int order_of_last_write();
        if (axi.last_aw_edge == axi.last_w_edge) return ORDER_SAME;
        if (axi.last_aw_edge <  axi.last_w_edge) return ORDER_AW;
        return ORDER_W;
    endfunction

    // Change gpio2_io_i at a random point between two edges.
    task automatic set_pins(input logic [3:0] value);
        @(posedge aclk);
        #($urandom_range(1, 9));
        gpio2_io_i = value;
        pins_edge  = axi.edges;
    endtask

    // Three more edges: a following read meets GPIO-SYN-002.
    task automatic settle();
        repeat (3) @(posedge aclk);
    endtask

    task automatic apply_reset(input int cycles = 4);
        @(posedge aclk);
        axi.aresetn <= 1'b0;
        axi.idle();
        repeat (cycles) @(posedge aclk);
        if (axi.awready !== 1'b0 || axi.wready !== 1'b0 || axi.bvalid !== 1'b0 ||
            axi.arready !== 1'b0 || axi.rvalid !== 1'b0)
            fail("GPIO-RST-002 handshake output not 0 during reset");
        axi.aresetn <= 1'b1;
        m_reset();
        @(posedge aclk);
    endtask

    task automatic do_write(input logic [8:0]  a,
                            input logic [31:0] d,
                            input logic [3:0]  s       = 4'hF,
                            input int          order   = ORDER_RANDOM,
                            input int          b_delay = -1);
        int         ord;
        int         awd;
        int         wd;
        int         bd;
        logic [1:0] resp;
        ord = (order == ORDER_RANDOM) ? int'($urandom_range(0, 2)) : order;
        awd = 0;
        wd  = 0;
        if (ord == ORDER_AW) wd  = $urandom_range(1, 3);
        if (ord == ORDER_W)  awd = $urandom_range(1, 3);
        if (b_delay >= 0)
            bd = b_delay;
        else
            bd = ($urandom_range(0, 3) == 0) ? int'($urandom_range(1, 3)) : 0;
        axi.write(a, d, s, awd, wd, bd, resp);
        m_write(a, d, s);
        expect32(resp, 0, $sformatf("GPIO-AXI-003 BRESP of write to 0x%03h", a));
        expect32(axi.gpio_at_first_b, m_data,
                 $sformatf("GPIO-AXI-008 gpio_io_o in the first bvalid cycle of write to 0x%03h", a));
        expect32(gpio_io_o, m_data,
                 $sformatf("GPIO-REG-003 gpio_io_o after write to 0x%03h", a));
        cov_access.sample(kind_of(a), 1'b1, s[0]);
        cov_order.sample(order_of_last_write());
        cov_stall.sample(axi.last_b_stalled ? 1 : 0);
    endtask

    task automatic do_read_v(input  logic [8:0]  a,
                             input  int          r_delay,
                             output logic [31:0] data);
        logic [1:0]  resp;
        logic [31:0] exp;
        int          rd;
        if (r_delay >= 0)
            rd = r_delay;
        else
            rd = ($urandom_range(0, 3) == 0) ? int'($urandom_range(1, 3)) : 0;
        axi.read(a, rd, data, resp);
        if (a[8:2] == 7'd2 && int'(axi.last_ar_edge - pins_edge) < 3)
            fail("testbench: DATA2 read before the inputs were stable for 3 edges");
        exp = m_read(a);
        expect32(resp, 0, $sformatf("GPIO-AXI-010 RRESP of read from 0x%03h", a));
        expect32(data, exp, $sformatf("read from 0x%03h", a));
        cov_access.sample(kind_of(a), 1'b0, 1'b1);
        cov_stall.sample(axi.last_r_stalled ? 2 : 0);
        if (a[8:2] == 7'd2) cov_inputs.sample(gpio2_io_i);
    endtask

    task automatic do_read(input logic [8:0] a, input int r_delay = -1);
        logic [31:0] data;
        do_read_v(a, r_delay, data);
    endtask

    task automatic read_all_regs();
        do_read(A_DATA);
        do_read(A_TRI);
        do_read(A_DATA2);
        do_read(A_TRI2);
    endtask

    // ------------------------------------------------------------------
    // Tests. run_test() applies a reset before each one.
    // ------------------------------------------------------------------

    // GPIO-IF-002, GPIO-RST-001/002/003
    task automatic t_reset_values();
        expect32(gpio_io_o, 0, "GPIO-RST-003 gpio_io_o after reset");
        do_read(A_DATA);
        do_read(A_TRI);
        do_read(A_TRI2);
        do_write(A_DATA, 32'hF);
        do_write(A_TRI,  32'hF);
        do_write(A_TRI2, 32'h0);
        apply_reset();
        expect32(gpio_io_o, 0, "GPIO-RST-003 gpio_io_o after second reset");
        do_read(A_DATA);
        do_read(A_TRI);
        do_read(A_TRI2);
        set_pins(4'h5);
        settle();
        do_read(A_DATA2);
    endtask

    // GPIO-IF-004, GPIO-REG-001/002/003, GPIO-AXI-008/015
    task automatic t_data_rw();
        for (int v = 0; v < 16; v++) begin
            for (int ord = ORDER_SAME; ord <= ORDER_W; ord++) begin
                do_write(A_DATA, {28'($urandom), 4'(v)}, 4'hF, ord);
                do_read(A_DATA);
            end
        end
    endtask

    // GPIO-REG-004/007
    task automatic t_tri_rw();
        do_write(A_DATA, 32'hA);
        for (int v = 0; v < 16; v++) begin
            do_write(A_TRI, {28'($urandom), 4'(v)});
            expect32(gpio_io_o, 32'hA, "GPIO-REG-004 gpio_io_o changed by a TRI write");
            do_read(A_TRI);
        end
        for (int v = 0; v < 16; v++) begin
            do_write(A_TRI2, {28'($urandom), 4'(v)});
            set_pins(4'($urandom));
            settle();
            do_read(A_DATA2);
            do_read(A_TRI2);
        end
    endtask

    // GPIO-IF-005, GPIO-REG-005/006
    task automatic t_data2_read();
        for (int v = 0; v < 16; v++) begin
            set_pins(4'(v));
            settle();
            do_read(A_DATA2);
        end
        do_write(A_DATA, 32'h3);
        for (int i = 0; i < 8; i++) begin
            do_write(A_DATA2, $urandom);
            read_all_regs();
        end
    endtask

    // GPIO-REG-008
    task automatic t_upper_bits();
        set_pins(4'hF);
        settle();
        for (int i = 0; i < 32; i++) begin
            do_write(A_DATA, $urandom | 32'hFFFF_FFF0);
            do_write(A_TRI,  $urandom | 32'hFFFF_FFF0);
            do_write(A_TRI2, $urandom | 32'hFFFF_FFF0);
            read_all_regs();
        end
    endtask

    // GPIO-STB-001/002
    task automatic t_wstrb();
        for (int s = 0; s < 16; s++) begin
            do_write(A_DATA,  $urandom, 4'(s));
            do_write(A_TRI,   $urandom, 4'(s));
            do_write(A_TRI2,  $urandom, 4'(s));
            do_write(A_DATA2, $urandom, 4'(s));
            do_read(A_DATA);
            do_read(A_TRI);
            do_read(A_TRI2);
        end
    endtask

    // GPIO-ADR-001
    task automatic t_addr_low_bits();
        logic [8:0] bases[3];
        bases = '{A_DATA, A_TRI, A_TRI2};
        set_pins(4'h9);
        settle();
        foreach (bases[b]) begin
            for (int lo = 0; lo < 4; lo++) begin
                do_write(bases[b] + 9'(lo), $urandom);
                for (int lr = 0; lr < 4; lr++) do_read(bases[b] + 9'(lr));
            end
        end
        for (int lo = 0; lo < 4; lo++) do_read(A_DATA2 + 9'(lo));
    endtask

    // GPIO-ADR-002/003/004
    task automatic t_unmapped();
        do_write(A_DATA, 32'h5);
        do_write(A_TRI,  32'h6);
        do_write(A_TRI2, 32'h7);
        for (int off = 'h10; off < 'h200; off += 4) begin
            do_write(9'(off), 32'hFFFF_FFFF);
            do_read(9'(off));
        end
        for (int off = 'h11; off < 'h200; off += 37) do_read(9'(off));
        read_all_regs();
        expect32(gpio_io_o, 32'h5, "GPIO-ADR-004 gpio_io_o after unmapped writes");
    endtask

    // GPIO-AXI-001/002
    task automatic t_aw_w_order();
        logic [8:0] a;
        for (int ord = ORDER_SAME; ord <= ORDER_W; ord++) begin
            for (int i = 0; i < 20; i++) begin
                a = pick_rw_addr();
                do_write(a, $urandom, 4'hF, ord);
                if (order_of_last_write() != ord)
                    fail($sformatf("testbench: requested order %0d, observed %0d",
                                   ord, order_of_last_write()));
                do_read(a);
            end
        end
    endtask

    // GPIO-AXI-004/005/011/012
    task automatic t_backpressure();
        logic [8:0] a;
        for (int i = 0; i < 48; i++) begin
            a = pick_rw_addr();
            do_write(a, $urandom, 4'hF, ORDER_RANDOM, 1 + i % 6);
            do_read(a, 1 + i % 6);
        end
    endtask

    // GPIO-AXI-021
    task automatic t_concurrent_rw();
        logic [31:0] d;
        logic [1:0]  resp;
        logic [3:0]  old_v;
        logic [3:0]  new_v;
        for (int i = 0; i < 40; i++) begin
            do_write(A_TRI, $urandom);
            fork
                do_write(A_DATA, $urandom);
                do_read(A_TRI);
            join
            old_v = m_data;
            new_v = 4'($urandom);
            fork
                do_write(A_DATA, {28'd0, new_v});
                axi.read(A_DATA, 0, d, resp);
            join
            expect32(resp, 0, "GPIO-AXI-021 RRESP of overlapping read");
            if (d[31:4] !== 28'd0 || (d[3:0] !== old_v && d[3:0] !== new_v))
                fail($sformatf("GPIO-AXI-021 overlapping read got 0x%08h, expected 0x%0h or 0x%0h",
                               d, old_v, new_v));
        end
    endtask

    // GPIO-SYN-001/002. stable = edges between the input change and the AR
    // handshake edge. Two stages: stable <= 1 returns the old value. The spec
    // bound: stable >= 3 returns the new value. stable == 2 may return either.
    task automatic t_sync_latency();
        logic [31:0] d;
        logic [1:0]  resp;
        logic [3:0]  old_v;
        logic [3:0]  new_v;
        int          stable;
        for (int i = 0; i < 60; i++) begin
            old_v = gpio2_io_i;
            new_v = old_v ^ 4'($urandom_range(1, 15));
            set_pins(new_v);
            repeat (i % 5) @(posedge aclk);
            for (int r = 0; r < 3; r++) begin
                axi.read(A_DATA2, 0, d, resp);
                stable = int'(axi.last_ar_edge - pins_edge);
                expect32(resp, 0, "GPIO-AXI-010 RRESP of DATA2 read");
                if (d[31:4] !== 28'd0)
                    fail($sformatf("GPIO-REG-008 DATA2 upper bits 0x%08h", d));
                if (stable <= 1 && d[3:0] !== old_v)
                    fail($sformatf("GPIO-SYN-001 value 0x%0h after %0d stable edges, expected old 0x%0h",
                                   d[3:0], stable, old_v));
                if (stable >= 3 && d[3:0] !== new_v)
                    fail($sformatf("GPIO-SYN-002 value 0x%0h after %0d stable edges, expected new 0x%0h",
                                   d[3:0], stable, new_v));
                if (stable == 2 && d[3:0] !== old_v && d[3:0] !== new_v)
                    fail($sformatf("GPIO-SYN-002 value 0x%0h after 2 stable edges is neither old nor new",
                                   d[3:0]));
            end
            cov_inputs.sample(new_v);
        end
    endtask

    // GPIO-RST-004/005. Points: 0 idle, 1 AW taken, 2 W taken,
    // 3 B pending, 4 R pending.
    task automatic t_reset_mid_txn();
        logic [31:0] d;
        logic [1:0]  resp;
        for (int rep = 0; rep < 3; rep++) begin
            for (int point = 0; point < 5; point++) begin
                do_write(A_DATA, $urandom);
                do_write(A_TRI,  $urandom);
                do_write(A_TRI2, $urandom);
                fork
                    begin
                        case (point)
                            1: axi.write(A_DATA, $urandom, 4'hF, 0, 12, 0, resp);
                            2: axi.write(A_DATA, $urandom, 4'hF, 12, 0, 0, resp);
                            3: axi.write(A_DATA, $urandom, 4'hF, 0, 0, 12, resp);
                            4: axi.read(A_DATA, 12, d, resp);
                            default: ;
                        endcase
                        if (point != 0)
                            fail($sformatf("testbench: transaction at point %0d ended before the reset",
                                           point));
                    end
                    begin
                        case (point)
                            1: @(ev_aw_hs);
                            2: @(ev_w_hs);
                            3: @(ev_bvalid);
                            4: @(ev_rvalid);
                            default: @(posedge aclk);
                        endcase
                    end
                join_any
                disable fork;
                cov_reset.sample(point);
                apply_reset();
                expect32(gpio_io_o, 0, $sformatf("GPIO-RST-004 gpio_io_o after reset at point %0d", point));
                do_read(A_DATA);
                do_read(A_TRI);
                do_read(A_TRI2);
                do_write(A_DATA, 32'h5);
                do_read(A_DATA);
            end
        end
    endtask

    // GPIO-AXI-015. Replays a vector file from sim/vectors/gen_vectors.py.
    // Expected values come from tools/gpio_reg_model.py and are also
    // compared with this scoreboard.
    task automatic t_random();
        string       path;
        int          fd;
        int          code;
        int          n_ops;
        byte         op;
        logic [31:0] a;
        logic [31:0] d;
        logic [31:0] s;
        logic [31:0] g;
        logic [31:0] got;
        if (!$value$plusargs("VEC=%s", path)) begin
            fail("no +VEC=<file> given");
            return;
        end
        fd = $fopen(path, "r");
        if (fd == 0) begin
            fail($sformatf("cannot open vector file %s", path));
            return;
        end
        n_ops = 0;
        while (!$feof(fd)) begin
            code = $fscanf(fd, " %c", op);
            if (code != 1) break;
            case (op)
                "W": begin
                    code = $fscanf(fd, "%h %h %h %h", a, d, s, g);
                    do_write(a[8:0], d, s[3:0]);
                    expect32(gpio_io_o, g, $sformatf("vector %0d: gpio_io_o vs Python model", n_ops));
                end
                "R": begin
                    code = $fscanf(fd, "%h %h", a, d);
                    do_read_v(a[8:0], -1, got);
                    expect32(got, d, $sformatf("vector %0d: read 0x%03h vs Python model", n_ops, a[8:0]));
                end
                "I": begin
                    code = $fscanf(fd, "%h", a);
                    set_pins(a[3:0]);
                end
                "T": begin
                    code = $fscanf(fd, "%h", a);
                    repeat (a) @(posedge aclk);
                end
                default: begin
                    fail($sformatf("bad vector operation '%c' after %0d operations", op, n_ops));
                    break;
                end
            endcase
            n_ops++;
        end
        $fclose(fd);
        $display("INFO t_random replayed %0d operations from %s", n_ops, path);
        if (n_ops == 0) fail("vector file is empty");
    endtask

    // GPIO-SW-001: configure_ja_gpio()
    task automatic t_sw_configure();
        do_write(A_DATA, 32'hF);
        do_write(A_TRI,  32'hF);
        do_write(A_TRI2, 32'h0);
        do_write(A_TRI,  32'h0000_0000);
        do_write(A_TRI2, 32'hFFFF_FFFF);
        do_write(A_DATA, 32'h0000_0000);
        expect32(gpio_io_o, 0, "GPIO-SW-001 gpio_io_o");
        do_read(A_TRI);
        do_read(A_TRI2);
        do_read(A_DATA);
    endtask

    // GPIO-SW-002: test_ja_outputs()
    task automatic t_sw_test_outputs();
        logic [3:0] pattern[6];
        pattern = '{4'h1, 4'h2, 4'h4, 4'h8, 4'hF, 4'h0};
        foreach (pattern[i]) begin
            do_write(A_DATA, {28'd0, pattern[i]});
            expect32(gpio_io_o, pattern[i], "GPIO-SW-002 gpio_io_o in the test pattern");
        end
    endtask

    // GPIO-SW-003: svf_write_outputs() then svf_read_tdo()
    task automatic t_sw_write_read_tdo();
        logic [31:0] shadow;
        for (int i = 0; i < 256; i++) begin
            shadow = $urandom;
            do_write(A_DATA, shadow & 32'hF);
            set_pins(4'($urandom));
            settle();
            do_read(A_DATA2);
        end
    endtask

    // GPIO-SW-004: read_inputs_with_tck() with a JA1-to-JA7 jumper. The
    // settle stands in for the firmware's usleep(INPUT_SETTLE_US).
    task automatic t_sw_loopback();
        logic [31:0] d;
        for (int tck = 0; tck < 2; tck++) begin
            do_write(A_DATA, tck);
            set_pins({gpio2_io_i[3:1], gpio_io_o[0]});
            settle();
            do_read_v(A_DATA2, 0, d);
            if (d[0] !== 1'(tck))
                fail($sformatf("GPIO-SW-004 TDO read %0d with TCK %0d", d[0], tck));
        end
        do_write(A_DATA, 32'h0);
        expect32(gpio_io_o, 0, "GPIO-SW-004 gpio_io_o after the loopback test");
    endtask

    // GPIO-SW-005: mb_svf_pulse_tck() write stream
    task automatic t_sw_stream();
        for (int i = 0; i < 10000; i++) begin
            do_write(A_DATA, $urandom_range(0, 7));
            if (i % 97 == 0) begin
                set_pins(4'($urandom));
                settle();
                do_read(A_DATA2);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Runner
    // ------------------------------------------------------------------
    task automatic dispatch(input string name);
        case (name)
            "t_reset_values":      t_reset_values();
            "t_data_rw":           t_data_rw();
            "t_tri_rw":            t_tri_rw();
            "t_data2_read":        t_data2_read();
            "t_upper_bits":        t_upper_bits();
            "t_wstrb":             t_wstrb();
            "t_addr_low_bits":     t_addr_low_bits();
            "t_unmapped":          t_unmapped();
            "t_aw_w_order":        t_aw_w_order();
            "t_backpressure":      t_backpressure();
            "t_concurrent_rw":     t_concurrent_rw();
            "t_sync_latency":      t_sync_latency();
            "t_reset_mid_txn":     t_reset_mid_txn();
            "t_random":            t_random();
            "t_sw_configure":      t_sw_configure();
            "t_sw_test_outputs":   t_sw_test_outputs();
            "t_sw_write_read_tdo": t_sw_write_read_tdo();
            "t_sw_loopback":       t_sw_loopback();
            "t_sw_stream":         t_sw_stream();
            default:               fail($sformatf("unknown test %s", name));
        endcase
    endtask

    task automatic run_test(input string name);
        int unsigned assert_before;
        cur_test    = name;
        test_errors = 0;
        n_tests++;
        $display("TEST_START %s", name);
        assert_before = u_chk.fail_count;
        fork
            begin
                apply_reset();
                dispatch(name);
            end
            begin
                #(timeout_ns);
                fail($sformatf("watchdog: test did not finish in %0d ns", timeout_ns));
            end
        join_any
        disable fork;
        axi.idle();
        repeat (4) @(posedge aclk);
        if (u_chk.fail_count != assert_before)
            fail($sformatf("%0d assertion failures", u_chk.fail_count - assert_before));
        if (test_errors == 0) begin
            n_pass++;
            $display("TEST_RESULT %s PASS", name);
        end else begin
            n_fail++;
            $display("TEST_RESULT %s FAIL", name);
        end
    endtask

    initial begin
        string       sel;
        int unsigned seed;
        if (!$value$plusargs("TEST=%s", sel)) sel = "all";
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
        process::self().srandom(seed);
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_axi_gpio_jtag.vcd");
            $dumpvars(0, tb_axi_gpio_jtag);
        end
        $display("SIM_INFO seed=%0d test=%s", seed, sel);
        foreach (test_names[i])
            if (sel == "all" || sel == test_names[i]) run_test(test_names[i]);
        if (n_tests == 0) begin
            $display("ERROR %s unknown test name", sel);
            n_fail++;
        end
        $display("SIM_SUMMARY tests=%0d pass=%0d fail=%0d assert_fail=%0d",
                 n_tests, n_pass, n_fail, u_chk.fail_count);
        $finish;
    end

endmodule
