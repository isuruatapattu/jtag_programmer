`timescale 1ns / 1ps
// System reset generator.
//
// `rst` is synchronous and active high. It is asserted for POR_CYCLES clocks
// after configuration (register initial values come from the bitstream) and
// whenever `rst_n_async` is low. The asynchronous input is synchronized with
// two flip-flops, so `rst` asserts and releases on a clock edge.
module reset_gen #(
    parameter int POR_CYCLES = 31
) (
    input  logic clk,
    input  logic rst_n_async,
    output logic rst
);

    localparam int CW = $clog2(POR_CYCLES + 1);

    (* ASYNC_REG = "TRUE" *) logic rstn_s1;
    (* ASYNC_REG = "TRUE" *) logic rstn_s2;
    logic [CW-1:0] por_cnt = '0;

    initial rst = 1'b1;

    always_ff @(posedge clk) begin
        rstn_s1 <= rst_n_async;
        rstn_s2 <= rstn_s1;
        if (por_cnt != CW'(POR_CYCLES))
            por_cnt <= por_cnt + 1'b1;
        rst <= (por_cnt != CW'(POR_CYCLES)) || !rstn_s2;
    end

endmodule
