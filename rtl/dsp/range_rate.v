`timescale 1ns / 1ps
// Inter-frame range-rate: speed_cms = (R_n - R_{n-1}) * 1e6 / dt_us.
module range_rate #(
    parameter [15:0] MAX_GAP_US = 16'd10000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_valid,
    input  wire        no_target,
    input  wire [15:0] distance_cm,
    (* mark_debug = "true" *) output reg signed [15:0] speed_cms,
    (* mark_debug = "true" *) output reg                speed_valid
);
    localparam S_IDLE = 3'd0;
    localparam S_MULA = 3'd1;
    localparam S_MULM = 3'd2;
    localparam S_MULP = 3'd3;
    localparam S_DIV  = 3'd4;
    localparam S_DONE = 3'd5;

    reg [6:0]  div100;
    reg [31:0] us_cnt;
    reg [31:0] t_prev;
    reg [15:0] cm_prev;
    reg        have;
    reg [2:0]  state;
    reg [15:0] delta;
    reg [15:0] mul_a;
    reg [35:0] prod;
    reg [31:0] num;
    reg [31:0] den;
    reg [31:0] quot;
    reg [31:0] rem;
    reg [4:0]  bit_i;
    reg        neg;
    wire [32:0] rem_try = {rem, num[bit_i]};

    always @(posedge clk) begin
        if (rst) begin
            div100      <= 7'd0;
            us_cnt      <= 32'd0;
            t_prev      <= 32'd0;
            cm_prev     <= 16'd0;
            have        <= 1'b0;
            state       <= S_IDLE;
            speed_cms   <= 16'd0;
            speed_valid <= 1'b0;
            delta       <= 16'd0;
            mul_a       <= 16'd0;
            prod        <= 36'd0;
            num         <= 32'd0;
            den         <= 32'd0;
            quot        <= 32'd0;
            rem         <= 32'd0;
            bit_i       <= 5'd31;
            neg         <= 1'b0;
        end else begin
            speed_valid <= 1'b0;
            if (div100 == 7'd99) begin
                div100 <= 7'd0;
                us_cnt <= us_cnt + 32'd1;
            end else
                div100 <= div100 + 7'd1;

            case (state)
                S_IDLE: begin
                    if (sample_valid) begin
                        if (no_target) begin
                            have        <= 1'b0;
                            speed_cms   <= 16'sd0;
                        end else if (have &&
                                    ((us_cnt - t_prev) != 32'd0) &&
                                    ((us_cnt - t_prev) <= {16'd0, MAX_GAP_US})) begin
                            if (distance_cm >= cm_prev) begin
                                neg   <= 1'b0;
                                delta <= distance_cm - cm_prev;
                            end else begin
                                neg   <= 1'b1;
                                delta <= cm_prev - distance_cm;
                            end
                            den     <= us_cnt - t_prev;
                            rem     <= 32'd0;
                            quot    <= 32'd0;
                            bit_i   <= 5'd31;
                            state   <= S_MULA;
                            cm_prev <= distance_cm;
                            t_prev  <= us_cnt;
                        end else begin
                            have    <= 1'b1;
                            cm_prev <= distance_cm;
                            t_prev  <= us_cnt;
                        end
                    end
                end

                // delta * 1_000_000 is registered into the DSP (A then M then P).
                S_MULA: begin
                    mul_a <= delta;
                    state <= S_MULM;
                end
                S_MULM: begin
                    prod  <= mul_a * 20'd1000000;
                    state <= S_MULP;
                end
                S_MULP: begin
                    num   <= prod[31:0];
                    state <= S_DIV;
                end

                S_DIV: begin
                    if (rem_try >= {1'b0, den}) begin
                        rem          <= rem_try[31:0] - den;
                        quot[bit_i]  <= 1'b1;
                    end else begin
                        rem          <= rem_try[31:0];
                        quot[bit_i]  <= 1'b0;
                    end
                    if (bit_i == 5'd0)
                        state <= S_DONE;
                    else
                        bit_i <= bit_i - 5'd1;
                end

                S_DONE: begin
                    if (quot > 32'd32767)
                        speed_cms <= neg ? -16'sd32767 : 16'sd32767;
                    else if (neg)
                        speed_cms <= -$signed(quot[15:0]);
                    else
                        speed_cms <= quot[15:0];
                    speed_valid <= 1'b1;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
