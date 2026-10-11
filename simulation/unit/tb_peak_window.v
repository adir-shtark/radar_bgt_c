`timescale 1ns / 1ps
module tb_peak_window;
    reg clk, rst, frame_clr, cal_mode, bin_valid, fft_last;
    reg signed [15:0] bin_re, bin_im;
    reg speed_valid;
    reg signed [15:0] speed_cms;
    wire frame_done, no_target, gated_nt;
    wire [15:0] distance_cm;
    wire [7:0] peak_bin;
    wire signed [15:0] r1r, r1i, r3r, r3i;
    integer rx, k, guard;

    peak_window #(.FLOOR(32'd100)) dut (
        .clk(clk), .rst(rst), .frame_clr(frame_clr), .cal_mode(cal_mode),
        .bin_re(bin_re), .bin_im(bin_im), .bin_valid(bin_valid), .fft_last(fft_last),
        .speed_valid(speed_valid), .speed_cms(speed_cms),
        .frame_done(frame_done), .distance_cm(distance_cm), .no_target(no_target),
        .peak_bin(peak_bin), .rx1_re(r1r), .rx1_im(r1i), .rx3_re(r3r), .rx3_im(r3i),
        .gated_no_target(gated_nt)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // kind: 0 point at bin 26, 1 wide blob, 2 point buried in clutter, 3 point at bin 10
    task send_fft;
        input integer kind;
        integer amp;
        begin
            for (k = 0; k < 128; k = k + 1) begin
                amp = 2;
                if (kind == 0 && k == 26)
                    amp = 400;
                if (kind == 1 && k >= 22 && k <= 30)
                    amp = 300;
                if (kind == 2) begin
                    if (k == 26)
                        amp = 400;
                    else if (k >= 15 && k <= 22)
                        amp = 400;
                    else if (k >= 30 && k <= 36)
                        amp = 400;
                end
                if (kind == 3 && k == 10)
                    amp = 400;
                bin_valid = 1'b1;
                fft_last  = (k == 127);
                bin_re    = amp[15:0];
                bin_im    = 16'sd0;
                @(posedge clk);
            end
            bin_valid = 1'b0;
            fft_last  = 1'b0;
            @(posedge clk);
        end
    endtask

    task run_frame;
        input integer kind;
        begin
            for (rx = 0; rx < 3; rx = rx + 1)
                send_fft(kind);
            guard = 0;
            while (guard < 20000 && !frame_done) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (!frame_done) begin
                $display("FAIL timeout kind %0d", kind);
                $fatal;
            end
        end
    endtask

    task pulse_speed;
        input signed [15:0] cms;
        begin
            @(negedge clk);
            speed_cms   = cms;
            speed_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            speed_valid = 1'b0;
        end
    endtask

    initial begin
        rst = 1; frame_clr = 0; cal_mode = 0;
        bin_valid = 0; fft_last = 0; bin_re = 0; bin_im = 0;
        speed_valid = 0; speed_cms = 0;
        repeat (3) @(posedge clk);
        rst = 0;

        // Specular baseball: one strong bin, quiet neighbors. Hidden until it flies.
        run_frame(0);
        if (no_target || peak_bin != 8'd26 || distance_cm != 16'd71) begin
            $display("FAIL ball peak %0d cm %0d nt %0d", peak_bin, distance_cm, no_target);
            $fatal;
        end
        if (gated_nt !== 1'b1) begin
            $display("FAIL ball visible before speed");
            $fatal;
        end
        pulse_speed(16'sd2000);
        if (gated_nt !== 1'b0) begin
            $display("FAIL flying ball rejected");
            $fatal;
        end
        pulse_speed(16'sd0);
        if (gated_nt !== 1'b1) begin
            $display("FAIL stationary ball accepted");
            $fatal;
        end
        pulse_speed(-16'sd2500);
        if (gated_nt !== 1'b0) begin
            $display("FAIL approaching ball rejected");
            $fatal;
        end
        pulse_speed(16'sd20000);
        if (gated_nt !== 1'b1) begin
            $display("FAIL glitch speed accepted");
            $fatal;
        end

        // Wider than a baseball.
        rst = 1;
        @(posedge clk);
        rst = 0;
        run_frame(1);
        if (!no_target) begin
            $display("FAIL wide target bin %0d", peak_bin);
            $fatal;
        end
        pulse_speed(16'sd2000);
        if (gated_nt !== 1'b1) begin
            $display("FAIL wide target opened by speed");
            $fatal;
        end

        // Point return sitting in strong nearby clutter (fails CA-CFAR).
        rst = 1;
        @(posedge clk);
        rst = 0;
        run_frame(2);
        if (!no_target) begin
            $display("FAIL clutter peak bin %0d cm %0d", peak_bin, distance_cm);
            $fatal;
        end

        // Strong return outside 40 cm..1 m.
        rst = 1;
        @(posedge clk);
        rst = 0;
        run_frame(3);
        if (!no_target) begin
            $display("FAIL expected no_target for bin 10");
            $fatal;
        end

        $display("PASS tb_peak_window");
        $finish;
    end
endmodule
