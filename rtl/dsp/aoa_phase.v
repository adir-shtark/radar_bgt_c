`timescale 1ns / 1ps
// Azimuth from RX1/RX3 phase: θ = arcsin(Δφ/π) with d = λ/2.
// The degree scale (dphi * 300 / 1440) is pipelined. A single-cycle
// 32-bit multiply/divide does not meet 100 MHz (routed WNS -23.8 ns).
module aoa_phase (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        valid_iq,
    input  wire signed [15:0] re1,
    input  wire signed [15:0] im1,
    input  wire signed [15:0] re3,
    input  wire signed [15:0] im3,
    (* mark_debug = "true" *) output reg         done,
    (* mark_debug = "true" *) output reg signed [15:0] angle_x10
);
    localparam S_IDLE = 4'd0;
    localparam S_AT1  = 4'd1;
    localparam S_AT3  = 4'd2;
    localparam S_OUT  = 4'd3;
    localparam S_WRAP = 4'd4;
    localparam S_ABS  = 4'd5;
    localparam S_MUL  = 4'd6;
    localparam S_PROD = 4'd7;
    localparam S_QMUL = 4'd8;
    localparam S_EMIT = 4'd9;

    function signed [15:0] atab;
        input [3:0] i;
        begin
            case (i)
                4'd0:  atab = 16'sd720;
                4'd1:  atab = 16'sd425;
                4'd2:  atab = 16'sd225;
                4'd3:  atab = 16'sd114;
                4'd4:  atab = 16'sd57;
                4'd5:  atab = 16'sd29;
                4'd6:  atab = 16'sd14;
                4'd7:  atab = 16'sd7;
                4'd8:  atab = 16'sd4;
                4'd9:  atab = 16'sd2;
                default: atab = 16'sd1;
            endcase
        end
    endfunction

    function signed [15:0] atan_axis;
        input signed [15:0] re;
        input signed [15:0] im;
        begin
            if (re == 16'sd0)
                atan_axis = (im >= 0) ? 16'sd1440 : -16'sd1440;
            else if (im == 16'sd0)
                atan_axis = (re >= 0) ? 16'sd0 : 16'sd2880;
            else
                atan_axis = 16'sd0;
        end
    endfunction

    function axis_done;
        input signed [15:0] re;
        input signed [15:0] im;
        begin
            axis_done = (re == 16'sd0) || (im == 16'sd0);
        end
    endfunction

    reg [3:0]  state;
    reg signed [15:0] a1, a3;
    reg signed [15:0] re_w, im_w;
    reg signed [31:0] cx, cy;
    reg signed [15:0] cz;
    reg [3:0]  ci;
    reg        busy;
    reg        use_cz;
    reg signed [15:0] diff, dphi_w;
    reg        neg_a;
    reg [15:0] abs_a, mul_a;
    reg [31:0] prod, qmul;

    wire signed [31:0] cx_sh = cx >>> ci;
    wire signed [31:0] cy_sh = cy >>> ci;
    // qmul holds (floor(abs(dphi)*300/32) * 11651). >> 19 is floor(/45),
    // and floor(floor(N>>5)/45) == floor(N/1440) for N >= 0.
    wire [15:0] ang_mag = {3'b0, qmul[31:19]};

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            done      <= 1'b0;
            angle_x10 <= 16'sd0;
            a1 <= 16'sd0; a3 <= 16'sd0;
            re_w <= 16'sd0; im_w <= 16'sd0;
            cx <= 32'sd0; cy <= 32'sd0; cz <= 16'sd0;
            ci <= 4'd0; busy <= 1'b0;
            use_cz <= 1'b0;
            diff <= 16'sd0; dphi_w <= 16'sd0;
            neg_a <= 1'b0;
            abs_a <= 16'd0; mul_a <= 16'd0;
            prod <= 32'd0; qmul <= 32'd0;
        end else begin
            done <= 1'b0;
            if (busy) begin
                if (cy > 0) begin
                    cx <= cx + cy_sh;
                    cy <= cy - cx_sh;
                    cz <= cz + atab(ci);
                end else if (cy < 0) begin
                    cx <= cx - cy_sh;
                    cy <= cy + cx_sh;
                    cz <= cz - atab(ci);
                end
                if (ci == 4'd15)
                    busy <= 1'b0;
                else
                    ci <= ci + 4'd1;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (start) begin
                            if (!valid_iq) begin
                                angle_x10 <= 16'sd0;
                                done      <= 1'b1;
                            end else if (axis_done(re1, im1)) begin
                                a1    <= atan_axis(re1, im1);
                                state <= S_AT3;
                            end else begin
                                re_w  <= re1;
                                im_w  <= im1;
                                cx    <= (re1 < 0) ? -$signed({{16{re1[15]}}, re1}) : {{16{re1[15]}}, re1};
                                cy    <= (re1 < 0) ? -$signed({{16{im1[15]}}, im1}) : {{16{im1[15]}}, im1};
                                cz    <= (re1 < 0) ? ((im1 >= 0) ? -16'sd2880 : 16'sd2880) : 16'sd0;
                                ci    <= 4'd0;
                                busy  <= 1'b1;
                                state <= S_AT1;
                            end
                        end
                    end
                    S_AT1: begin
                        a1    <= cz;
                        state <= S_AT3;
                    end
                    S_AT3: begin
                        if (axis_done(re3, im3)) begin
                            a3     <= atan_axis(re3, im3);
                            use_cz <= 1'b0;
                            state  <= S_OUT;
                        end else begin
                            cx     <= (re3 < 0) ? -$signed({{16{re3[15]}}, re3}) : {{16{re3[15]}}, re3};
                            cy     <= (re3 < 0) ? -$signed({{16{im3[15]}}, im3}) : {{16{im3[15]}}, im3};
                            cz     <= (re3 < 0) ? ((im3 >= 0) ? -16'sd2880 : 16'sd2880) : 16'sd0;
                            ci     <= 4'd0;
                            busy   <= 1'b1;
                            use_cz <= 1'b1;
                            state  <= S_OUT;
                        end
                    end
                    // a3/cz were captured on the previous edge. Do not re-read live I/Q.
                    S_OUT: begin
                        diff  <= (use_cz ? cz : a3) - a1;
                        state <= S_WRAP;
                    end
                    S_WRAP: begin
                        if (diff > 16'sd2880)
                            dphi_w <= diff - 16'sd5760;
                        else if (diff < -16'sd2880)
                            dphi_w <= diff + 16'sd5760;
                        else
                            dphi_w <= diff;
                        state <= S_ABS;
                    end
                    S_ABS: begin
                        neg_a <= dphi_w[15];
                        abs_a <= dphi_w[15] ? -dphi_w : dphi_w;
                        state <= S_MUL;
                    end
                    S_MUL: begin
                        mul_a <= abs_a;
                        state <= S_PROD;
                    end
                    S_PROD: begin
                        prod  <= mul_a * 16'd300;
                        state <= S_QMUL;
                    end
                    S_QMUL: begin
                        qmul  <= prod[20:5] * 16'd11651;
                        state <= S_EMIT;
                    end
                    S_EMIT: begin
                        angle_x10 <= neg_a ? -$signed(ang_mag) : $signed(ang_mag);
                        done      <= 1'b1;
                        state     <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
