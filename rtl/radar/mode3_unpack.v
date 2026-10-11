`timescale 1ns / 1ps
// Datasheet 5.2 Mode-3 FIFO unpack: 192 words → 128 time samples × 3 RX.
module mode3_unpack #(
    parameter integer N_SAMP = 128
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        chirp_start,
    input  wire [23:0] word,
    input  wire        word_valid,
    (* mark_debug = "true" *) output reg  [11:0] rx1,
    (* mark_debug = "true" *) output reg  [11:0] rx2,
    (* mark_debug = "true" *) output reg  [11:0] rx3,
    (* mark_debug = "true" *) output reg  [7:0]  sample_idx,
    (* mark_debug = "true" *) output reg         sample_valid,
    (* mark_debug = "true" *) output reg         chirp_done
);
    localparam [7:0] LAST_EVEN = N_SAMP[7:0] - 8'd2;

    reg [1:0]  slot;
    reg [11:0] hold_rx2;
    reg [11:0] hold_odd_rx1;
    reg [7:0]  idx;
    reg        active;

    always @(posedge clk) begin
        if (rst) begin
            slot         <= 2'd0;
            idx          <= 8'd0;
            active       <= 1'b0;
            sample_valid <= 1'b0;
            chirp_done   <= 1'b0;
            rx1          <= 12'd0;
            rx2          <= 12'd0;
            rx3          <= 12'd0;
            sample_idx   <= 8'd0;
            hold_rx2     <= 12'd0;
            hold_odd_rx1 <= 12'd0;
        end else begin
            sample_valid <= 1'b0;
            chirp_done   <= 1'b0;

            if (chirp_start) begin
                slot   <= 2'd0;
                idx    <= 8'd0;
                active <= 1'b1;
            end else if (active && word_valid) begin
                case (slot)
                    2'd0: begin
                        rx1      <= word[23:12];
                        hold_rx2 <= word[11:0];
                        slot     <= 2'd1;
                    end
                    2'd1: begin
                        rx3          <= word[23:12];
                        rx2          <= hold_rx2;
                        sample_idx   <= idx;
                        sample_valid <= 1'b1;
                        hold_odd_rx1 <= word[11:0];
                        slot         <= 2'd2;
                    end
                    default: begin
                        rx1          <= hold_odd_rx1;
                        rx2          <= word[23:12];
                        rx3          <= word[11:0];
                        sample_idx   <= idx + 8'd1;
                        sample_valid <= 1'b1;
                        slot         <= 2'd0;
                        if (idx >= LAST_EVEN) begin
                            active     <= 1'b0;
                            chirp_done <= 1'b1;
                            idx        <= 8'd0;
                        end else
                            idx <= idx + 8'd2;
                    end
                endcase
            end
        end
    end
endmodule
