`timescale 1ns / 1ps
// Prints one status line on the USB-UART (8N1):
//
//     "JTAG <text> 0x<info as 16 hex digits>\r\n"
//
// <text> is 8 characters chosen by `code` (the jbin_decoder status codes,
// plus 10 = flash ID error and 12 = flash ID OK). `send` is ignored while a
// line is being sent.
module uart_tx_status #(
    parameter int CLK_PER_BIT = 868   // 100 MHz / 115200
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        send,
    input  logic [3:0]  code,
    input  logic [63:0] info,
    output logic        tx,
    output logic        busy
);

    localparam int MSG_LEN = 34;

    function automatic logic [63:0] code_text(input logic [3:0] c);
        case (c)
            4'd1:    return "OK      ";
            4'd2:    return "ERR TDO ";
            4'd3:    return "ERR HDR ";
            4'd4:    return "ERR OPC ";
            4'd5:    return "ERR OVR ";
            4'd6:    return "ERR CRC ";
            4'd7:    return "ERR TCK ";
            4'd8:    return "ABORT   ";
            4'd9:    return "ERR ARG ";
            4'd10:   return "ERR FLID";
            4'd11:   return "ERR TOUT";
            4'd12:   return "FLASH OK";
            default: return "?       ";
        endcase
    endfunction

    function automatic logic [7:0] hex_char(input logic [3:0] v);
        return (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h57 + {4'd0, v});
    endfunction

    logic [3:0]  code_q;
    logic [63:0] info_q;
    logic [5:0]  idx;
    logic [3:0]  bit_no;
    logic [9:0]  baud;
    logic [9:0]  sr;
    logic [7:0]  ch;
    logic [63:0] text;

    assign text = code_text(code_q);

    always_comb begin
        if (idx < 6'd5)
            ch = "JTAG "  >> (8 * (4 - idx));
        else if (idx < 6'd13)
            ch = text >> (8 * (12 - idx));
        else if (idx == 6'd13)
            ch = " ";
        else if (idx == 6'd14)
            ch = "0";
        else if (idx == 6'd15)
            ch = "x";
        else if (idx < 6'd32)
            ch = hex_char(info_q[4 * (31 - idx) +: 4]);
        else if (idx == 6'd32)
            ch = 8'h0D;
        else
            ch = 8'h0A;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            tx     <= 1'b1;
            busy   <= 1'b0;
            idx    <= 6'd0;
            bit_no <= 4'd0;
            baud   <= 10'd0;
            sr     <= 10'h3FF;
            code_q <= 4'd0;
            info_q <= 64'd0;
        end else if (!busy) begin
            tx <= 1'b1;
            if (send) begin
                code_q <= code;
                info_q <= info;
                idx    <= 6'd0;
                bit_no <= 4'd0;
                baud   <= 10'd0;
                busy   <= 1'b1;
                sr     <= 10'h3FF;
            end
        end else if (baud != 10'd0) begin
            baud <= baud - 10'd1;
        end else begin
            baud <= 10'(CLK_PER_BIT - 1);
            if (bit_no == 4'd0) begin
                // Start bit; load the frame {stop, data, start}.
                sr     <= {1'b1, ch, 1'b0};
                tx     <= 1'b0;
                bit_no <= 4'd1;
            end else if (bit_no < 4'd10) begin
                tx     <= sr[bit_no];
                bit_no <= bit_no + 4'd1;
            end else begin
                bit_no <= 4'd0;
                baud   <= 10'd0;
                if (idx == 6'(MSG_LEN - 1))
                    busy <= 1'b0;
                else
                    idx <= idx + 6'd1;
            end
        end
    end

endmodule
