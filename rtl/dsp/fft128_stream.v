`timescale 1ns / 1ps
// 128-point scaled radix-2 DIT FFT, AXI-Stream {imag[15:0], real[15:0]}.
module fft128_stream (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast,
    (* mark_debug = "true" *) output reg         s_tready,
    (* mark_debug = "true" *) output reg  [31:0] m_tdata,
    (* mark_debug = "true" *) output reg         m_tvalid,
    (* mark_debug = "true" *) output reg         m_tlast,
    input  wire        m_tready
);
    `include "twiddle_q15_128.vh"

    localparam ST_LOAD = 2'd0;
    localparam ST_FFT  = 2'd1;
    localparam ST_UNLD = 2'd2;

    function [6:0] bitrev;
        input [6:0] x;
        integer i;
        begin
            for (i = 0; i < 7; i = i + 1)
                bitrev[i] = x[6-i];
        end
    endfunction

    reg signed [15:0] mem_re [0:127];
    reg signed [15:0] mem_im [0:127];

    reg [1:0]  state;
    reg [6:0]  ld_idx;
    reg [2:0]  stage;
    reg [7:0]  k;
    reg [6:0]  j;
    reg        ph;
    reg [6:0]  ul_idx;

    reg signed [15:0] a_re, a_im, b_re, b_im;
    reg signed [15:0] wr, wi;
    reg [6:0]  addr_a, addr_b;

    wire signed [15:0] s_re = s_tdata[15:0];
    wire signed [15:0] s_im = s_tdata[31:16];

    wire [6:0] half  = 7'd1 << stage;
    wire [7:0] mspan = 8'd2 << stage;
    wire [6:0] twidx = j << (3'd6 - stage);

    wire signed [31:0] p_br_wr = b_re * wr;
    wire signed [31:0] p_bi_wi = b_im * wi;
    wire signed [31:0] p_br_wi = b_re * wi;
    wire signed [31:0] p_bi_wr = b_im * wr;

    wire signed [15:0] t_re = p_br_wr[30:15] - p_bi_wi[30:15];
    wire signed [15:0] t_im = p_br_wi[30:15] + p_bi_wr[30:15];

    wire signed [16:0] sum_re = $signed({a_re[15], a_re}) + $signed({t_re[15], t_re});
    wire signed [16:0] sum_im = $signed({a_im[15], a_im}) + $signed({t_im[15], t_im});
    wire signed [16:0] dif_re = $signed({a_re[15], a_re}) - $signed({t_re[15], t_re});
    wire signed [16:0] dif_im = $signed({a_im[15], a_im}) - $signed({t_im[15], t_im});

    always @(posedge clk) begin
        if (rst) begin
            state    <= ST_LOAD;
            s_tready <= 1'b1;
            m_tvalid <= 1'b0;
            m_tlast  <= 1'b0;
            m_tdata  <= 32'd0;
            ld_idx   <= 7'd0;
            stage    <= 3'd0;
            k        <= 8'd0;
            j        <= 7'd0;
            ph       <= 1'b0;
            ul_idx   <= 7'd0;
            a_re <= 16'd0; a_im <= 16'd0; b_re <= 16'd0; b_im <= 16'd0;
            wr <= 16'd0; wi <= 16'd0;
            addr_a <= 7'd0; addr_b <= 7'd0;
        end else begin
            case (state)
                ST_LOAD: begin
                    s_tready <= 1'b1;
                    m_tvalid <= 1'b0;
                    if (s_tvalid && s_tready) begin
                        mem_re[bitrev(ld_idx)] <= s_re;
                        mem_im[bitrev(ld_idx)] <= s_im;
                        if (ld_idx == 7'd127) begin
                            s_tready <= 1'b0;
                            state    <= ST_FFT;
                            stage    <= 3'd0;
                            k        <= 8'd0;
                            j        <= 7'd0;
                            ph       <= 1'b0;
                            ld_idx   <= 7'd0;
                        end else
                            ld_idx <= ld_idx + 7'd1;
                    end
                end

                ST_FFT: begin
                    s_tready <= 1'b0;
                    if (ph == 1'b0) begin
                        addr_a <= k[6:0] + j;
                        addr_b <= k[6:0] + j + half;
                        a_re   <= mem_re[k[6:0] + j];
                        a_im   <= mem_im[k[6:0] + j];
                        b_re   <= mem_re[k[6:0] + j + half];
                        b_im   <= mem_im[k[6:0] + j + half];
                        wr     <= tw_re(twidx);
                        wi     <= tw_im(twidx);
                        ph     <= 1'b1;
                    end else begin
                        mem_re[addr_a] <= sum_re[16:1];
                        mem_im[addr_a] <= sum_im[16:1];
                        mem_re[addr_b] <= dif_re[16:1];
                        mem_im[addr_b] <= dif_im[16:1];
                        ph <= 1'b0;
                        if (j + 7'd1 >= half) begin
                            j <= 7'd0;
                            if (k + mspan >= 8'd128) begin
                                k <= 8'd0;
                                if (stage == 3'd6) begin
                                    state  <= ST_UNLD;
                                    ul_idx <= 7'd0;
                                end else
                                    stage <= stage + 3'd1;
                            end else
                                k <= k + mspan;
                        end else
                            j <= j + 7'd1;
                    end
                end

                ST_UNLD: begin
                    if (!m_tvalid) begin
                        m_tdata  <= {mem_im[ul_idx], mem_re[ul_idx]};
                        m_tvalid <= 1'b1;
                        m_tlast  <= (ul_idx == 7'd127);
                    end else if (m_tready) begin
                        if (ul_idx == 7'd127) begin
                            m_tvalid <= 1'b0;
                            m_tlast  <= 1'b0;
                            ul_idx   <= 7'd0;
                            ld_idx   <= 7'd0;
                            s_tready <= 1'b1;
                            state    <= ST_LOAD;
                        end else begin
                            ul_idx   <= ul_idx + 7'd1;
                            m_tdata  <= {mem_im[ul_idx + 7'd1], mem_re[ul_idx + 7'd1]};
                            m_tlast  <= (ul_idx + 7'd1 == 7'd127);
                        end
                    end
                end

                default: state <= ST_LOAD;
            endcase
        end
    end
endmodule
