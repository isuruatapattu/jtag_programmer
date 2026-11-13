`timescale 1ns / 1ps

// AXI4-Lite master BFM for tb_axi_gpio_jtag.
//
// Timing rules, race free because every DUT output is a flip-flop:
//   - Every task starts on a rising edge of aclk.
//   - Master signals are driven with non-blocking assignments right after an
//     edge, so the DUT sees them at the next edge.
//   - Slave signals are read right after an edge, before that edge's
//     non-blocking updates, so the value read is the one the DUT drove in the
//     cycle that just ended. "valid && ready" read this way means the
//     handshake happened on that edge.
//   - After a handshake the address, data and strobe are overwritten with
//     random values, so the DUT must use what it captured (GPIO-AXI-002).
//
// edges counts rising edges. Read right after edge n it still holds n - 1.

interface axi_lite_if (input logic aclk, input logic [3:0] gpio_io_o);

    logic        aresetn;
    logic [8:0]  awaddr;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [8:0]  araddr;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    int unsigned edges = 0;
    always @(posedge aclk) edges <= edges + 1;

    // Results of the last write and the last read
    int unsigned last_aw_edge;
    int unsigned last_w_edge;
    int unsigned last_ar_edge;
    logic [3:0]  gpio_at_first_b;
    bit          last_b_stalled;
    bit          last_r_stalled;

    initial begin
        aresetn = 1'b0;
        awaddr  = '0;
        awvalid = 1'b0;
        wdata   = '0;
        wstrb   = '0;
        wvalid  = 1'b0;
        bready  = 1'b0;
        araddr  = '0;
        arvalid = 1'b0;
        rready  = 1'b0;
    end

    task automatic idle();
        awvalid <= 1'b0;
        wvalid  <= 1'b0;
        bready  <= 1'b0;
        arvalid <= 1'b0;
        rready  <= 1'b0;
    endtask

    // aw_delay, w_delay: cycles before AWVALID / WVALID go high.
    // b_delay: cycles BREADY stays low after BVALID is first seen.
    task automatic write(input  logic [8:0]  addr,
                         input  logic [31:0] data,
                         input  logic [3:0]  strb,
                         input  int          aw_delay,
                         input  int          w_delay,
                         input  int          b_delay,
                         output logic [1:0]  resp);
        gpio_at_first_b = 'x;
        resp            = 'x;
        @(posedge aclk);
        fork
            begin
                repeat (aw_delay) @(posedge aclk);
                awaddr  <= addr;
                awvalid <= 1'b1;
                do @(posedge aclk); while (!awready);
                last_aw_edge = edges;
                awvalid <= 1'b0;
                awaddr  <= 9'($urandom);
            end
            begin
                repeat (w_delay) @(posedge aclk);
                wdata  <= data;
                wstrb  <= strb;
                wvalid <= 1'b1;
                do @(posedge aclk); while (!wready);
                last_w_edge = edges;
                wvalid <= 1'b0;
                wdata  <= $urandom;
                wstrb  <= 4'($urandom);
            end
            begin
                bit seen;
                bit stalled;
                int waited;
                seen    = 1'b0;
                stalled = 1'b0;
                waited  = 0;
                bready <= (b_delay == 0);
                forever begin
                    @(posedge aclk);
                    if (bvalid && !seen) begin
                        seen            = 1'b1;
                        gpio_at_first_b = gpio_io_o;
                    end
                    if (bvalid && !bready) stalled = 1'b1;
                    if (bvalid && bready) begin
                        resp = bresp;
                        break;
                    end
                    if (bvalid) waited++;
                    if (waited >= b_delay) bready <= 1'b1;
                end
                bready <= 1'b0;
                last_b_stalled = stalled;
            end
        join
    endtask

    // r_delay: cycles RREADY stays low after RVALID is first seen.
    task automatic read(input  logic [8:0]  addr,
                        input  int          r_delay,
                        output logic [31:0] data,
                        output logic [1:0]  resp);
        data = 'x;
        resp = 'x;
        @(posedge aclk);
        fork
            begin
                araddr  <= addr;
                arvalid <= 1'b1;
                do @(posedge aclk); while (!arready);
                last_ar_edge = edges;
                arvalid <= 1'b0;
                araddr  <= 9'($urandom);
            end
            begin
                bit stalled;
                int waited;
                stalled = 1'b0;
                waited  = 0;
                rready <= (r_delay == 0);
                forever begin
                    @(posedge aclk);
                    if (rvalid && !rready) stalled = 1'b1;
                    if (rvalid && rready) begin
                        data = rdata;
                        resp = rresp;
                        break;
                    end
                    if (rvalid) waited++;
                    if (waited >= r_delay) rready <= 1'b1;
                end
                rready <= 1'b0;
                last_r_stalled = stalled;
            end
        join
    endtask

endinterface
