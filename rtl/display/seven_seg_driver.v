`timescale 1ns / 1ps
// Basys3 4-digit seven-segment, active-low an/seg. seg[0]=A .. seg[6]=G.
module seven_seg_driver (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] value,
    input  wire        blank,
    (* mark_debug = "true" *) output reg  [6:0]  seg,
    (* mark_debug = "true" *) output reg  [3:0]  an
);
    reg [16:0] div;
    reg [1:0]  digit_sel;
    reg [15:0] bin;
    reg [3:0]  bcd0, bcd1, bcd2, bcd3;
    integer i;

    always @* begin
        bin  = value;
        bcd0 = 4'd0; bcd1 = 4'd0; bcd2 = 4'd0; bcd3 = 4'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (bcd0 >= 4'd5) bcd0 = bcd0 + 4'd3;
            if (bcd1 >= 4'd5) bcd1 = bcd1 + 4'd3;
            if (bcd2 >= 4'd5) bcd2 = bcd2 + 4'd3;
            if (bcd3 >= 4'd5) bcd3 = bcd3 + 4'd3;
            {bcd3, bcd2, bcd1, bcd0, bin} = {bcd3, bcd2, bcd1, bcd0, bin} << 1;
        end
    end

    function [6:0] hex7;
        input [3:0] d;
        begin
            case (d)
                4'h0: hex7 = 7'b1000000;
                4'h1: hex7 = 7'b1111001;
                4'h2: hex7 = 7'b0100100;
                4'h3: hex7 = 7'b0110000;
                4'h4: hex7 = 7'b0011001;
                4'h5: hex7 = 7'b0010010;
                4'h6: hex7 = 7'b0000010;
                4'h7: hex7 = 7'b1111000;
                4'h8: hex7 = 7'b0000000;
                4'h9: hex7 = 7'b0010000;
                default: hex7 = 7'b1111111;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            div       <= 17'd0;
            digit_sel <= 2'd0;
            seg       <= 7'b1111111;
            an        <= 4'b1111;
        end else begin
            div <= div + 17'd1;
            if (div == 17'd0)
                digit_sel <= digit_sel + 2'd1;
            case (digit_sel)
                2'd0: begin an <= 4'b1110; seg <= blank ? 7'b0111111 : hex7(bcd0); end
                2'd1: begin an <= 4'b1101; seg <= blank ? 7'b0111111 : hex7(bcd1); end
                2'd2: begin an <= 4'b1011; seg <= blank ? 7'b0111111 : hex7(bcd2); end
                default: begin an <= 4'b0111; seg <= blank ? 7'b0111111 : hex7(bcd3); end
            endcase
        end
    end
endmodule
