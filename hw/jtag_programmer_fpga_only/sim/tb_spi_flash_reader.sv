`timescale 1ns / 1ps
// Unit test for spi_flash_reader + byte_fifo against spi_flash_model.
//
// Checks: JEDEC ID read and verdict (good part, blank bus, too-small part),
// streaming with a random-rate consumer, abort and restart at an unaligned
// address, no FIFO overflow, sustained read throughput.
`ifndef VEC_DIR
`define VEC_DIR "build/sim/vectors"
`endif

module tb_spi_flash_reader #(
    parameter int  FIFO_XPM = 0,
    parameter real T_V_NS   = 8.0
);

    localparam int BASE = 32'h0040_0000;
    localparam int SIZE = 65536;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    int errors = 0;

    // ---------------- DUT: good flash ----------------
    logic        cs_n, mosi;
    wire         miso;
    logic        id_done, id_ok;
    logic [23:0] jedec;
    logic        stream_en = 1'b0;
    logic [23:0] start_addr = 24'h400000;
    logic        fifo_wr, fifo_room, fifo_empty, fifo_ovf;
    logic [7:0]  fifo_din, fifo_dout;
    logic        fifo_rd = 1'b0;
    logic        fifo_rst = 1'b0;

    pullup (miso);

    spi_flash_reader u_rd (
        .clk        (clk),
        .rst        (rst),
        .flash_cs_n (cs_n),
        .flash_mosi (mosi),
        .flash_miso (miso),
        .id_done    (id_done),
        .id_ok      (id_ok),
        .jedec_id   (jedec),
        .stream_en  (stream_en),
        .start_addr (start_addr),
        .fifo_wr    (fifo_wr),
        .fifo_din   (fifo_din),
        .fifo_room  (fifo_room)
    );

    byte_fifo #(.DEPTH(4096), .ROOM(320), .USE_XPM(FIFO_XPM)) u_fifo (
        .clk      (clk),
        .rst      (rst || fifo_rst),
        .wr_en    (fifo_wr),
        .din      (fifo_din),
        .rd_en    (fifo_rd),
        .dout     (fifo_dout),
        .empty    (fifo_empty),
        .room     (fifo_room),
        .overflow (fifo_ovf)
    );

    wire fsck = u_rd.u_sck.cclk;

    spi_flash_model #(
        .BASE     (BASE),
        .SIZE     (SIZE),
        .JEDEC    (24'h012018),
        .T_V_NS   (T_V_NS)
    ) u_flash (
        .sck  (fsck),
        .cs_n (cs_n),
        .mosi (mosi),
        .miso (miso)
    );

    // ---------------- blank bus (no flash answers) ----------------
    logic        cs2, mosi2, done2, ok2;
    logic [23:0] jedec2;
    wire         miso2;
    pullup (miso2);

    spi_flash_reader u_rd_blank (
        .clk (clk), .rst (rst), .flash_cs_n (cs2), .flash_mosi (mosi2),
        .flash_miso (miso2), .id_done (done2), .id_ok (ok2),
        .jedec_id (jedec2), .stream_en (1'b0), .start_addr (24'd0),
        .fifo_wr (), .fifo_din (), .fifo_room (1'b0)
    );

    // ---------------- flash too small (32 Mbit) ----------------
    logic        cs3, mosi3, done3, ok3;
    logic [23:0] jedec3;
    wire         miso3;
    pullup (miso3);

    spi_flash_reader u_rd_small (
        .clk (clk), .rst (rst), .flash_cs_n (cs3), .flash_mosi (mosi3),
        .flash_miso (miso3), .id_done (done3), .id_ok (ok3),
        .jedec_id (jedec3), .stream_en (1'b0), .start_addr (24'd0),
        .fifo_wr (), .fifo_din (), .fifo_room (1'b0)
    );

    wire fsck3 = u_rd_small.u_sck.cclk;

    spi_flash_model #(.SIZE(16), .JEDEC(24'hEF4016), .T_V_NS(T_V_NS)) u_flash3 (
        .sck (fsck3), .cs_n (cs3), .mosi (mosi3), .miso (miso3)
    );

    // ---------------- reference data ----------------
    logic [7:0] ref_mem [0:SIZE-1];
    string vec;
    initial begin
        if (!$value$plusargs("VEC=%s", vec))
            vec = `VEC_DIR;
        u_flash.load({vec, "/reader.hex"}, SIZE);
        $readmemh({vec, "/reader.hex"}, ref_mem);
    end

    // Random-rate consumer, checks every byte against ref_mem.
    int     exp_off;
    int     got;
    int     pop_pct = 50;
    logic   consume_on = 1'b0;

    always @(posedge clk) begin
        if (consume_on && !fifo_empty && ($urandom_range(99) < pop_pct)) begin
            fifo_rd <= 1'b1;
        end else begin
            fifo_rd <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (fifo_rd && !fifo_empty) begin
            if (fifo_dout !== ref_mem[exp_off]) begin
                if (errors < 10)
                    $display("ERROR: byte %0d: got %02x expected %02x",
                             exp_off, fifo_dout, ref_mem[exp_off]);
                errors = errors + 1;
            end
            exp_off = exp_off + 1;
            got     = got + 1;
        end
    end

    task automatic stream(input int offset, input int nbytes, input int pct);
        // Stop, flush, restart at BASE + offset.
        consume_on = 1'b0;
        @(posedge clk);
        stream_en  <= 1'b0;
        repeat (4) @(posedge clk);
        fifo_rst   <= 1'b1;
        repeat (16) @(posedge clk);
        fifo_rst   <= 1'b0;
        repeat (32) @(posedge clk);
        exp_off    = offset;
        got        = 0;
        pop_pct    = pct;
        start_addr <= 24'(BASE + offset);
        stream_en  <= 1'b1;
        consume_on = 1'b1;
        wait (got >= nbytes);
        consume_on = 1'b0;
        $display("%0t ns: streamed %0d bytes from offset %0d", $time / 1000,
                 nbytes, offset);
    endtask

    realtime t0, t1;

    initial begin
        exp_off = 0;
        got     = 0;
        repeat (10) @(posedge clk);
        rst <= 1'b0;

        wait (id_done && done2 && done3);
        $display("JEDEC good=%06x ok=%0d  blank=%06x ok=%0d  small=%06x ok=%0d",
                 jedec, id_ok, jedec2, ok2, jedec3, ok3);
        if (jedec !== 24'h012018 || id_ok !== 1'b1) begin
            $display("ERROR: good flash ID not accepted");
            errors = errors + 1;
        end
        if (jedec2 !== 24'hFFFFFF || ok2 !== 1'b0) begin
            $display("ERROR: blank bus accepted");
            errors = errors + 1;
        end
        if (jedec3 !== 24'hEF4016 || ok3 !== 1'b0) begin
            $display("ERROR: 32 Mbit flash accepted");
            errors = errors + 1;
        end

        // Slow consumer: the FIFO fills up and the reader must throttle.
        stream(0, 6000, 2);
        // Fast consumer from an unaligned offset.
        stream(16'h1234, 3000, 90);
        // Restart in the middle of a block.
        stream(7, 100, 100);
        repeat (37) @(posedge clk);
        stream(32000, 2000, 60);

        // Throughput with a consumer that never waits.
        stream(0, 64, 100);
        t0 = $realtime;
        got = 0;
        consume_on = 1'b1;
        wait (got >= 8192);
        t1 = $realtime;
        $display("throughput: %0.3f MB/s", 8192.0 * 1000.0 / (t1 - t0));
        if (8192.0 * 1000.0 / (t1 - t0) < 2.9) begin
            $display("ERROR: throughput below 2.9 MB/s");
            errors = errors + 1;
        end

        if (fifo_ovf) begin
            $display("ERROR: FIFO overflow");
            errors = errors + 1;
        end
        if (u_flash.bad_cmds != 0) begin
            $display("ERROR: flash saw %0d unknown commands", u_flash.bad_cmds);
            errors = errors + 1;
        end
        $display("flash commands: %0d READ, %0d JEDEC", u_flash.read_cmds,
                 u_flash.id_cmds);
        if (errors == 0)
            $display("TEST PASSED: tb_spi_flash_reader");
        else
            $display("TEST FAILED: tb_spi_flash_reader (%0d errors)", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TEST FAILED: tb_spi_flash_reader timeout");
        $finish;
    end

endmodule
