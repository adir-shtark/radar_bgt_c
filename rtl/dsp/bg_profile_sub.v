`timescale 1ns / 1ps
// Empty-room baseline subtract for a 64-bin NCI range profile.
module bg_profile_sub #(
    parameter integer CAL_FRAMES = 8
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        cal_mode,
    input  wire [31:0] mag_in,
    input  wire [7:0]  idx_in,
    input  wire        valid_in,
    input  wire        last_in,
    (* mark_debug = "true" *) output reg  [31:0] mag_out,
    (* mark_debug = "true" *) output reg  [7:0]  idx_out,
    (* mark_debug = "true" *) output reg         valid_out,
    (* mark_debug = "true" *) output reg         last_out,
    (* mark_debug = "true" *) output reg         cal_active
);
    (* ram_style = "block" *) reg [31:0] baseline [0:63];
    (* ram_style = "block" *) reg [39:0] acc      [0:63];
    reg [3:0]  cal_cnt;
    reg        cal_run;
    reg        cal_mode_d;

    wire [5:0] a = idx_in[5:0];
    wire [39:0] acc_n = acc[a] + {8'd0, mag_in};
    wire [31:0] base_q = baseline[a];
    wire [31:0] sub    = (mag_in > base_q) ? (mag_in - base_q) : 32'd0;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            mag_out    <= 32'd0;
            idx_out    <= 8'd0;
            valid_out  <= 1'b0;
            last_out   <= 1'b0;
            cal_active <= 1'b0;
            cal_cnt    <= 4'd0;
            cal_run    <= 1'b0;
            cal_mode_d <= 1'b0;
            for (i = 0; i < 64; i = i + 1) begin
                baseline[i] <= 32'd0;
                acc[i]      <= 40'd0;
            end
        end else begin
            valid_out  <= 1'b0;
            last_out   <= 1'b0;
            cal_mode_d <= cal_mode;

            if (cal_mode && !cal_mode_d) begin
                cal_run    <= 1'b1;
                cal_cnt    <= 4'd0;
                cal_active <= 1'b1;
            end

            if (valid_in) begin
                idx_out   <= idx_in;
                last_out  <= last_in;
                valid_out <= 1'b1;
                if (cal_run) begin
                    acc[a]     <= acc_n;
                    mag_out    <= 32'd0;
                    cal_active <= 1'b1;
                    if (cal_cnt == CAL_FRAMES[3:0] - 4'd1)
                        baseline[a] <= acc_n[39:3];
                    if (last_in) begin
                        if (cal_cnt == CAL_FRAMES[3:0] - 4'd1) begin
                            cal_run    <= 1'b0;
                            cal_active <= 1'b0;
                        end else
                            cal_cnt <= cal_cnt + 4'd1;
                    end
                end else begin
                    mag_out    <= cal_mode ? 32'd0 : sub;
                    cal_active <= 1'b0;
                end
            end
        end
    end
endmodule
