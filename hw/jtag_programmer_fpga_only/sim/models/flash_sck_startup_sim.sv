`timescale 1ns / 1ps
// Simulation replacement for rtl/flash_sck_startup.sv.
//
// `cclk` is the clock seen by the flash pin. Like STARTUPE2, it swallows the
// first three USRCCLKO rising edges after EOS. Testbenches connect the flash
// model to <instance>.cclk hierarchically.
module flash_sck_startup #(
    parameter int  EOS_DELAY_NS = 200,
    parameter real CCLK_DELAY_NS = 3.0
) (
    input  logic usrcclko,
    output logic eos
);

    logic cclk;
    int   swallowed;

    initial begin
        eos       = 1'b0;
        cclk      = 1'b0;
        swallowed = 0;
        #(EOS_DELAY_NS);
        eos = 1'b1;
    end

    always @(posedge usrcclko) begin
        if (eos && swallowed < 3)
            swallowed = swallowed + 1;
        else if (eos)
            cclk <= #(CCLK_DELAY_NS) 1'b1;
    end

    always @(negedge usrcclko)
        cclk <= #(CCLK_DELAY_NS) 1'b0;

endmodule
