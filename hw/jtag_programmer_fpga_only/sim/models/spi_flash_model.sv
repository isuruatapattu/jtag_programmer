`timescale 1ns / 1ps
// Behavioral SPI NOR flash (SPI mode 0, single I/O), commands 0x9F (JEDEC ID)
// and 0x03 (READ, 24-bit address, wraps at 16 MiB).
//
// The memory window BASE .. BASE+SIZE-1 is loaded from HEX_FILE
// ($readmemh, one byte per line); every other address reads 0xFF.
// After each SCK falling edge MISO is X from T_HO_NS to T_V_NS, then valid,
// so a reader sampling outside the valid window sees X.
module spi_flash_model #(
    parameter              HEX_FILE = "",
    parameter int          BASE     = 32'h0040_0000,
    parameter int          SIZE     = 65536,
    parameter logic [23:0] JEDEC    = 24'h01_2018,
    parameter real         T_HO_NS  = 2.0,
    parameter real         T_V_NS   = 8.0
) (
    input  wire sck,
    input  wire cs_n,
    input  wire mosi,
    output wire miso
);

    logic [7:0]  mem [0:SIZE-1];
    logic        miso_r;
    logic        out_en;
    int          bit_cnt;
    logic [7:0]  cmd;
    logic [23:0] addr;
    logic [7:0]  out_byte;
    int          out_bit;
    int          jedec_idx;

    int read_cmds;
    int id_cmds;
    int bad_cmds;

    assign miso = out_en ? miso_r : 1'bz;

    // Testbenches may change the ID and the contents at time 0.
    logic [23:0] jedec_val;

    task automatic load(input string fname, input int nbytes);
        for (int i = 0; i < SIZE; i++)
            mem[i] = 8'hFF;
        $readmemh(fname, mem, 0, nbytes - 1);
    endtask

    initial begin
        jedec_val = JEDEC;
        for (int i = 0; i < SIZE; i++)
            mem[i] = 8'hFF;
        if (HEX_FILE != "")
            $readmemh(HEX_FILE, mem);
        out_en    = 1'b0;
        miso_r    = 1'b0;
        read_cmds = 0;
        id_cmds   = 0;
        bad_cmds  = 0;
    end

    function automatic logic [7:0] rd(input logic [23:0] a);
        int off;
        off = int'(a) - BASE;
        if (off >= 0 && off < SIZE)
            return mem[off];
        return 8'hFF;
    endfunction

    always @(negedge cs_n) begin
        bit_cnt = 0;
        cmd     = 8'd0;
        addr    = 24'd0;
        out_bit = -1;
    end

    always @(posedge cs_n)
        out_en <= 1'b0;

    always @(posedge sck) begin
        if (!cs_n) begin
            if (bit_cnt < 8) begin
                cmd = {cmd[6:0], mosi};
                if (bit_cnt == 7) begin
                    if (cmd == 8'h9F) begin
                        id_cmds   = id_cmds + 1;
                        jedec_idx = 0;
                        out_byte  = jedec_val[23:16];
                        out_bit   = 7;
                    end else if (cmd == 8'h03) begin
                        read_cmds = read_cmds + 1;
                    end else begin
                        bad_cmds = bad_cmds + 1;
                    end
                end
            end else if (cmd == 8'h03 && bit_cnt < 32) begin
                addr = {addr[22:0], mosi};
                if (bit_cnt == 31) begin
                    out_byte = rd(addr);
                    out_bit  = 7;
                end
            end
            bit_cnt = bit_cnt + 1;
        end
    end

    // Data bits are launched on the falling edge after the last command or
    // address bit.
    always @(negedge sck) begin
        if (!cs_n && out_bit >= 0) begin
            out_en <= #(T_HO_NS) 1'b1;
            miso_r <= #(T_HO_NS) 1'bx;
            miso_r <= #(T_V_NS) out_byte[out_bit];
            if (out_bit == 0) begin
                out_bit = 7;
                if (cmd == 8'h9F) begin
                    jedec_idx = jedec_idx + 1;
                    out_byte  = (jedec_idx == 1) ? jedec_val[15:8] :
                                (jedec_idx == 2) ? jedec_val[7:0] : 8'hFF;
                end else begin
                    addr     = addr + 24'd1;
                    out_byte = rd(addr);
                end
            end else begin
                out_bit = out_bit - 1;
            end
        end
    end

endmodule
