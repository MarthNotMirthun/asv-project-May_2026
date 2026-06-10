// Module: uart_tx
// Description: UART transmitter, 8N1, idles HIGH, configurable baud divisor
// Target: Tang Nano 20K (GW2AR-18)
// Clock: 27MHz (CLKS_PER_BIT=234 -> ~115200 baud)
// Author: fpga-verilog-engineer agent
// Date: 2026-06-09

module uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,      // synchronous active-low reset
    input  wire       tx_start,   // pulse high to begin a transmission
    input  wire [7:0] tx_data,    // byte to send, latched at start
    output reg        tx,         // serial output, idles HIGH
    output reg        tx_busy     // HIGH while a byte is in flight
);

    // State encoding
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;   // counts clocks within a bit period
    reg [2:0]  bit_index;   // which data bit (0..7)
    reg [7:0]  tx_shift;    // latched data being shifted out

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            tx_shift  <= 8'd0;
            tx        <= 1'b1;   // line idles high
            tx_busy   <= 1'b0;
        end else begin
            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    tx        <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (tx_start) begin
                        tx_shift <= tx_data;   // latch the byte
                        tx_busy  <= 1'b1;
                        state    <= S_START;
                    end
                end
                // -------------------------------------------------
                S_START: begin
                    tx      <= 1'b0;           // start bit
                    tx_busy <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= S_DATA;
                    end
                end
                // -------------------------------------------------
                S_DATA: begin
                    tx      <= tx_shift[bit_index];   // LSB first
                    tx_busy <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count <= 16'd0;
                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 3'd1;
                        end else begin
                            bit_index <= 3'd0;
                            state     <= S_STOP;
                        end
                    end
                end
                // -------------------------------------------------
                S_STOP: begin
                    tx      <= 1'b1;           // stop bit (line high)
                    tx_busy <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count <= 16'd0;
                        tx_busy   <= 1'b0;
                        state     <= S_IDLE;
                    end
                end
                // -------------------------------------------------
                default: begin
                    state     <= S_IDLE;
                    tx        <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                end
            endcase
        end
    end

endmodule
