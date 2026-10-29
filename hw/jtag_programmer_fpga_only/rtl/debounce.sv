`timescale 1ns / 1ps
// Synchronizer and debouncer for a push button or switch.
// `level` follows the input once it has been stable for STABLE_CYCLES;
// `rise` pulses for one cycle when `level` goes high.
module debounce #(
    parameter int STABLE_CYCLES = 1_000_000
) (
    input  logic clk,
    input  logic rst,
    input  logic din,
    output logic level,
    output logic rise
);

    localparam int CW = $clog2(STABLE_CYCLES + 1);

    logic          s1, s2;
    logic [CW-1:0] cnt;

    always_ff @(posedge clk) begin
        s1   <= din;
        s2   <= s1;
        rise <= 1'b0;
        if (rst) begin
            level <= 1'b0;
            cnt   <= '0;
        end else if (s2 == level) begin
            cnt <= '0;
        end else if (cnt == CW'(STABLE_CYCLES - 1)) begin
            cnt   <= '0;
            level <= s2;
            rise  <= s2;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule
