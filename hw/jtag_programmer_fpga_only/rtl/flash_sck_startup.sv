`timescale 1ns / 1ps
// Drives the configuration flash clock (CCLK, pin E9) from user logic.
//
// On 7-series devices CCLK is a dedicated pin that is only reachable through
// STARTUPE2.USRCCLKO. The first three USRCCLKO edges after configuration are
// used to switch the clock source and do not reach the pin, so the reader
// issues dummy clocks before its first command.
//
// sim/models/flash_sck_startup_sim.sv is a drop-in replacement for
// simulation.
module flash_sck_startup (
    input  logic usrcclko,
    output logic eos
);

    STARTUPE2 #(
        .PROG_USR      ("FALSE"),
        .SIM_CCLK_FREQ (0.0)
    ) u_startup (
        .CFGCLK    (),
        .CFGMCLK   (),
        .EOS       (eos),
        .PREQ      (),
        .CLK       (1'b0),
        .GSR       (1'b0),
        .GTS       (1'b0),
        .KEYCLEARB (1'b1),
        .PACK      (1'b0),
        .USRCCLKO  (usrcclko),
        .USRCCLKTS (1'b0),
        .USRDONEO  (1'b1),
        .USRDONETS (1'b1)
    );

endmodule
