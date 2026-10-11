`timescale 1ns / 1ps
module tb_uart_telemetry;
    reg clk, rst, send;
    wire tx, busy;
    integer bitn, byten, i;
    reg [7:0] acc;
    reg [7:0] mem [0:63];

    telemetry #(.CLKS_PER_BIT(8)) dut (
        .clk(clk), .rst(rst), .send(send),
        .seq(16'd1842), .dist_cm(16'd67),
        .speed_cms(-16'sd1520), .angle_x10(-16'sd85),
        .flags(8'd9), .uart_tx(tx), .busy(busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; send = 0; byten = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        @(negedge clk);
        send = 1;
        @(negedge clk);
        send = 0;

        // Collect bytes until newline or timeout
        for (i = 0; i < 40; i = i + 1) begin
            wait (tx == 1'b0);
            // mid-start (CLKS_PER_BIT/2)
            repeat (4) @(posedge clk);
            acc = 8'd0;
            for (bitn = 0; bitn < 8; bitn = bitn + 1) begin
                repeat (8) @(posedge clk);
                acc[bitn] = tx;
            end
            repeat (8) @(posedge clk); // stop
            mem[byten] = acc;
            byten = byten + 1;
            if (acc == 8'h0A) begin
                if (mem[0] !== 8'h53) begin
                    $display("FAIL first byte %h", mem[0]);
                    $fatal;
                end
                $display("PASS tb_uart_telemetry bytes=%0d", byten);
                $finish;
            end
        end
        $display("FAIL no newline");
        $fatal;
    end

    initial begin
        #200000;
        $display("FAIL timeout");
        $fatal;
    end
endmodule
