`timescale 1ns / 1ps
module tb_spi_master;
    reg clk, rst, start;
    reg [1:0] cmd;
    reg [6:0] addr;
    reg [23:0] wdata;
    wire busy, done;
    wire [23:0] rdata;
    wire [7:0] gsr0;
    wire [23:0] fifo_word;
    wire fifo_word_valid;
    wire sclk, mosi, cs_n;
    wire miso;

    bgt60_spi_master dut (
        .clk(clk), .rst(rst), .start(start), .cmd(cmd), .addr(addr), .wdata(wdata),
        .burst_nwords(10'd4), .busy(busy), .done(done), .rdata(rdata), .gsr0(gsr0),
        .fifo_word(fifo_word), .fifo_word_valid(fifo_word_valid),
        .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso), .spi_cs_n(cs_n)
    );

    bgt60_spi_slave_model slv (
        .reset_n(1'b1), .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task spi_go;
        input [1:0] c;
        input [6:0] a;
        input [23:0] d;
        begin
            @(negedge clk);
            cmd = c;
            addr = a;
            wdata = d;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done);
            @(posedge clk);
        end
    endtask

    initial begin
        rst = 1; start = 0; cmd = 0; addr = 0; wdata = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);
        spi_go(2'd0, 7'h06, 24'h7000BF);
        spi_go(2'd1, 7'h02, 24'h0);
        if (rdata[7:0] !== 8'd3) begin
            $display("FAIL CHIP_ID %h", rdata);
            $fatal;
        end
        $display("PASS tb_spi_master rdata=%h", rdata);
        $finish;
    end
endmodule
