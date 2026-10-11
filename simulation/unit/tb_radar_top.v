`timescale 1ns / 1ps
module tb_radar_top;
    reg clk, reset, cal_mode;
    wire sclk, mosi, cs_n, rst_n, miso;
    wire error_flag, overflow_err, uart_tx;
    wire [6:0] seg;
    wire [3:0] an;

    radar_top #(.FAST_SIM(1), .USE_XFFT(0), .USE_ILA(0)) dut (
        .clk(clk), .reset(reset), .cal_mode(cal_mode),
        .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso),
        .spi_cs_n(cs_n), .spi_reset_n(rst_n),
        .error_flag(error_flag), .overflow_err(overflow_err),
        .seg(seg), .an(an), .uart_tx(uart_tx)
    );

    bgt60_spi_slave_model slv (
        .reset_n(rst_n), .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        reset = 1; cal_mode = 0;
        repeat (20) @(posedge clk);
        reset = 0;
        // FAST_SIM config + one chirp + 3x128 FFT
        repeat (200000) @(posedge clk);
        if (error_flag) begin
            $display("FAIL error_flag set");
            $fatal;
        end
        $display("INFO top ran; dist blank=%0d overflow=%0d", dut.no_target, overflow_err);
        $display("PASS tb_radar_top (smoke)");
        $finish;
    end
endmodule
