`timescale 1ns / 1ps
// Streaming reader for the configuration SPI flash (SPI mode 0, single I/O).
//
// After EOS it sends 8 dummy SCK cycles with CS high (STARTUPE2 swallows the
// first three), then reads the JEDEC ID (0x9F) once. `id_done` / `id_ok`
// report the result.
//
// While `stream_en` is 1 it reads the flash from `start_addr` onwards with
// 0x03 READ commands of BLOCK_BYTES bytes each and pushes the bytes into a
// FIFO. A block is started only when the FIFO reports `fifo_room`, so writes
// never overflow. Dropping `stream_en` ends the current command at once (no
// partial byte is written). `start_addr` is sampled when the reader first
// sees `stream_en` high after it was low.
//
// SCK = clk / 4 (25 MHz at 100 MHz). One bit takes 4 clock cycles, phases
// 0..3: SCK is low in phases 0-1 and high in phases 2-3. MOSI changes at the
// start of phase 0, the flash samples it at the rising edge (start of phase
// 2). The flash drives MISO after the falling edge (start of phase 0); the
// IOB register captures it at the start of phase 3, 30 ns after the falling
// edge, which leaves room for the STARTUPE2 CCLK delay plus the flash
// clock-to-output time.
module spi_flash_reader #(
    parameter int BLOCK_BYTES = 256,
    parameter int GAP_CYCLES  = 8
) (
    input  logic        clk,
    input  logic        rst,

    output logic        flash_cs_n,
    output logic        flash_mosi,
    input  logic        flash_miso,

    output logic        id_done,
    output logic        id_ok,
    output logic [23:0] jedec_id,

    input  logic        stream_en,
    input  logic [23:0] start_addr,
    output logic        fifo_wr,
    output logic [7:0]  fifo_din,
    input  logic        fifo_room
);

    localparam int NB_W = $clog2(32 + 8 * BLOCK_BYTES + 1);

    typedef enum logic [2:0] {
        S_EOS,
        S_DUMMY,
        S_GAP,
        S_IDLE,
        S_CSLOW,
        S_XFER,
        S_END
    } state_t;

    state_t          state;
    logic [1:0]      ph;
    logic [4:0]      cnt;
    logic [31:0]     tx_sr;
    logic [6:0]      rx_sr;
    logic [NB_W-1:0] bit_idx;
    logic [NB_W-1:0] last_bit;
    logic [5:0]      tx_bits;
    logic            is_read;
    logic [23:0]     addr;
    logic            running;
    logic            sck;
    logic            eos;

    (* IOB = "TRUE" *) logic cs_q;
    (* IOB = "TRUE" *) logic mosi_q;
    (* IOB = "TRUE" *) logic miso_q;

    assign flash_cs_n = cs_q;
    assign flash_mosi = mosi_q;

    flash_sck_startup u_sck (
        .usrcclko (sck),
        .eos      (eos)
    );

    always_ff @(posedge clk)
        miso_q <= flash_miso;

    // The JEDEC ID read is never aborted; a stream read is aborted when
    // stream_en drops.
    logic abort_xfer;
    assign abort_xfer = is_read && !stream_en;

    always_ff @(posedge clk) begin
        fifo_wr <= 1'b0;
        if (rst) begin
            state    <= S_EOS;
            ph       <= 2'd0;
            cnt      <= 5'd0;
            sck      <= 1'b0;
            cs_q     <= 1'b1;
            mosi_q   <= 1'b0;
            tx_sr    <= 32'd0;
            rx_sr    <= 7'd0;
            bit_idx  <= '0;
            last_bit <= '0;
            tx_bits  <= 6'd0;
            is_read  <= 1'b0;
            addr     <= 24'd0;
            running  <= 1'b0;
            id_done  <= 1'b0;
            id_ok    <= 1'b0;
            jedec_id <= 24'd0;
            fifo_din <= 8'd0;
        end else begin
            case (state)
                S_EOS: begin
                    cnt <= 5'd0;
                    ph  <= 2'd0;
                    if (eos)
                        state <= S_DUMMY;
                end

                // 8 SCK cycles with CS high.
                S_DUMMY: begin
                    ph <= ph + 2'd1;
                    if (ph == 2'd1)
                        sck <= 1'b1;
                    if (ph == 2'd3) begin
                        sck <= 1'b0;
                        cnt <= cnt + 5'd1;
                        if (cnt == 5'd7) begin
                            cnt   <= 5'd0;
                            state <= S_GAP;
                        end
                    end
                end

                // CS high time between commands.
                S_GAP: begin
                    cs_q <= 1'b1;
                    sck  <= 1'b0;
                    cnt  <= cnt + 5'd1;
                    if (cnt == 5'(GAP_CYCLES - 1)) begin
                        cnt <= 5'd0;
                        if (!id_done) begin
                            tx_sr    <= {8'h9F, 24'd0};
                            tx_bits  <= 6'd8;
                            last_bit <= NB_W'(8 + 24 - 1);
                            is_read  <= 1'b0;
                            cs_q     <= 1'b0;
                            state    <= S_CSLOW;
                        end else begin
                            state <= S_IDLE;
                        end
                    end
                end

                S_IDLE: begin
                    if (stream_en && !running) begin
                        addr    <= start_addr;
                        running <= 1'b1;
                    end else if (stream_en && fifo_room) begin
                        tx_sr    <= {8'h03, addr};
                        tx_bits  <= 6'd32;
                        last_bit <= NB_W'(32 + 8 * BLOCK_BYTES - 1);
                        is_read  <= 1'b1;
                        cs_q     <= 1'b0;
                        state    <= S_CSLOW;
                    end
                end

                // CS setup time, then the first bit.
                S_CSLOW: begin
                    cnt <= cnt + 5'd1;
                    if (abort_xfer) begin
                        cnt   <= 5'd0;
                        state <= S_GAP;
                    end else if (cnt == 5'd1) begin
                        cnt     <= 5'd0;
                        ph      <= 2'd0;
                        bit_idx <= '0;
                        mosi_q  <= tx_sr[31];
                        tx_sr   <= {tx_sr[30:0], 1'b0};
                        state   <= S_XFER;
                    end
                end

                S_XFER: begin
                    if (abort_xfer) begin
                        sck   <= 1'b0;
                        cnt   <= 5'd0;
                        state <= S_GAP;
                    end else begin
                        ph <= ph + 2'd1;
                        if (ph == 2'd1)
                            sck <= 1'b1;
                        if (ph == 2'd3) begin
                            sck <= 1'b0;
                            if (bit_idx >= NB_W'(tx_bits)) begin
                                rx_sr <= {rx_sr[5:0], miso_q};
                                if (bit_idx[2:0] == 3'd7) begin
                                    if (is_read) begin
                                        fifo_din <= {rx_sr, miso_q};
                                        fifo_wr  <= 1'b1;
                                    end else begin
                                        jedec_id <= {jedec_id[15:0], rx_sr, miso_q};
                                    end
                                end
                            end
                            if (bit_idx == last_bit) begin
                                state <= S_END;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                                mosi_q  <= tx_sr[31];
                                tx_sr   <= {tx_sr[30:0], 1'b0};
                            end
                        end
                    end
                end

                // SCK is low; release CS one cycle later.
                S_END: begin
                    cnt   <= 5'd0;
                    state <= S_GAP;
                    if (is_read) begin
                        addr <= addr + 24'(BLOCK_BYTES);
                    end else begin
                        id_done <= 1'b1;
                        id_ok   <= (jedec_id[23:16] != 8'h00) &&
                                   (jedec_id[23:16] != 8'hFF) &&
                                   (jedec_id[7:0] >= 8'h17) &&
                                   (jedec_id[7:0] <= 8'h20);
                    end
                end

                default: state <= S_EOS;
            endcase
            if (!stream_en)
                running <= 1'b0;
        end
    end

endmodule
