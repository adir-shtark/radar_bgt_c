`timescale 1ns / 1ps
// ASCII: S,<seq>,<dist_cm>,<speed_cms>,<angle_x10>,<flags>\n
module telemetry #(
    parameter integer CLKS_PER_BIT = 868
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        send,
    input  wire [15:0] seq,
    input  wire [15:0] dist_cm,
    input  wire signed [15:0] speed_cms,
    input  wire signed [15:0] angle_x10,
    input  wire [7:0]  flags,
    (* mark_debug = "true" *) output wire        uart_tx,
    (* mark_debug = "true" *) output wire        busy
);
    localparam ST_IDLE  = 3'd0;
    localparam ST_LOAD  = 3'd1;
    localparam ST_SIGN  = 3'd2;
    localparam ST_MSIGN = 3'd3;
    localparam ST_SKIP  = 3'd4;
    localparam ST_DIG   = 3'd5;
    localparam ST_WAIT  = 3'd6;
    localparam ST_BCD   = 3'd7;

    reg [2:0]  state;
    reg [3:0]  field;   // 0:'S' 1:seq 2:dist 3:speed 4:angle 5:flags 6:NL
    reg [7:0]  ch;
    reg        wr;
    wire       tx_busy;
    reg [15:0] absv;
    reg        neg;
    reg [3:0]  d0, d1, d2, d3, d4;
    reg [2:0]  didx;
    reg        started;
    // One double-dabble step per clock. Five parallel divides did not meet 100 MHz.
    reg [4:0]  sh;
    reg [15:0] bin;
    reg [19:0] bcd;
    wire [3:0] adj0 = (bcd[3:0]   >= 4'd5) ? (bcd[3:0]   + 4'd3) : bcd[3:0];
    wire [3:0] adj1 = (bcd[7:4]   >= 4'd5) ? (bcd[7:4]   + 4'd3) : bcd[7:4];
    wire [3:0] adj2 = (bcd[11:8]  >= 4'd5) ? (bcd[11:8]  + 4'd3) : bcd[11:8];
    wire [3:0] adj3 = (bcd[15:12] >= 4'd5) ? (bcd[15:12] + 4'd3) : bcd[15:12];
    wire [3:0] adj4 = (bcd[19:16] >= 4'd5) ? (bcd[19:16] + 4'd3) : bcd[19:16];
    wire [19:0] adj = {adj4, adj3, adj2, adj1, adj0};

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk   (clk),
        .rst   (rst),
        .data  (ch),
        .start (wr),
        .busy  (tx_busy),
        .tx    (uart_tx)
    );

    assign busy = (state != ST_IDLE) || tx_busy;

    function [15:0] uabs;
        input signed [15:0] v;
        begin
            uabs = v[15] ? (~v + 16'd1) : v;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state   <= ST_IDLE;
            field   <= 4'd0;
            ch      <= 8'd0;
            wr      <= 1'b0;
            absv    <= 16'd0;
            neg     <= 1'b0;
            d0 <= 4'd0; d1 <= 4'd0; d2 <= 4'd0; d3 <= 4'd0; d4 <= 4'd0;
            didx    <= 3'd0;
            started <= 1'b0;
            sh      <= 5'd0;
            bin     <= 16'd0;
            bcd     <= 20'd0;
        end else begin
            wr <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (send && !tx_busy) begin
                        ch    <= 8'h53;
                        wr    <= 1'b1;
                        field <= 4'd0;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (!tx_busy && !wr) begin
                        if (field == 4'd0) begin
                            ch    <= 8'h2C;
                            wr    <= 1'b1;
                            field <= 4'd1;
                            state <= ST_WAIT;
                        end else if ((field >= 4'd1) && (field <= 4'd5) && (ch == 8'h2C)) begin
                            state <= ST_LOAD;
                        end else if (field == 4'd5) begin
                            ch    <= 8'h0A;
                            wr    <= 1'b1;
                            field <= 4'd6;
                            state <= ST_WAIT;
                        end else if (field == 4'd6) begin
                            state <= ST_IDLE;
                        end else begin
                            ch    <= 8'h2C;
                            wr    <= 1'b1;
                            field <= field + 4'd1;
                            state <= ST_WAIT;
                        end
                    end
                end

                ST_LOAD: begin
                    case (field)
                        4'd1: begin neg <= 1'b0; absv <= seq; end
                        4'd2: begin neg <= 1'b0; absv <= dist_cm; end
                        4'd3: begin neg <= speed_cms[15]; absv <= uabs(speed_cms); end
                        4'd4: begin neg <= angle_x10[15]; absv <= uabs(angle_x10); end
                        default: begin neg <= 1'b0; absv <= {8'd0, flags}; end
                    endcase
                    state <= ST_SIGN;
                end

                ST_SIGN: begin
                    bcd   <= 20'd0;
                    bin   <= absv;
                    sh    <= 5'd0;
                    state <= ST_BCD;
                end

                ST_BCD: begin
                    if (sh == 5'd16) begin
                        d4      <= bcd[19:16];
                        d3      <= bcd[15:12];
                        d2      <= bcd[11:8];
                        d1      <= bcd[7:4];
                        d0      <= bcd[3:0];
                        didx    <= 3'd4;
                        started <= 1'b0;
                        if (neg) begin
                            if (!tx_busy) begin
                                ch    <= 8'h2D;
                                wr    <= 1'b1;
                                neg   <= 1'b0;
                                state <= ST_MSIGN;
                            end
                        end else
                            state <= ST_SKIP;
                    end else begin
                        bcd <= {adj[18:0], bin[15]};
                        bin <= {bin[14:0], 1'b0};
                        sh  <= sh + 5'd1;
                    end
                end

                ST_MSIGN: begin
                    if (!tx_busy && !wr)
                        state <= ST_SKIP;
                end

                ST_SKIP: begin
                    if ((didx == 3'd0) ||
                        (didx == 3'd4 && d4 != 4'd0) ||
                        (didx == 3'd3 && d3 != 4'd0) ||
                        (didx == 3'd2 && d2 != 4'd0) ||
                        (didx == 3'd1 && d1 != 4'd0) ||
                        started) begin
                        started <= 1'b1;
                        state   <= ST_DIG;
                    end else
                        didx <= didx - 3'd1;
                end

                ST_DIG: begin
                    if (!tx_busy && !wr) begin
                        case (didx)
                            3'd4: ch <= 8'h30 + {4'd0, d4};
                            3'd3: ch <= 8'h30 + {4'd0, d3};
                            3'd2: ch <= 8'h30 + {4'd0, d2};
                            3'd1: ch <= 8'h30 + {4'd0, d1};
                            default: ch <= 8'h30 + {4'd0, d0};
                        endcase
                        wr <= 1'b1;
                        if (didx == 3'd0)
                            state <= ST_WAIT;
                        else begin
                            didx  <= didx - 3'd1;
                            state <= ST_DIG;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
