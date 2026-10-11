`timescale 1ns / 1ps
module uart_tx #(
    parameter integer CLKS_PER_BIT = 868
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       start,
    (* mark_debug = "true" *) output reg busy,
    (* mark_debug = "true" *) output reg tx
);
    localparam S_IDLE = 2'd0;
    localparam S_STRT = 2'd1;
    localparam S_DATA = 2'd2;
    localparam S_STOP = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            busy    <= 1'b0;
            tx      <= 1'b1;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx      <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 16'd0;
                    if (start) begin
                        shift   <= data;
                        busy    <= 1'b1;
                        tx      <= 1'b0;
                        state   <= S_STRT;
                    end
                end
                S_STRT: begin
                    busy <= 1'b1;
                    tx   <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_DATA: begin
                    tx <= shift[0];
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        shift   <= {1'b0, shift[7:1]};
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        busy    <= 1'b0;
                        state   <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
