`timescale 1ns / 1ps
// Behavioral IEEE 1149.1 target, close enough to a 7-series FPGA for the
// programming sequence that Vivado writes into SVF files.
//
//   IR: 6 bits, captures {DONE, INIT_COMPLETE = 1, 2'b00, 2'b01}
//   IDCODE   0x09  32-bit DR, captures `idcode` (settable by the testbench)
//   CFG_IN   0x05  counts the bits shifted into it (`cfg_bits`)
//   CFG_OUT  0x04  32-bit DR, captures 0x3F5E0D40 with bit 27 = DONE
//   JPROGRAM 0x0B  clears DONE and the configuration
//   JSTART   0x0C  sets DONE if configuration data was received
//   others         1-bit BYPASS register
//
// TMS/TDI are sampled on the rising TCK edge; TDO changes TDO_DELAY_NS after
// the falling edge and is released (pulled up) outside Shift-IR/DR.
module tap_model #(
    parameter real TDO_DELAY_NS = 15.0
) (
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output wire tdo
);

    localparam logic [3:0]
        TLR = 4'd0,  RTI = 4'd1,  SELDR = 4'd2,  CAPDR = 4'd3,
        SHDR = 4'd4, EX1DR = 4'd5, PADR = 4'd6,  EX2DR = 4'd7,
        UPDR = 4'd8, SELIR = 4'd9, CAPIR = 4'd10, SHIR = 4'd11,
        EX1IR = 4'd12, PAIR = 4'd13, EX2IR = 4'd14, UPIR = 4'd15;

    logic [3:0]  state = TLR;
    logic [5:0]  ir = 6'h09;
    logic [5:0]  ir_sr;
    logic [31:0] dr_sr;
    int          dr_len;
    logic        done = 1'b0;
    logic        tdo_r = 1'b1;
    logic        tdo_en = 1'b0;

    logic [31:0] idcode = 32'h1363_1093;
    longint      cfg_bits = 0;
    int          tck_count = 0;
    int          resets = 0;

    assign tdo = tdo_en ? tdo_r : 1'bz;

    function automatic logic [3:0] next_state(input logic [3:0] s,
                                              input logic m);
        case (s)
            TLR:   return m ? TLR   : RTI;
            RTI:   return m ? SELDR : RTI;
            SELDR: return m ? SELIR : CAPDR;
            CAPDR: return m ? EX1DR : SHDR;
            SHDR:  return m ? EX1DR : SHDR;
            EX1DR: return m ? UPDR  : PADR;
            PADR:  return m ? EX2DR : PADR;
            EX2DR: return m ? UPDR  : SHDR;
            UPDR:  return m ? SELDR : RTI;
            SELIR: return m ? TLR   : CAPIR;
            CAPIR: return m ? EX1IR : SHIR;
            SHIR:  return m ? EX1IR : SHIR;
            EX1IR: return m ? UPIR  : PAIR;
            PAIR:  return m ? EX2IR : PAIR;
            EX2IR: return m ? UPIR  : SHIR;
            default: return m ? SELDR : RTI;   // UPIR
        endcase
    endfunction

    always @(posedge tck) begin
        tck_count = tck_count + 1;
        case (state)
            CAPIR: ir_sr = {done, 1'b1, 2'b00, 2'b01};
            SHIR:  ir_sr = {tdi, ir_sr[5:1]};
            UPIR: begin
                ir = ir_sr;
                if (ir_sr == 6'h0B) begin
                    done     = 1'b0;
                    cfg_bits = 0;
                end
                if (ir_sr == 6'h0C && cfg_bits > 0)
                    done = 1'b1;
            end
            CAPDR: begin
                case (ir)
                    6'h09:   begin dr_sr = idcode; dr_len = 32; end
                    6'h04:   begin dr_sr = 32'h3F5E0D40 & ~(32'd1 << 27) |
                                           ({31'd0, done} << 27);
                                   dr_len = 32; end
                    6'h05:   begin dr_sr = 32'd0; dr_len = 32; end
                    default: begin dr_sr = 32'd0; dr_len = 1; end
                endcase
            end
            SHDR: begin
                if (ir == 6'h05)
                    cfg_bits = cfg_bits + 1;
                if (dr_len == 32)
                    dr_sr = {tdi, dr_sr[31:1]};
                else
                    dr_sr[0] = tdi;
            end
            default: ;
        endcase
        if (state != TLR && next_state(state, tms) == TLR)
            resets = resets + 1;
        state = next_state(state, tms);
        if (state == TLR)
            ir = 6'h09;
    end

    always @(negedge tck) begin
        if (state == SHIR) begin
            tdo_en <= #(TDO_DELAY_NS) 1'b1;
            tdo_r  <= #(TDO_DELAY_NS) ir_sr[0];
        end else if (state == SHDR) begin
            tdo_en <= #(TDO_DELAY_NS) 1'b1;
            tdo_r  <= #(TDO_DELAY_NS) dr_sr[0];
        end else begin
            tdo_en <= #(TDO_DELAY_NS) 1'b0;
        end
    end

endmodule
