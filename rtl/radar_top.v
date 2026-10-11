`timescale 1ns / 1ps
module radar_top #(
    parameter FAST_SIM = 0,
    parameter USE_XFFT = 0,
    parameter USE_ILA  = 0
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       cal_mode,
    (* mark_debug = "true" *) output wire       spi_sclk,
    (* mark_debug = "true" *) output wire       spi_mosi,
    input  wire       spi_miso,
    (* mark_debug = "true" *) output wire       spi_cs_n,
    (* mark_debug = "true" *) output wire       spi_reset_n,
    (* mark_debug = "true" *) output wire       error_flag,
    (* mark_debug = "true" *) output wire       overflow_err,
    (* mark_debug = "true" *) output wire [6:0] seg,
    (* mark_debug = "true" *) output wire [3:0] an,
    (* mark_debug = "true" *) output wire       uart_tx
);
    localparam integer UART_DIV   = FAST_SIM ? 8 : 868;
    localparam [19:0]  TELEM_WAIT = FAST_SIM ? 20'd80 : 20'd500_000;
    // Last accepted throw stays on the 7-seg and UART after frame_clr.
    // 300 ms at 100 MHz. The chirp loop does not wait on this timer.
    localparam [24:0]  HOLD_CYCLES = FAST_SIM ? 25'd200 : 25'd30_000_000;

    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_pipe = 2'b11;
    always @(posedge clk)
        rst_pipe <= {rst_pipe[0], reset};
    wire rst_sync = rst_pipe[1];

    wire cal_sync;
    sync_2ff u_cal_sync (
        .clk (clk),
        .rst (rst_sync),
        .d   (cal_mode),
        .q   (cal_sync)
    );

    wire        spi_start, spi_busy, spi_done, spi_fifo_valid;
    wire [1:0]  spi_cmd;
    wire [6:0]  spi_addr;
    wire [23:0] spi_wdata, spi_rdata, spi_fifo_word;
    wire [9:0]  spi_burst_n;
    wire [7:0]  spi_gsr0;

    wire        chirp_start, chirp_done, sample_valid;
    wire [11:0] u_rx1, u_rx2, u_rx3;
    wire [7:0]  sample_idx;

    wire [31:0] fft_s_tdata, fft_m_tdata;
    wire        fft_s_tvalid, fft_s_tready, fft_s_tlast;
    wire        fft_m_tvalid, fft_m_tready, fft_m_tlast;
    assign fft_m_tready = 1'b1;

    wire        frame_clr;
    wire        peak_done, spatial_nt, no_target;
    wire [15:0] distance_cm;
    wire [7:0]  peak_bin;
    wire signed [15:0] rx1_re, rx1_im, rx3_re, rx3_im;
    wire signed [15:0] speed_cms;
    wire        speed_valid;
    wire        aoa_done;
    wire signed [15:0] angle_x10;
    wire        telem_busy;
    wire        uart_start;

    bgt60_spi_master u_spi (
        .clk            (clk),
        .rst            (rst_sync),
        .start          (spi_start),
        .cmd            (spi_cmd),
        .addr           (spi_addr),
        .wdata          (spi_wdata),
        .burst_nwords   (spi_burst_n),
        .busy           (spi_busy),
        .done           (spi_done),
        .rdata          (spi_rdata),
        .gsr0           (spi_gsr0),
        .fifo_word      (spi_fifo_word),
        .fifo_word_valid(spi_fifo_valid),
        .spi_sclk       (spi_sclk),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),
        .spi_cs_n       (spi_cs_n)
    );

    mode3_unpack u_unp (
        .clk          (clk),
        .rst          (rst_sync),
        .chirp_start  (chirp_start),
        .word         (spi_fifo_word),
        .word_valid   (spi_fifo_valid),
        .rx1          (u_rx1),
        .rx2          (u_rx2),
        .rx3          (u_rx3),
        .sample_idx   (sample_idx),
        .sample_valid (sample_valid),
        .chirp_done   (chirp_done)
    );

    generate
        if (USE_XFFT) begin : g_xfft
            fft128_xfft_wrap u_fft (
                .clk      (clk),
                .rst      (rst_sync),
                .s_tdata  (fft_s_tdata),
                .s_tvalid (fft_s_tvalid),
                .s_tlast  (fft_s_tlast),
                .s_tready (fft_s_tready),
                .m_tdata  (fft_m_tdata),
                .m_tvalid (fft_m_tvalid),
                .m_tlast  (fft_m_tlast),
                .m_tready (fft_m_tready)
            );
        end else begin : g_rtl
            fft128_stream u_fft (
                .clk      (clk),
                .rst      (rst_sync),
                .s_tdata  (fft_s_tdata),
                .s_tvalid (fft_s_tvalid),
                .s_tlast  (fft_s_tlast),
                .s_tready (fft_s_tready),
                .m_tdata  (fft_m_tdata),
                .m_tvalid (fft_m_tvalid),
                .m_tlast  (fft_m_tlast),
                .m_tready (fft_m_tready)
            );
        end
    endgenerate

    peak_window u_peak (
        .clk          (clk),
        .rst          (rst_sync),
        .frame_clr    (frame_clr),
        .cal_mode     (cal_sync),
        .bin_re       (fft_m_tdata[15:0]),
        .bin_im       (fft_m_tdata[31:16]),
        .bin_valid    (fft_m_tvalid),
        .fft_last     (fft_m_tlast && fft_m_tvalid),
        .speed_valid  (speed_valid),
        .speed_cms    (speed_cms),
        .frame_done   (peak_done),
        .distance_cm  (distance_cm),
        .no_target    (spatial_nt),
        .gated_no_target(no_target),
        .peak_bin     (peak_bin),
        .rx1_re       (rx1_re),
        .rx1_im       (rx1_im),
        .rx3_re       (rx3_re),
        .rx3_im       (rx3_im)
    );

    range_rate u_rate (
        .clk           (clk),
        .rst           (rst_sync),
        .sample_valid  (peak_done),
        .no_target     (spatial_nt),
        .distance_cm   (distance_cm),
        .speed_cms     (speed_cms),
        .speed_valid   (speed_valid)
    );

    aoa_phase u_aoa (
        .clk      (clk),
        .rst      (rst_sync),
        .start    (peak_done),
        .valid_iq (!spatial_nt),
        .re1      (rx1_re),
        .im1      (rx1_im),
        .re3      (rx3_re),
        .im3      (rx3_im),
        .done     (aoa_done),
        .angle_x10(angle_x10)
    );

    bgt60_ctrl #(.FAST_SIM(FAST_SIM)) u_ctrl (
        .clk            (clk),
        .rst_sync       (rst_sync),
        .sw_reset       (reset),
        .spi_start      (spi_start),
        .spi_cmd        (spi_cmd),
        .spi_addr       (spi_addr),
        .spi_wdata      (spi_wdata),
        .spi_burst_n    (spi_burst_n),
        .spi_busy       (spi_busy),
        .spi_done       (spi_done),
        .spi_rdata      (spi_rdata),
        .spi_gsr0       (spi_gsr0),
        .spi_fifo_valid (spi_fifo_valid),
        .spi_fifo_word  (spi_fifo_word),
        .spi_reset_n    (spi_reset_n),
        .chirp_start    (chirp_start),
        .chirp_done     (chirp_done),
        .sample_valid   (sample_valid),
        .sample_idx     (sample_idx),
        .rx1            (u_rx1),
        .rx2            (u_rx2),
        .rx3            (u_rx3),
        .fft_s_tdata    (fft_s_tdata),
        .fft_s_tvalid   (fft_s_tvalid),
        .fft_s_tlast    (fft_s_tlast),
        .fft_s_tready   (fft_s_tready),
        .dsp_done       (peak_done),
        .frame_clr      (frame_clr),
        .error_flag     (error_flag),
        .overflow_err   (overflow_err)
    );

    // Snapshot taken the cycle after the flying gate opens, so distance_cm
    // and speed_cms have already updated. frame_clr does not touch these.
    reg [15:0] hold_dist;
    reg signed [15:0] hold_speed;
    reg signed [15:0] hold_angle;
    reg        hold_valid;
    reg [24:0] hold_tmr;
    reg        speed_valid_d;
    reg        aoa_done_d;
    reg        angle_ready;
    reg        angle_pending;
    reg signed [15:0] angle_cap;

    seven_seg_driver u_seg (
        .clk   (clk),
        .rst   (rst_sync),
        .value (hold_dist),
        .blank (!hold_valid || cal_sync),
        .seg   (seg),
        .an    (an)
    );

    reg [15:0] seq;
    reg [15:0] lat_dist;
    reg signed [15:0] lat_speed;
    reg signed [15:0] lat_angle;
    reg [7:0]  lat_flags;
    reg        send_pulse;
    reg [19:0] telem_div;

    always @(posedge clk) begin
        if (rst_sync) begin
            seq           <= 16'd0;
            lat_dist      <= 16'd0;
            lat_speed     <= 16'sd0;
            lat_angle     <= 16'sd0;
            lat_flags     <= 8'd0;
            send_pulse    <= 1'b0;
            telem_div     <= 20'd0;
            hold_dist     <= 16'd0;
            hold_speed    <= 16'sd0;
            hold_angle    <= 16'sd0;
            hold_valid    <= 1'b0;
            hold_tmr      <= 25'd0;
            speed_valid_d <= 1'b0;
            aoa_done_d    <= 1'b0;
            angle_ready   <= 1'b0;
            angle_pending <= 1'b0;
            angle_cap     <= 16'sd0;
        end else begin
            send_pulse    <= 1'b0;
            speed_valid_d <= speed_valid;
            aoa_done_d    <= aoa_done;

            if (peak_done)
                angle_ready <= 1'b0;
            if (aoa_done_d) begin
                angle_cap   <= angle_x10;
                angle_ready <= 1'b1;
            end

            if (cal_sync) begin
                hold_valid    <= 1'b0;
                angle_pending <= 1'b0;
            end else if (speed_valid_d && !no_target) begin
                hold_dist  <= distance_cm;
                hold_speed <= speed_cms;
                hold_valid <= 1'b1;
                hold_tmr   <= HOLD_CYCLES;
                if (aoa_done_d) begin
                    hold_angle    <= angle_x10;
                    angle_pending <= 1'b0;
                end else if (angle_ready) begin
                    hold_angle    <= angle_cap;
                    angle_pending <= 1'b0;
                end else
                    angle_pending <= 1'b1;
            end else if (aoa_done_d && angle_pending) begin
                hold_angle    <= angle_x10;
                angle_pending <= 1'b0;
            end else if (hold_valid) begin
                if (hold_tmr != 25'd0)
                    hold_tmr <= hold_tmr - 25'd1;
                else
                    hold_valid <= 1'b0;
            end

            if (telem_div != TELEM_WAIT)
                telem_div <= telem_div + 20'd1;
            else if (!telem_busy) begin
                lat_dist   <= hold_dist;
                lat_speed  <= hold_speed;
                lat_angle  <= hold_angle;
                lat_flags  <= {4'd0, hold_valid, overflow_err, error_flag,
                               hold_valid && !cal_sync};
                send_pulse <= 1'b1;
                seq        <= seq + 16'd1;
                telem_div  <= 20'd0;
            end
        end
    end

    assign uart_start = send_pulse;

    telemetry #(.CLKS_PER_BIT(UART_DIV)) u_telem (
        .clk        (clk),
        .rst        (rst_sync),
        .send       (send_pulse),
        .seq        (seq),
        .dist_cm    (lat_dist),
        .speed_cms  (lat_speed),
        .angle_x10  (lat_angle),
        .flags      (lat_flags),
        .uart_tx    (uart_tx),
        .busy       (telem_busy)
    );

    generate
        if (USE_ILA) begin : g_ila
            ila_dsp_chain u_ila_dsp (
                .clk     (clk),
                .probe0  (spi_miso),
                .probe1  (spi_sclk),
                .probe2  (spi_cs_n),
                .probe3  (spi_fifo_word),
                .probe4  (spi_fifo_valid),
                .probe5  (u_rx1),
                .probe6  (u_rx2),
                .probe7  (u_rx3),
                .probe8  (sample_idx),
                .probe9  (sample_valid),
                .probe10 (chirp_done),
                .probe11 (peak_done),
                .probe12 (distance_cm),
                .probe13 (no_target),
                .probe14 (speed_cms),
                .probe15 (angle_x10),
                .probe16 (uart_tx),
                .probe17 (uart_start)
            );
        end
    endgenerate
endmodule
