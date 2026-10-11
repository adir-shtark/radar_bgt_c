`timescale 1ns / 1ps
module tb_mode3_unpack;
    reg clk, rst, chirp_start, word_valid;
    reg [23:0] word;
    wire [11:0] rx1, rx2, rx3;
    wire [7:0] sample_idx;
    wire sample_valid, chirp_done;
    integer k, got;

    mode3_unpack dut (
        .clk(clk), .rst(rst), .chirp_start(chirp_start),
        .word(word), .word_valid(word_valid),
        .rx1(rx1), .rx2(rx2), .rx3(rx3),
        .sample_idx(sample_idx), .sample_valid(sample_valid), .chirp_done(chirp_done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; chirp_start = 0; word_valid = 0; word = 0; got = 0;
        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);
        chirp_start = 1;
        @(posedge clk);
        chirp_start = 0;
        for (k = 0; k < 64; k = k + 1) begin
            @(posedge clk);
            word = {(12'd0 + (k * 2)), 12'd100};
            word_valid = 1;
            @(posedge clk); word_valid = 0;
            @(posedge clk);
            word = {12'd200, (12'd0 + (k * 2) + 12'd1)};
            word_valid = 1;
            @(posedge clk); word_valid = 0;
            @(posedge clk);
            word = {12'd101, 12'd201};
            word_valid = 1;
            @(posedge clk); word_valid = 0;
        end
        wait (chirp_done);
        @(posedge clk);
        if (got !== 128) begin
            $display("FAIL sample count %0d", got);
            $fatal;
        end
        $display("PASS tb_mode3_unpack");
        $finish;
    end

    always @(posedge clk) begin
        if (sample_valid) begin
            if (rx1 !== sample_idx) begin
                $display("FAIL rx1 idx %0d val %0d", sample_idx, rx1);
                $fatal;
            end
            got = got + 1;
        end
    end
endmodule
