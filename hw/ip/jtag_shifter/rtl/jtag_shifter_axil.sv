// AXI4-Lite register interface and JA pin mux for the JTAG shifter.
// The register map is defined in ../doc/jtag_shifter_spec.md.
module jtag_shifter_axil #(
    parameter int ADDR_W   = 8,
    parameter int TX_DEPTH = 512,
    parameter int RX_DEPTH = 256
) (
    input  logic              clk,
    input  logic              rst_n,

    input  logic [ADDR_W-1:0] s_axi_awaddr,
    input  logic              s_axi_awvalid,
    output logic              s_axi_awready,
    input  logic [31:0]       s_axi_wdata,
    input  logic [3:0]        s_axi_wstrb,
    input  logic              s_axi_wvalid,
    output logic              s_axi_wready,
    output logic [1:0]        s_axi_bresp,
    output logic              s_axi_bvalid,
    input  logic              s_axi_bready,
    input  logic [ADDR_W-1:0] s_axi_araddr,
    input  logic              s_axi_arvalid,
    output logic              s_axi_arready,
    output logic [31:0]       s_axi_rdata,
    output logic [1:0]        s_axi_rresp,
    output logic              s_axi_rvalid,
    input  logic              s_axi_rready,

    input  logic [3:0]        gpio_bypass_i,
    input  logic [3:0]        jtag_i,
    output logic [3:0]        jtag_o
);

    localparam logic [5:0] REG_CTRL   = 6'h00;
    localparam logic [5:0] REG_STATUS = 6'h01;
    localparam logic [5:0] REG_CLKDIV = 6'h02;
    localparam logic [5:0] REG_CFG    = 6'h03;
    localparam logic [5:0] REG_DATA   = 6'h04;
    localparam logic [5:0] REG_TDO    = 6'h05;
    localparam logic [5:0] REG_CYCLES = 6'h06;
    localparam logic [5:0] REG_ID     = 6'h07;

    localparam logic [31:0] ID_VALUE      = 32'h4A534831;
    localparam logic [15:0] CLKDIV_RESET  = 16'd5;

    logic        engine_en;
    logic        flush;
    logic [15:0] clkdiv;
    logic [4:0]  cfg_nbm1;
    logic        cfg_mode;
    logic        cfg_tms_last;
    logic        cfg_capture;
    logic [31:0] cycles;

    logic        tx_wr;
    logic        tx_full;
    logic        tx_empty;
    logic [$clog2(TX_DEPTH):0] tx_level;
    logic        rx_rd;
    logic [31:0] rx_dout;
    logic        rx_full;
    logic        rx_empty;
    logic [$clog2(RX_DEPTH):0] rx_level;
    logic        busy;
    logic        eng_tck;
    logic        eng_tms;
    logic        eng_tdi;

    logic              aw_got;
    logic              w_got;
    logic [ADDR_W-1:0] aw_addr;
    logic [31:0]       w_data;
    logic [5:0]        w_idx;
    logic              w_go;
    logic [5:0]        r_idx;
    logic              ar_hs;

    jtag_shifter_core #(
        .TX_DEPTH(TX_DEPTH),
        .RX_DEPTH(RX_DEPTH)
    ) u_core (
        .clk     (clk),
        .rst_n   (rst_n),
        .flush   (flush),
        .clkdiv  (clkdiv),
        .tx_wr   (tx_wr),
        .tx_din  ({cfg_capture, cfg_tms_last, cfg_mode, cfg_nbm1, w_data}),
        .tx_full (tx_full),
        .tx_empty(tx_empty),
        .tx_level(tx_level),
        .rx_rd   (rx_rd),
        .rx_dout (rx_dout),
        .rx_full (rx_full),
        .rx_empty(rx_empty),
        .rx_level(rx_level),
        .busy    (busy),
        .tdo_i   (jtag_i[0]),
        .tck_o   (eng_tck),
        .tms_o   (eng_tms),
        .tdi_o   (eng_tdi)
    );

    // ---------------- Write channel ----------------
    // One write in flight. A DATA write waits here (no BVALID) while the TX
    // FIFO is full.
    assign s_axi_awready = rst_n && !aw_got && !s_axi_bvalid;
    assign s_axi_wready  = rst_n && !w_got && !s_axi_bvalid;
    assign s_axi_bresp   = 2'b00;
    assign w_idx         = aw_addr[7:2];
    assign w_go          = aw_got && w_got && !s_axi_bvalid &&
                           !((w_idx == REG_DATA) && tx_full);
    assign tx_wr         = w_go && (w_idx == REG_DATA);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            aw_got       <= 1'b0;
            w_got        <= 1'b0;
            aw_addr      <= '0;
            w_data       <= '0;
            s_axi_bvalid <= 1'b0;
            engine_en    <= 1'b0;
            flush        <= 1'b0;
            clkdiv       <= CLKDIV_RESET;
            cfg_nbm1     <= 5'd31;
            cfg_mode     <= 1'b0;
            cfg_tms_last <= 1'b0;
            cfg_capture  <= 1'b0;
        end else begin
            flush <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                aw_got  <= 1'b1;
                aw_addr <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_got  <= 1'b1;
                w_data <= s_axi_wdata;
            end

            if (w_go) begin
                aw_got       <= 1'b0;
                w_got        <= 1'b0;
                s_axi_bvalid <= 1'b1;
                case (w_idx)
                    REG_CTRL: begin
                        engine_en <= w_data[0];
                        flush     <= w_data[1];
                    end
                    REG_CLKDIV: clkdiv <= w_data[15:0];
                    REG_CFG: begin
                        cfg_nbm1     <= w_data[4:0];
                        cfg_mode     <= w_data[8];
                        cfg_tms_last <= w_data[9];
                        cfg_capture  <= w_data[10];
                    end
                    default: ;
                endcase
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---------------- Read channel ----------------
    assign s_axi_arready = rst_n && !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;
    assign ar_hs         = s_axi_arvalid && s_axi_arready;
    assign r_idx         = s_axi_araddr[7:2];
    assign rx_rd         = ar_hs && (r_idx == REG_TDO) && !rx_empty;

    function automatic logic [7:0] sat8(input logic [15:0] v);
        return (v > 16'd255) ? 8'd255 : v[7:0];
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
        end else begin
            if (ar_hs) begin
                s_axi_rvalid <= 1'b1;
                case (r_idx)
                    REG_CTRL:   s_axi_rdata <= {31'd0, engine_en};
                    REG_STATUS: s_axi_rdata <= {8'd0,
                                                sat8(16'(rx_level)),
                                                sat8(16'(tx_level)),
                                                3'd0, rx_full, tx_empty,
                                                rx_empty, tx_full, busy};
                    REG_CLKDIV: s_axi_rdata <= {16'd0, clkdiv};
                    REG_CFG:    s_axi_rdata <= {21'd0, cfg_capture, cfg_tms_last,
                                                cfg_mode, 3'd0, cfg_nbm1};
                    REG_TDO:    s_axi_rdata <= rx_empty ? 32'd0 : rx_dout;
                    REG_CYCLES: s_axi_rdata <= cycles;
                    REG_ID:     s_axi_rdata <= ID_VALUE;
                    default:    s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // ---------------- Cycle counter ----------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= '0;
        end else begin
            cycles <= cycles + 32'd1;
        end
    end

    // ---------------- Pin mux ----------------
    // Registered so the output flip-flops can be packed into the IOBs.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            jtag_o <= 4'b0000;
        end else if (engine_en) begin
            jtag_o <= {1'b0, eng_tdi, eng_tms, eng_tck};
        end else begin
            jtag_o <= gpio_bypass_i;
        end
    end

endmodule
