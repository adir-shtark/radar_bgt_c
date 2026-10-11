`timescale 1ns / 1ps
// AXI-Stream wrapper for xfft_0 (Xilinx FFT 9.1, 128-pt).
module fft128_xfft_wrap (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast,
    (* mark_debug = "true" *) output wire        s_tready,
    (* mark_debug = "true" *) output wire [31:0] m_tdata,
    (* mark_debug = "true" *) output wire        m_tvalid,
    (* mark_debug = "true" *) output wire        m_tlast,
    input  wire        m_tready
);
    // PG109 pipelined scaled: tdata[0]=FWD_INV, SCALE_SCH in the next bits.
    localparam [15:0] CFG_FWD_SCALE = 16'h00AB;

    reg [2:0] arst_n_sr;
    always @(posedge clk) begin
        if (rst)
            arst_n_sr <= 3'b000;
        else
            arst_n_sr <= {arst_n_sr[1:0], 1'b1};
    end
    wire aresetn = arst_n_sr[2];

    reg        cfg_sent;
    reg        cfg_tvalid;
    wire       cfg_tready;
    wire       data_tready;

    always @(posedge clk) begin
        if (!aresetn) begin
            cfg_sent   <= 1'b0;
            cfg_tvalid <= 1'b0;
        end else if (!cfg_sent) begin
            cfg_tvalid <= 1'b1;
            if (cfg_tvalid && cfg_tready) begin
                cfg_sent   <= 1'b1;
                cfg_tvalid <= 1'b0;
            end
        end
    end

    assign s_tready = cfg_sent && data_tready;

    xfft_0 u_xfft (
        .aclk                        (clk),
        .aresetn                     (aresetn),
        .s_axis_config_tdata         (CFG_FWD_SCALE),
        .s_axis_config_tvalid        (cfg_tvalid),
        .s_axis_config_tready        (cfg_tready),
        .s_axis_data_tdata           (s_tdata),
        .s_axis_data_tvalid          (s_tvalid && cfg_sent),
        .s_axis_data_tready          (data_tready),
        .s_axis_data_tlast           (s_tlast),
        .m_axis_data_tdata           (m_tdata),
        .m_axis_data_tvalid          (m_tvalid),
        .m_axis_data_tready          (m_tready),
        .m_axis_data_tlast           (m_tlast),
        .event_frame_started         (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_status_channel_halt   (),
        .event_data_in_channel_halt  (),
        .event_data_out_channel_halt ()
    );
endmodule
