`timescale 1ns / 1ps
module bgt60_ctrl #(
    parameter FAST_SIM = 0
) (
    input  wire        clk,
    input  wire        rst_sync,
    input  wire        sw_reset,
    (* mark_debug = "true" *) output reg         spi_start,
    (* mark_debug = "true" *) output reg  [1:0]  spi_cmd,
    (* mark_debug = "true" *) output reg  [6:0]  spi_addr,
    (* mark_debug = "true" *) output reg  [23:0] spi_wdata,
    (* mark_debug = "true" *) output wire [9:0]  spi_burst_n,
    input  wire        spi_busy,
    input  wire        spi_done,
    input  wire [23:0] spi_rdata,
    input  wire [7:0]  spi_gsr0,
    input  wire        spi_fifo_valid,
    input  wire [23:0] spi_fifo_word,
    (* mark_debug = "true" *) output reg         spi_reset_n,
    (* mark_debug = "true" *) output reg         chirp_start,
    input  wire        chirp_done,
    input  wire        sample_valid,
    input  wire [7:0]  sample_idx,
    input  wire [11:0] rx1,
    input  wire [11:0] rx2,
    input  wire [11:0] rx3,
    (* mark_debug = "true" *) output reg  [31:0] fft_s_tdata,
    (* mark_debug = "true" *) output reg         fft_s_tvalid,
    (* mark_debug = "true" *) output reg         fft_s_tlast,
    input  wire        fft_s_tready,
    input  wire        dsp_done,
    (* mark_debug = "true" *) output reg         frame_clr,
    (* mark_debug = "true" *) output reg         error_flag,
    (* mark_debug = "true" *) output reg         overflow_err
);
    localparam CMD_WR = 2'd0, CMD_RD = 2'd1, CMD_BURST = 2'd2;
    localparam [23:0] MAIN_SWR  = 24'h7869C2;
    localparam [23:0] MAIN_FSM  = 24'h7869C4;
    localparam [23:0] MAIN_STRT = 24'h7869C1;
    localparam [19:0] T_1MS     = FAST_SIM ? 20'd40 : 20'd100_000;
    localparam [19:0] T_SOFT    = FAST_SIM ? 20'd400 : 20'd1_000_000;

    localparam S_WAIT   = 5'd0;
    localparam S_HW0    = 5'd1;
    localparam S_HW1    = 5'd2;
    localparam S_HW2    = 5'd3;
    localparam S_SWR    = 5'd4;
    localparam S_SWD    = 5'd5;
    localparam S_SWP    = 5'd6;
    localparam S_SWW    = 5'd7;
    localparam S_CID    = 5'd8;
    localparam S_CIDD   = 5'd9;
    localparam S_CFG    = 5'd10;
    localparam S_CFGD   = 5'd11;
    localparam S_START  = 5'd12;
    localparam S_STRD   = 5'd13;
    localparam S_POLL   = 5'd14;
    localparam S_POLLD  = 5'd15;
    localparam S_BURST  = 5'd16;
    localparam S_BURD   = 5'd17;
    localparam S_FEED   = 5'd18;
    localparam S_FWAIT  = 5'd19;
    localparam S_DSP    = 5'd20;
    localparam S_FRST   = 5'd21;
    localparam S_FRSTD  = 5'd22;
    localparam S_ERR    = 5'd31;

    assign spi_burst_n = 10'd192;

    reg [4:0]  state;
    reg [19:0] tmr;
    reg [4:0]  rom_idx;
    wire [6:0]  rom_addr;
    wire [23:0] rom_data;
    wire        rom_last;
    reg [1:0]  rx_sel;
    reg [7:0]  feed_idx;
    reg        dsp_seen;

    reg [11:0] mem1 [0:127];
    reg [11:0] mem2 [0:127];
    reg [11:0] mem3 [0:127];

    bgt60_reg_rom u_rom (
        .idx  (rom_idx),
        .addr (rom_addr),
        .data (rom_data),
        .last (rom_last)
    );

    wire [11:0] feed_raw = (rx_sel == 2'd0) ? mem1[feed_idx[6:0]] :
                           (rx_sel == 2'd1) ? mem2[feed_idx[6:0]] : mem3[feed_idx[6:0]];
    wire signed [15:0] feed_s = $signed({4'b0, feed_raw}) - 16'sd2048;

    always @(posedge clk) begin
        if (sample_valid) begin
            mem1[sample_idx[6:0]] <= rx1;
            mem2[sample_idx[6:0]] <= rx2;
            mem3[sample_idx[6:0]] <= rx3;
        end
    end

    always @(posedge clk) begin
        if (rst_sync) begin
            state        <= S_WAIT;
            spi_start    <= 1'b0;
            spi_cmd      <= CMD_WR;
            spi_addr     <= 7'd0;
            spi_wdata    <= 24'd0;
            spi_reset_n  <= 1'b0;
            chirp_start  <= 1'b0;
            fft_s_tdata  <= 32'd0;
            fft_s_tvalid <= 1'b0;
            fft_s_tlast  <= 1'b0;
            frame_clr    <= 1'b1;
            error_flag   <= 1'b0;
            overflow_err <= 1'b0;
            tmr          <= 20'd0;
            rom_idx      <= 5'd0;
            rx_sel       <= 2'd0;
            feed_idx     <= 8'd0;
            dsp_seen     <= 1'b0;
        end else begin
            spi_start   <= 1'b0;
            chirp_start <= 1'b0;
            frame_clr   <= 1'b0;
            if (dsp_done)
                dsp_seen <= 1'b1;

            if (sw_reset)
                state <= S_WAIT;

            case (state)
                S_WAIT: begin
                    spi_reset_n  <= 1'b0;
                    fft_s_tvalid <= 1'b0;
                    if (!sw_reset) begin
                        spi_reset_n <= 1'b1;
                        tmr         <= T_1MS;
                        state       <= S_HW0;
                    end
                end
                S_HW0: begin
                    spi_reset_n <= 1'b1;
                    if (tmr == 20'd0) begin
                        spi_reset_n <= 1'b0;
                        tmr         <= T_1MS;
                        state       <= S_HW1;
                    end else
                        tmr <= tmr - 20'd1;
                end
                S_HW1: begin
                    spi_reset_n <= 1'b0;
                    if (tmr == 20'd0) begin
                        spi_reset_n <= 1'b1;
                        tmr         <= T_1MS;
                        state       <= S_HW2;
                    end else
                        tmr <= tmr - 20'd1;
                end
                S_HW2: begin
                    spi_reset_n <= 1'b1;
                    if (tmr == 20'd0)
                        state <= S_SWR;
                    else
                        tmr <= tmr - 20'd1;
                end
                S_SWR: begin
                    if (!spi_busy) begin
                        spi_cmd   <= CMD_WR;
                        spi_addr  <= 7'h00;
                        spi_wdata <= MAIN_SWR;
                        spi_start <= 1'b1;
                        tmr       <= T_SOFT;
                        state     <= S_SWD;
                    end
                end
                S_SWD: if (spi_done) state <= S_SWP;
                S_SWP: begin
                    if (!spi_busy) begin
                        spi_cmd   <= CMD_RD;
                        spi_addr  <= 7'h00;
                        spi_wdata <= 24'd0;
                        spi_start <= 1'b1;
                        state     <= S_SWW;
                    end
                end
                S_SWW: begin
                    if (spi_done) begin
                        if (spi_rdata[3:1] == 3'b000) begin
                            tmr   <= T_1MS;
                            state <= S_CID;
                        end else if (tmr == 20'd0)
                            state <= S_ERR;
                        else begin
                            tmr   <= tmr - 20'd1;
                            state <= S_SWP;
                        end
                    end
                end
                S_CID: begin
                    if (tmr != 20'd0)
                        tmr <= tmr - 20'd1;
                    else if (!spi_busy) begin
                        spi_cmd   <= CMD_RD;
                        spi_addr  <= 7'h02;
                        spi_start <= 1'b1;
                        state     <= S_CIDD;
                    end
                end
                S_CIDD: begin
                    if (spi_done) begin
                        if ((spi_rdata[7:0] != 8'd3) || (spi_rdata[15:8] != 8'd3))
                            state <= S_ERR;
                        else begin
                            rom_idx <= 5'd0;
                            state   <= S_CFG;
                        end
                    end
                end
                S_CFG: begin
                    if (!spi_busy) begin
                        spi_cmd   <= CMD_WR;
                        spi_addr  <= rom_addr;
                        spi_wdata <= rom_data;
                        spi_start <= 1'b1;
                        state     <= S_CFGD;
                    end
                end
                S_CFGD: begin
                    if (spi_done) begin
                        if (rom_last)
                            state <= S_START;
                        else begin
                            rom_idx <= rom_idx + 5'd1;
                            state   <= S_CFG;
                        end
                    end
                end
                S_START: begin
                    frame_clr <= 1'b1;
                    dsp_seen  <= 1'b0;
                    if (!spi_busy) begin
                        spi_cmd   <= CMD_WR;
                        spi_addr  <= 7'h00;
                        spi_wdata <= MAIN_STRT;
                        spi_start <= 1'b1;
                        state     <= S_STRD;
                    end
                end
                S_STRD: if (spi_done) state <= S_POLL;
                S_POLL: begin
                    if (!spi_busy) begin
                        spi_cmd   <= CMD_RD;
                        spi_addr  <= 7'h5F;
                        spi_start <= 1'b1;
                        state     <= S_POLLD;
                    end
                end
                S_POLLD: begin
                    if (spi_done) begin
                        if (spi_rdata[23])
                            overflow_err <= 1'b1;
                        if (spi_rdata[21])
                            state <= S_BURST;
                        else
                            state <= S_POLL;
                    end
                end
                S_BURST: begin
                    if (!spi_busy) begin
                        chirp_start <= 1'b1;
                        spi_cmd     <= CMD_BURST;
                        spi_start   <= 1'b1;
                        state       <= S_BURD;
                    end
                end
                S_BURD: begin
                    if (spi_done) begin
                        rx_sel   <= 2'd0;
                        feed_idx <= 8'd0;
                        state    <= S_FEED;
                    end
                end
                S_FEED: begin
                    fft_s_tdata  <= {16'd0, feed_s};
                    fft_s_tlast  <= (feed_idx == 8'd127);
                    if (!fft_s_tvalid) begin
                        fft_s_tvalid <= 1'b1;
                    end else if (fft_s_tready) begin
                        if (feed_idx == 8'd127) begin
                            fft_s_tvalid <= 1'b0;
                            fft_s_tlast  <= 1'b0;
                            state        <= S_FWAIT;
                        end else
                            feed_idx <= feed_idx + 8'd1;
                    end
                end
                S_FWAIT: begin
                    if (fft_s_tready) begin
                        if (rx_sel == 2'd2)
                            state <= S_DSP;
                        else begin
                            rx_sel   <= rx_sel + 2'd1;
                            feed_idx <= 8'd0;
                            state    <= S_FEED;
                        end
                    end
                end
                S_DSP: begin
                    if (dsp_seen && !spi_busy)
                        state <= S_FRST;
                end
                S_FRST: begin
                    if (!spi_busy) begin
                        spi_cmd   <= CMD_WR;
                        spi_addr  <= 7'h00;
                        spi_wdata <= MAIN_FSM;
                        spi_start <= 1'b1;
                        state     <= S_FRSTD;
                    end
                end
                S_FRSTD: if (spi_done) state <= S_START;
                S_ERR: begin
                    error_flag   <= 1'b1;
                    fft_s_tvalid <= 1'b0;
                end
                default: state <= S_WAIT;
            endcase
        end
    end
endmodule
