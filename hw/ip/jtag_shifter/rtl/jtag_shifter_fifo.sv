// Synchronous first-word-fall-through FIFO. dout is valid whenever empty = 0.
// DEPTH must be a power of two: the pointers wrap by overflow.
module jtag_shifter_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 512
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   clear,
    input  logic                   wr_en,
    input  logic [WIDTH-1:0]       din,
    output logic                   full,
    input  logic                   rd_en,
    output logic [WIDTH-1:0]       dout,
    output logic                   empty,
    output logic [$clog2(DEPTH):0] level
);

    localparam int          AW      = $clog2(DEPTH);
    localparam logic [AW:0] DEPTH_L = DEPTH;

    (* ram_style = "distributed" *) logic [WIDTH-1:0] mem [DEPTH];

    logic [AW-1:0] wp;
    logic [AW-1:0] rp;
    logic [AW:0]   cnt;
    logic          do_wr;
    logic          do_rd;

    assign full  = (cnt == DEPTH_L);
    assign empty = (cnt == '0);
    assign level = cnt;
    assign dout  = mem[rp];
    assign do_wr = wr_en && !full;
    assign do_rd = rd_en && !empty;

    always_ff @(posedge clk) begin
        if (do_wr) begin
            mem[wp] <= din;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            wp  <= '0;
            rp  <= '0;
            cnt <= '0;
        end else begin
            if (do_wr) begin
                wp <= wp + 1'b1;
            end
            if (do_rd) begin
                rp <= rp + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10:   cnt <= cnt + 1'b1;
                2'b01:   cnt <= cnt - 1'b1;
                default: cnt <= cnt;
            endcase
        end
    end

endmodule
