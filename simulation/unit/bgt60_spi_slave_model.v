`timescale 1ns / 1ps
module bgt60_spi_slave_model (
    input  wire reset_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n
);
    reg [23:0] regs [0:127];
    reg [31:0] rx;
    reg [6:0]  cmd_addr;
    integer    bit_i;
    integer    phase;
    integer    fbit;
    integer    fword;
    integer    n, kk;
    real       ang, cv;
    reg [11:0] rx1 [0:127];
    reg [23:0] fifo_mem [0:191];
    integer    i;

    initial begin
        miso = 1'b1;
        bit_i = 0;
        cmd_addr = 7'd0;
        phase = 0;
        fbit = 0;
        fword = 0;
        rx = 0;
        for (i = 0; i < 128; i = i + 1)
            regs[i] = 24'd0;
        regs[2] = 24'h000303;
        regs[8'h5F] = 24'h200000; // CREF=1
        // Beat at bin 26 (~70.9 cm): x[n] = 2048 + 600*cos(2π*26*n/128)
        for (n = 0; n < 128; n = n + 1) begin
            ang = 6.283185307179586 * 26.0 * n / 128.0;
            cv  = $cos(ang);
            rx1[n] = 12'd2048 + $rtoi(cv * 600.0);
        end
        for (kk = 0; kk < 64; kk = kk + 1) begin
            fifo_mem[3*kk]     = {rx1[2*kk],     12'd2048};
            fifo_mem[3*kk + 1] = {12'd2048,      rx1[2*kk + 1]};
            fifo_mem[3*kk + 2] = {12'd2048,      12'd2048};
        end
    end

    always @(posedge cs_n) begin
        bit_i = 0;
        cmd_addr = 7'd0;
        phase = 0;
        fbit  = 0;
        fword = 0;
        rx    = 0;
        miso  = 1'b1;
    end

    always @(negedge cs_n) begin
        miso  = 1'b0;
        bit_i = 0;
        cmd_addr = 7'd0;
        phase = 0;
        rx    = 0;
    end

    always @(posedge sclk) begin
        if (!cs_n && reset_n) begin
            rx = {rx[30:0], mosi};
            if (phase == 0) begin
                bit_i = bit_i + 1;
                if (bit_i == 8)
                    cmd_addr = rx[7:1];
                if (bit_i == 32) begin
                    if (rx[31:25] == 7'h7F)
                        phase = 1;
                    else begin
                        if (rx[24]) begin
                            regs[rx[31:25]] = rx[23:0];
                            if (rx[31:25] == 7'd0)
                                regs[0] = rx[23:0] & 24'hFFFFF1;
                        end
                    end
                    bit_i = 0;
                    fbit  = 0;
                    fword = 0;
                end
            end else begin
                fbit = fbit + 1;
                if (fbit == 24) begin
                    fbit  = 0;
                    fword = fword + 1;
                end
            end
        end
    end

    always @(negedge sclk) begin
        if (!cs_n && reset_n) begin
            if (phase == 0) begin
                if (bit_i < 8)
                    miso = 1'b0;
                else
                    miso = regs[cmd_addr][23 - (bit_i - 8)];
            end else begin
                if (fword < 192)
                    miso = fifo_mem[fword][23 - fbit];
                else
                    miso = 1'b0;
            end
        end
    end
endmodule
