`timescale 1ns / 1ps
// BGT60TR13C SPI mode-0 master: 32-bit register frames and FIFO burst.
module bgt60_spi_master (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [1:0]  cmd,
    input  wire [6:0]  addr,
    input  wire [23:0] wdata,
    input  wire [9:0]  burst_nwords,
    (* mark_debug = "true" *) output reg         busy,
    (* mark_debug = "true" *) output reg         done,
    (* mark_debug = "true" *) output reg  [23:0] rdata,
    (* mark_debug = "true" *) output reg  [7:0]  gsr0,
    (* mark_debug = "true" *) output reg  [23:0] fifo_word,
    (* mark_debug = "true" *) output reg         fifo_word_valid,
    (* mark_debug = "true" *) output reg         spi_sclk,
    (* mark_debug = "true" *) output reg         spi_mosi,
    input  wire        spi_miso,
    (* mark_debug = "true" *) output reg         spi_cs_n
);
    localparam CMD_WR    = 2'd0;
    localparam CMD_RD    = 2'd1;
    localparam CMD_BURST = 2'd2;

    localparam ST_IDLE  = 3'd0;
    localparam ST_LEAD  = 3'd1;
    localparam ST_LOW   = 3'd2;
    localparam ST_HIGH  = 3'd3;
    localparam ST_TRAIL = 3'd4;
    localparam ST_DONE  = 3'd5;

    localparam [2:0] HALF = 3'd3; // 4-cycle half period → 12.5 MHz

    reg [2:0]  state;
    reg [2:0]  div;
    reg [31:0] tx_sr;
    reg [31:0] rx_sr;
    reg [15:0] bits_left;
    reg [4:0]  burst_bit;
    reg [9:0]  words_left;
    reg        header_done;
    reg [1:0]  cmd_r;

    wire [31:0] wr_word    = {addr, 1'b1, wdata};
    wire [31:0] rd_word    = {addr, 1'b0, 24'b0};
    wire [31:0] burst_cmd  = 32'hFFC0_0000;

    always @(posedge clk) begin
        if (rst) begin
            state           <= ST_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            spi_cs_n        <= 1'b1;
            spi_sclk        <= 1'b0;
            spi_mosi        <= 1'b0;
            fifo_word_valid <= 1'b0;
            rdata           <= 24'd0;
            gsr0            <= 8'd0;
            fifo_word       <= 24'd0;
            div             <= 3'd0;
            tx_sr           <= 32'd0;
            rx_sr           <= 32'd0;
            bits_left       <= 16'd0;
            burst_bit       <= 5'd23;
            words_left      <= 10'd0;
            header_done     <= 1'b0;
            cmd_r           <= 2'd0;
        end else begin
            done            <= 1'b0;
            fifo_word_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    busy     <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        cmd_r       <= cmd;
                        header_done <= 1'b0;
                        rx_sr       <= 32'd0;
                        if (cmd == CMD_BURST) begin
                            tx_sr      <= burst_cmd;
                            spi_mosi   <= burst_cmd[31];
                            bits_left  <= 16'd31;
                            words_left <= burst_nwords;
                        end else if (cmd == CMD_WR) begin
                            tx_sr     <= wr_word;
                            spi_mosi  <= wr_word[31];
                            bits_left <= 16'd31;
                        end else begin
                            tx_sr     <= rd_word;
                            spi_mosi  <= rd_word[31];
                            bits_left <= 16'd31;
                        end
                        spi_cs_n   <= 1'b0;
                        div        <= 3'd0;
                        burst_bit  <= 5'd23;
                        state      <= ST_LEAD;
                    end
                end

                ST_LEAD: begin
                    if (div == HALF) begin
                        div   <= 3'd0;
                        state <= ST_LOW;
                    end else
                        div <= div + 3'd1;
                end

                ST_LOW: begin
                    spi_sclk <= 1'b0;
                    if (div == HALF) begin
                        div      <= 3'd0;
                        spi_sclk <= 1'b1;
                        rx_sr    <= {rx_sr[30:0], spi_miso};
                        state    <= ST_HIGH;
                    end else
                        div <= div + 3'd1;
                end

                ST_HIGH: begin
                    spi_sclk <= 1'b1;
                    if (div == HALF) begin
                        div      <= 3'd0;
                        spi_sclk <= 1'b0;

                        if (!header_done) begin
                            if (bits_left == 16'd0) begin
                                rdata        <= rx_sr[23:0];
                                gsr0         <= rx_sr[31:24];
                                header_done  <= 1'b1;
                                if (cmd_r == CMD_BURST) begin
                                    spi_mosi   <= 1'b0;
                                    burst_bit  <= 5'd23;
                                    bits_left  <= 16'd23;
                                    rx_sr      <= 32'd0;
                                    state      <= ST_LOW;
                                end else begin
                                    state <= ST_TRAIL;
                                end
                            end else begin
                                tx_sr     <= {tx_sr[30:0], 1'b0};
                                spi_mosi  <= tx_sr[30];
                                bits_left <= bits_left - 16'd1;
                                state     <= ST_LOW;
                            end
                        end else begin
                            spi_mosi <= 1'b0;
                            if (burst_bit == 5'd0) begin
                                fifo_word       <= rx_sr[23:0];
                                fifo_word_valid <= 1'b1;
                                if (words_left <= 10'd1)
                                    state <= ST_TRAIL;
                                else begin
                                    words_left <= words_left - 10'd1;
                                    burst_bit  <= 5'd23;
                                    rx_sr      <= 32'd0;
                                    state      <= ST_LOW;
                                end
                            end else begin
                                burst_bit <= burst_bit - 5'd1;
                                state     <= ST_LOW;
                            end
                        end
                    end else
                        div <= div + 3'd1;
                end

                ST_TRAIL: begin
                    spi_sclk <= 1'b0;
                    if (div == HALF) begin
                        spi_cs_n <= 1'b1;
                        div      <= 3'd0;
                        state    <= ST_DONE;
                    end else
                        div <= div + 3'd1;
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
