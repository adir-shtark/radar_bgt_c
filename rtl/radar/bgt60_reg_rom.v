`timescale 1ns / 1ps
// Fast 1-chirp / 128-sample / 3-RX ROM. Analog fields from proven Infineon 3-RX set.
module bgt60_reg_rom (
    input  wire [4:0]  idx,
    (* mark_debug = "true" *) output reg  [6:0]  addr,
    (* mark_debug = "true" *) output reg  [23:0] data,
    (* mark_debug = "true" *) output wire        last
);
    localparam NREGS = 24;
    assign last = (idx == 5'd23);

    always @* begin
        addr = 7'h00;
        data = 24'h000000;
        case (idx)
            5'd0:  begin addr = 7'h00; data = 24'h7869C0; end // MAIN
            5'd1:  begin addr = 7'h01; data = 24'h0A0A40; end // ADC0 2 Msps
            5'd2:  begin addr = 7'h04; data = 24'hE967FD; end // PACR1
            5'd3:  begin addr = 7'h05; data = 24'h0805B4; end // PACR2 saw
            5'd4:  begin addr = 7'h06; data = 24'h7000BF; end // SFCTL CREF=191
            5'd5:  begin addr = 7'h07; data = 24'h010D00; end // SADC_CTRL
            5'd6:  begin addr = 7'h0B; data = 24'h000BE0; end // CSCI
            5'd7:  begin addr = 7'h0F; data = 24'h000B60; end // CSCDS
            5'd8:  begin addr = 7'h10; data = 24'h13FC51; end // CSU1_0
            5'd9:  begin addr = 7'h11; data = 24'h7FF41F; end // CSU1_1 Mode3 TX_DAC=31
            5'd10: begin addr = 7'h12; data = 24'h0238E3; end // CSU1_2 VGA=4, HP=18 dB, HPF=80 kHz
            5'd11: begin addr = 7'h16; data = 24'h000490; end // CSC1
            5'd12: begin addr = 7'h2C; data = 24'h52C200; end // CCR0
            5'd13: begin addr = 7'h2D; data = 24'h00024F; end // CCR1
            5'd14: begin addr = 7'h2E; data = 24'h000001; end // CCR2 1 chirp
            5'd15: begin addr = 7'h2F; data = 24'hABD464; end // CCR3
            5'd16: begin addr = 7'h30; data = 24'hAA0000; end // PLL1 FSU 58 GHz
            5'd17: begin addr = 7'h31; data = 24'h000649; end // RSU=1609
            5'd18: begin addr = 7'h32; data = 24'h0002BC; end // RTU=700
            5'd19: begin addr = 7'h33; data = 24'h000080; end // APU=128
            5'd20: begin addr = 7'h34; data = 24'h000000; end // FSD
            5'd21: begin addr = 7'h35; data = 24'h000000; end // RSD
            5'd22: begin addr = 7'h36; data = 24'h000000; end // RTD
            5'd23: begin addr = 7'h37; data = 24'h36D310; end // PLL1_7 T_SED~1.4ms
            default: begin addr = 7'h00; data = 24'h000000; end
        endcase
    end
endmodule
