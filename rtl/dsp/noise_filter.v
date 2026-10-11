`timescale 1ns / 1ps
// Noise filter for the 64-bin clutter-subtracted range profile.
//
// A baseball is 7.3 cm across. Range bins are 2.727 cm, so the ball
// covers about three bins. The specular return is usually one bin; FFT
// spread can reach four. Wider than that is a larger object.
//
// 1. Nearest local maximum in BIN_LO..BIN_HI at or above FLOOR.
// 2. CA-CFAR: 2 guard bins and 4 reference bins each side.
//    Threshold = 4 * mean(reference) = (sum of 8 refs) / 2.
// 3. Extent: -6 dB width (bins >= peak/4) must be 1..4 and must stop
//    before +/-3, so the run is closed inside a baseball-sized window.
// 4. Flying gate: report the hit only when |speed| is in
//    [FLY_MIN, FLY_MAX] cm/s. One bin per ~1.5 ms frame is ~2000 cm/s,
//    which is a thrown baseball. Zero speed is stationary clutter.
//
// mag is the profile word addressed by rd_addr on the previous clock
// (the parent registers work[rd_addr]). The scan uses issue / load / take.
module noise_filter #(
    parameter [7:0]  BIN_LO    = 8'd15,
    parameter [7:0]  BIN_HI    = 8'd37,
    parameter [31:0] FLOOR     = 32'd4096,
    parameter [3:0]  WIDTH_MIN = 4'd1,
    parameter [3:0]  WIDTH_MAX = 4'd4,
    parameter [15:0] FLY_MIN   = 16'd800,
    parameter [15:0] FLY_MAX   = 16'd6000
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire [31:0]        mag,
    output reg  [7:0]         rd_addr,
    output reg                done,
    output reg                hit,
    output reg  [7:0]         peak_bin,
    input  wire               det_pulse,
    input  wire               det_no_target,
    input  wire               speed_valid,
    input  wire signed [15:0] speed_cms,
    (* mark_debug = "true" *) output reg gated_no_target
);
    localparam S_IDLE  = 3'd0;
    localparam S_ISSUE = 3'd1;
    localparam S_LOAD  = 3'd2;
    localparam S_TAKE  = 3'd3;
    localparam S_ADV   = 3'd4;

    reg [2:0]  st;
    reg [3:0]  step;
    reg [7:0]  k;
    reg [31:0] left_m, cut_m, right_m;
    reg [31:0] mm3, mm2, mp2;
    reg [34:0] nsum;

    wire [15:0] spd_u   = speed_cms;
    wire [15:0] spd_abs = spd_u[15] ? (~spd_u + 16'd1) : spd_u;
    wire        fly_now = (spd_abs >= FLY_MIN) && (spd_abs <= FLY_MAX);

    wire [31:0] qthr = cut_m >> 2;
    wire        l1   = (left_m  >= qthr);
    wire        l2   = l1 && (mm2 >= qthr);
    wire        l3   = l2 && (mm3 >= qthr);
    wire        r1   = (right_m >= qthr);
    wire        r2   = r1 && (mp2 >= qthr);
    wire        r3   = r2 && (mag >= qthr);
    wire [3:0]  wid  = 4'd1 + {3'd0, l1} + {3'd0, l2} + {3'd0, l3}
                            + {3'd0, r1} + {3'd0, r2} + {3'd0, r3};
    wire        closed  = (mm3 < qthr) && (mag < qthr);
    wire        wide_ok = (wid >= WIDTH_MIN) && (wid <= WIDTH_MAX) && closed;

    wire [34:0] n_all   = nsum + {3'b0, mag};
    wire [34:0] cthr    = n_all >> 1;
    wire        cfar_ok = ({3'b0, cut_m} >= cthr);

    function [7:0] bin_at;
        input [7:0] base;
        input [3:0] stpv;
        begin
            case (stpv)
                4'd0:  bin_at = base - 8'd1;
                4'd1:  bin_at = base;
                4'd2:  bin_at = base + 8'd1;
                4'd3:  bin_at = base - 8'd3;
                4'd4:  bin_at = base - 8'd2;
                4'd5:  bin_at = base + 8'd2;
                4'd6:  bin_at = base + 8'd3;
                4'd7:  bin_at = base - 8'd6;
                4'd8:  bin_at = base - 8'd5;
                4'd9:  bin_at = base - 8'd4;
                4'd10: bin_at = base - 8'd3;
                4'd11: bin_at = base + 8'd3;
                4'd12: bin_at = base + 8'd4;
                4'd13: bin_at = base + 8'd5;
                4'd14: bin_at = base + 8'd6;
                default: bin_at = base;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            st               <= S_IDLE;
            step             <= 4'd0;
            k                <= BIN_LO;
            rd_addr          <= 8'd0;
            done             <= 1'b0;
            hit              <= 1'b0;
            peak_bin         <= 8'd0;
            gated_no_target  <= 1'b1;
            left_m           <= 32'd0;
            cut_m            <= 32'd0;
            right_m          <= 32'd0;
            mm3              <= 32'd0;
            mm2              <= 32'd0;
            mp2              <= 32'd0;
            nsum             <= 35'd0;
        end else begin
            done <= 1'b0;
            if (det_pulse)
                gated_no_target <= 1'b1;
            if (speed_valid)
                gated_no_target <= det_no_target || !fly_now;

            case (st)
                S_IDLE: begin
                    if (start) begin
                        k    <= BIN_LO;
                        step <= 4'd0;
                        hit  <= 1'b0;
                        st   <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    rd_addr <= bin_at(k, step);
                    st      <= S_LOAD;
                end

                // Parent captures work[rd_addr] on this edge.
                S_LOAD: st <= S_TAKE;

                S_TAKE: begin
                    case (step)
                        4'd0: left_m  <= mag;
                        4'd1: cut_m   <= mag;
                        4'd2: right_m <= mag;
                        4'd3: mm3     <= mag;
                        4'd4: mm2     <= mag;
                        4'd5: mp2     <= mag;
                        default: ;
                    endcase

                    if (step < 4'd2) begin
                        step <= step + 4'd1;
                        st   <= S_ISSUE;
                    end else if (step == 4'd2) begin
                        if ((cut_m >= left_m) && (cut_m >= mag) &&
                            (cut_m >= FLOOR)) begin
                            step <= 4'd3;
                            st   <= S_ISSUE;
                        end else
                            st <= S_ADV;
                    end else if (step < 4'd6) begin
                        step <= step + 4'd1;
                        st   <= S_ISSUE;
                    end else if (step == 4'd6) begin
                        if (wide_ok) begin
                            nsum <= 35'd0;
                            step <= 4'd7;
                            st   <= S_ISSUE;
                        end else
                            st <= S_ADV;
                    end else if (step < 4'd14) begin
                        nsum <= nsum + {3'b0, mag};
                        step <= step + 4'd1;
                        st   <= S_ISSUE;
                    end else if (cfar_ok) begin
                        hit      <= 1'b1;
                        peak_bin <= k;
                        done     <= 1'b1;
                        st       <= S_IDLE;
                    end else
                        st <= S_ADV;
                end

                S_ADV: begin
                    if (k >= BIN_HI) begin
                        hit  <= 1'b0;
                        done <= 1'b1;
                        st   <= S_IDLE;
                    end else begin
                        k    <= k + 8'd1;
                        step <= 4'd0;
                        st   <= S_ISSUE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
