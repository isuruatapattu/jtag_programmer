`timescale 1ns / 1ps
module led_checker #(parameter int N = 4)(output bit finished = 0);
    bit clk = 0;
    bit rst_n = 1;
    wire [3:0] LED;
    wire programming_done;
    leb_blink #(.STEP_CYCLES(N)) dut (.*);
    always #5 clk = ~clk;

    task automatic check(input logic [3:0] expected);
        if (LED !== expected || programming_done !== 1'b1)
            $fatal(1, "N=%0d LED=%b expected=%b done=%b", N, LED, expected, programming_done);
    endtask
    task automatic tick(input logic [3:0] expected);
        @(posedge clk); #1; check(expected);
    endtask
    task automatic sequence_check;
        for (int cycle = 1; cycle <= 10*N; cycle++) begin
            case ((cycle / N) % 5)
                0: tick(4'b0000);
                1: tick(4'b0001);
                2: tick(4'b0011);
                3: tick(4'b0111);
                4: tick(4'b1111);
            endcase
        end
    endtask
    initial begin
        #1; check(4'b0000);
        sequence_check(); // Startup without reset, two complete cycles.
        repeat (2*N) @(posedge clk);
        #1; check(4'b0011);
        @(negedge clk); rst_n = 0;
        #1; check(4'b0011); // Reset must be synchronous.
        repeat (N+2) tick(4'b0000);
        @(negedge clk); rst_n = 1;
        sequence_check(); // Full off interval after reset release.
        finished = 1;
    end
endmodule
module tb_leb_blink;
    wire a, b, c;
    led_checker #(.N(4)) normal (.finished(a));
    led_checker #(.N(1)) minimum (.finished(b));
    led_checker #(.N(3)) non_power_of_two (.finished(c));
    initial begin
        wait(a && b && c);
        $display("PASS: startup, durations, order, repeats, reset, and acknowledgement");
        $finish;
    end
    initial begin
        #10000; $fatal(1, "Timeout");
    end
endmodule
