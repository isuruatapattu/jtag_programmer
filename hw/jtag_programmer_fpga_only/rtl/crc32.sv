`timescale 1ns / 1ps
// Byte-wise CRC-32 (reflected, polynomial 0xEDB88320, init 0xFFFFFFFF,
// final XOR 0xFFFFFFFF), identical to zlib.crc32.
//
// `crc` is the final (XORed) value of all bytes fed since the last `init`.
// `init` has priority over `en`.
module crc32 (
    input  logic        clk,
    input  logic        init,
    input  logic        en,
    input  logic [7:0]  data,
    output logic [31:0] crc
);

    logic [31:0] state;

    function automatic logic [31:0] crc32_byte(input logic [31:0] c_in,
                                               input logic [7:0]  d);
        logic [31:0] c;
        c = c_in ^ {24'd0, d};
        for (int i = 0; i < 8; i++)
            c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        return c;
    endfunction

    always_ff @(posedge clk) begin
        if (init)
            state <= 32'hFFFFFFFF;
        else if (en)
            state <= crc32_byte(state, data);
    end

    assign crc = ~state;

endmodule
