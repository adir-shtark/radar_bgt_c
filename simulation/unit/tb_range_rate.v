`timescale 1ns / 1ps
module tb_range_rate;
    reg clk, rst, sample_valid, no_target;
    reg [15:0] distance_cm;
    wire signed [15:0] speed_cms;
    wire speed_valid;
    integer t;

    range_rate dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .no_target(no_target), .distance_cm(distance_cm),
        .speed_cms(speed_cms), .speed_valid(speed_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; sample_valid = 0; no_target = 0; distance_cm = 40;
        repeat (5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        sample_valid = 1; distance_cm = 40;
        @(posedge clk); sample_valid = 0;
        // 2000 us later, 67 cm → Δ=27 cm / 0.002 s = 13500 cm/s
        repeat (200000) @(posedge clk);
        sample_valid = 1; distance_cm = 67;
        @(posedge clk); sample_valid = 0;
        wait (speed_valid);
        if ((speed_cms < 16'sd12000) || (speed_cms > 16'sd15000)) begin
            $display("FAIL speed %0d", speed_cms);
            $fatal;
        end
        $display("PASS tb_range_rate speed=%0d", speed_cms);
        $finish;
    end
endmodule
