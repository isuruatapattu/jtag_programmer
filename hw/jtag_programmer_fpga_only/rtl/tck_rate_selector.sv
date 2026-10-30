`timescale 1ns / 1ps
// Select the JTAG TCK half period from the switch limit and JBIN request.
//
// Without override, the slower rate (larger half period) is selected. With
// override, the switch-selected rate is used directly.
module tck_rate_selector (
    input  logic        clk,
    input  logic [2:0]  div_sw_sel,
    input  logic        override_en,
    input  logic [15:0] div_file,
    output logic [15:0] half
);

    logic [15:0] div_sw;

    always_comb begin
        case (div_sw_sel)
            3'd0:    div_sw = 16'd5;
            3'd1:    div_sw = 16'd50;
            3'd2:    div_sw = 16'd10;
            3'd3:    div_sw = 16'd4;
            3'd4:    div_sw = 16'd3;
            3'd5:    div_sw = 16'd2;
            3'd6:    div_sw = 16'd500;
            default: div_sw = 16'd5000;
        endcase
    end

    always_ff @(posedge clk)
        half <= (override_en || div_sw > div_file) ? div_sw : div_file;

endmodule
