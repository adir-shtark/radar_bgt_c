`timescale 1ns / 1ps
// Collect 3 RX range FFTs, NCI, optional clutter subtract.
// noise_filter keeps a nearest bin only when it clears CA-CFAR,
// fits a baseball (about 7.3 cm), and is flying.
module peak_window #(
    parameter [7:0]   BIN_LO = 8'd15,
    parameter [7:0]   BIN_HI = 8'd37,
    parameter [31:0]  FLOOR  = 32'd4096
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_clr,
    input  wire        cal_mode,
    input  wire signed [15:0] bin_re,
    input  wire signed [15:0] bin_im,
    input  wire        bin_valid,
    input  wire        fft_last,
    input  wire        speed_valid,
    input  wire signed [15:0] speed_cms,
    (* mark_debug = "true" *) output reg         frame_done,
    (* mark_debug = "true" *) output reg  [15:0] distance_cm,
    (* mark_debug = "true" *) output reg         no_target,
    (* mark_debug = "true" *) output reg  [7:0]  peak_bin,
    (* mark_debug = "true" *) output reg signed [15:0] rx1_re,
    (* mark_debug = "true" *) output reg signed [15:0] rx1_im,
    (* mark_debug = "true" *) output reg signed [15:0] rx3_re,
    (* mark_debug = "true" *) output reg signed [15:0] rx3_im,
    (* mark_debug = "true" *) output wire        gated_no_target
);
    localparam S_COLLECT = 2'd0;
    localparam S_DUMP    = 2'd1;
    localparam S_WAITBG  = 2'd2;
    localparam S_FILT    = 2'd3;

    reg [31:0] nci     [0:63];
    reg [31:0] work    [0:63];
    reg signed [15:0] iq1_re [0:63];
    reg signed [15:0] iq1_im [0:63];
    reg signed [15:0] iq3_re [0:63];
    reg signed [15:0] iq3_im [0:63];

    reg [1:0]  state;
    reg [1:0]  rx_cnt;
    reg [7:0]  bin_cnt;
    reg [7:0]  d_idx;
    integer    wi;

    // Replicate the reset LUT. A single rst||frame_clr net onto the
    // NCI/IQ registers was a multi-nanosecond setup fail.
    (* max_fanout = 32 *) wire mem_rst = rst || frame_clr;

    // Square pipeline: input reg, product, product copy, then sum.
    // Keeps each 16x16 square inside one DSP48 cycle (100 MHz).
    reg                v0, v1, v2, v3, v4;
    reg [1:0]          rx0, rx1, rx2, rx3p, rx4;
    reg [7:0]          b0, b1, b2, b3, b4;
    reg signed [15:0]  re_a, im_a;
    reg signed [31:0]  re_m, im_m, re_p, im_p;
    reg [31:0]         mag_p, mag4, nci_rd;
    wire [32:0] nci_sum = {1'b0, nci_rd} + {1'b0, mag4};
    wire [31:0] nci_sat = nci_sum[32] ? 32'hFFFF_FFFF : nci_sum[31:0];

    // distance_cm = (k * 2727 + 500) / 1000, k = 0..63. A variable
    // multiply/divide here was a -8.6 ns path. The table is that formula.
    (* rom_style = "distributed" *) reg [7:0] cm_rom [0:63];
    integer bi;
    initial begin
        for (bi = 0; bi < 64; bi = bi + 1)
            cm_rom[bi] = (bi * 2727 + 500) / 1000;
    end

    wire [31:0] bg_mag;
    wire [7:0]  bg_idx;
    wire        bg_valid, bg_last, cal_active;
    wire        dump_valid, dump_last;
    wire [31:0] dump_mag;
    wire [7:0]  dump_idx;

    wire dumping = (state == S_DUMP);
    assign dump_mag   = nci[d_idx[5:0]];
    assign dump_idx   = d_idx;
    assign dump_valid = dumping;
    assign dump_last  = dumping && (d_idx == 8'd63);

    bg_profile_sub u_bg (
        .clk        (clk),
        .rst        (rst),
        .cal_mode   (cal_mode),
        .mag_in     (dump_mag),
        .idx_in     (dump_idx),
        .valid_in   (dump_valid),
        .last_in    (dump_last),
        .mag_out    (bg_mag),
        .idx_out    (bg_idx),
        .valid_out  (bg_valid),
        .last_out   (bg_last),
        .cal_active (cal_active)
    );

    wire        nf_done, nf_hit;
    wire [7:0]  nf_bin, nf_rd;
    reg  [31:0] nf_mag;
    wire        nf_start = (state == S_WAITBG) && bg_last &&
                           !cal_mode && !cal_active;

    noise_filter #(.BIN_LO(BIN_LO), .BIN_HI(BIN_HI), .FLOOR(FLOOR)) u_noise (
        .clk              (clk),
        .rst              (mem_rst),
        .start            (nf_start),
        .mag              (nf_mag),
        .rd_addr          (nf_rd),
        .done             (nf_done),
        .hit              (nf_hit),
        .peak_bin         (nf_bin),
        .det_pulse        (frame_done),
        .det_no_target    (no_target),
        .speed_valid      (speed_valid),
        .speed_cms        (speed_cms),
        .gated_no_target  (gated_no_target)
    );

    always @(posedge clk) begin
        if (mem_rst) begin
            state        <= S_COLLECT;
            rx_cnt       <= 2'd0;
            for (wi = 0; wi < 64; wi = wi + 1) begin
                nci[wi]  <= 32'd0;
                work[wi] <= 32'd0;
            end
            bin_cnt      <= 8'd0;
            d_idx        <= 8'd0;
            frame_done   <= 1'b0;
            nf_mag       <= 32'd0;
            distance_cm  <= 16'd0;
            no_target    <= 1'b1;
            peak_bin     <= 8'd0;
            rx1_re       <= 16'd0;
            rx1_im       <= 16'd0;
            rx3_re       <= 16'd0;
            rx3_im       <= 16'd0;
            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0; v4 <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            re_a <= bin_re;
            im_a <= bin_im;
            v0   <= (state == S_COLLECT) && bin_valid;
            b0   <= bin_cnt;
            rx0  <= rx_cnt;

            re_m <= re_a * re_a;
            im_m <= im_a * im_a;
            v1   <= v0;
            b1   <= b0;
            rx1  <= rx0;

            re_p <= re_m;
            im_p <= im_m;
            v2   <= v1;
            b2   <= b1;
            rx2  <= rx1;

            mag_p <= re_p + im_p;
            v3    <= v2;
            b3    <= b2;
            rx3p  <= rx2;

            // Register the profile read, then add on the next cycle.
            // A 64-deep mux plus a 32-bit add missed 100 MHz in one cycle.
            nci_rd <= nci[b3[5:0]];
            mag4   <= mag_p;
            v4     <= v3;
            b4     <= b3;
            rx4    <= rx3p;
            nf_mag <= work[nf_rd[5:0]];

            if (v4 && (b4 < 8'd64)) begin
                if (rx4 == 2'd0)
                    nci[b4[5:0]] <= mag4;
                else
                    nci[b4[5:0]] <= nci_sat;
            end

            if (bg_valid)
                work[bg_idx[5:0]] <= bg_mag;

            case (state)
                S_COLLECT: begin
                    if (bin_valid) begin
                        if (bin_cnt < 8'd64) begin
                            if (rx_cnt == 2'd0) begin
                                iq1_re[bin_cnt[5:0]] <= bin_re;
                                iq1_im[bin_cnt[5:0]] <= bin_im;
                            end else if (rx_cnt == 2'd2) begin
                                iq3_re[bin_cnt[5:0]] <= bin_re;
                                iq3_im[bin_cnt[5:0]] <= bin_im;
                            end
                        end
                        if (fft_last) begin
                            bin_cnt <= 8'd0;
                            if (rx_cnt == 2'd2) begin
                                d_idx <= 8'd0;
                                state <= S_DUMP;
                            end else
                                rx_cnt <= rx_cnt + 2'd1;
                        end else
                            bin_cnt <= bin_cnt + 8'd1;
                    end
                end

                S_DUMP: begin
                    if (d_idx == 8'd63)
                        state <= S_WAITBG;
                    else
                        d_idx <= d_idx + 8'd1;
                end

                S_WAITBG: begin
                    if (bg_last) begin
                        if (cal_mode || cal_active) begin
                            no_target  <= 1'b1;
                            frame_done <= 1'b1;
                            rx_cnt     <= 2'd0;
                            state      <= S_COLLECT;
                        end else
                            state <= S_FILT;
                    end
                end

                S_FILT: begin
                    if (nf_done) begin
                        if (nf_hit) begin
                            peak_bin    <= nf_bin;
                            distance_cm <= {8'd0, cm_rom[nf_bin[5:0]]};
                            no_target   <= 1'b0;
                            rx1_re      <= iq1_re[nf_bin[5:0]];
                            rx1_im      <= iq1_im[nf_bin[5:0]];
                            rx3_re      <= iq3_re[nf_bin[5:0]];
                            rx3_im      <= iq3_im[nf_bin[5:0]];
                        end else
                            no_target <= 1'b1;
                        frame_done <= 1'b1;
                        rx_cnt     <= 2'd0;
                        state      <= S_COLLECT;
                    end
                end

                default: state <= S_COLLECT;
            endcase
        end
    end
endmodule
