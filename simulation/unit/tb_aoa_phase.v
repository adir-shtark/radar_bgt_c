`timescale 1ns / 1ps
module tb_aoa_phase;
    reg clk, rst, start, valid_iq;
    reg signed [15:0] re1, im1, re3, im3;
    wire done;
    wire signed [15:0] angle_x10;

    aoa_phase dut (
        .clk(clk), .rst(rst), .start(start), .valid_iq(valid_iq),
        .re1(re1), .im1(im1), .re3(re3), .im3(im3),
        .done(done), .angle_x10(angle_x10)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; start = 0; valid_iq = 1;
        re1 = 16'sd10000; im1 = 16'sd0;
        re3 = 16'sd0;     im3 = 16'sd10000;
        repeat (3) @(posedge clk);
        rst = 0;
        @(negedge clk);
        start = 1;
        @(negedge clk); start = 0;
        wait (done);
        // Δφ=90° → θ=30° → 300
        if ((angle_x10 < 16'sd240) || (angle_x10 > 16'sd360)) begin
            $display("FAIL angle_x10=%0d", angle_x10);
            $fatal;
        end
        $display("PASS tb_aoa_phase angle_x10=%0d", angle_x10);
        $finish;
    end
endmodule
