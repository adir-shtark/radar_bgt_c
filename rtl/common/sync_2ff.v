`timescale 1ns / 1ps
module sync_2ff (
    input  wire clk,
    input  wire rst,
    input  wire d,
    output wire q
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] s;
    always @(posedge clk) begin
        if (rst)
            s <= 2'b00;
        else
            s <= {s[0], d};
    end
    assign q = s[1];
endmodule
