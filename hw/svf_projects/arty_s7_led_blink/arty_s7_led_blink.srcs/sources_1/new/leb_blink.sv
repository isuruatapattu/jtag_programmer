`timescale 1ns / 1ps

module leb_blink #(
    // Positive clock count per animation step: 0.5 s at 100 MHz.
    parameter int unsigned STEP_CYCLES = 50_000_000
) (
    input wire clk,
    input wire rst_n,
    output logic [3:0] LED = 4'b0000,
    output wire programming_done
);
    localparam int COUNTER_WIDTH = (STEP_CYCLES > 1) ? $clog2(STEP_CYCLES) : 1;
    logic [COUNTER_WIDTH-1:0] counter = '0;

    // Driven once configuration startup enables user I/O; independent of reset.
    assign programming_done = 1'b1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            counter <= '0;
            LED <= 4'b0000;
        end else if (counter == STEP_CYCLES - 1) begin
            counter <= '0;
            case (LED)
                4'b0000: LED <= 4'b0001;
                4'b0001: LED <= 4'b0011;
                4'b0011: LED <= 4'b0111;
                4'b0111: LED <= 4'b1111;
                default: LED <= 4'b0000;
            endcase
        end else begin
            counter <= counter + 1'b1;
        end
    end
endmodule
