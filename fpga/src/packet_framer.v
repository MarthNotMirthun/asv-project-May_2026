// ============================================================
// Module:      packet_framer
// Description: 8-byte UART packet FSM. Latches a detection result
//              from peak_detector on data_valid, then shifts the
//              8 packet bytes out through the single-byte uart_tx,
//              tx_busy-gated, with no inter-byte gap beyond the
//              uart_tx state turnaround. Checksum = XOR of bytes 0-5.
// Target:      Tang Nano 20K (GW2AR-18), 27MHz system clock
// Pipeline:    peak_detector -> THIS -> uart_tx
// Latency:     8 * (10 bit-periods @ 115200) ~= 695 us per packet;
//              data_valid arriving mid-packet is DROPPED (200 Hz valid
//              vs 115200 baud has >10x margin, never starved).
// Resources:   ~80 LUTs, 0 multipliers, 0 BSRAM.
// Author:      fpga-verilog-engineer agent
// Date:        2026-06-17
// ============================================================
//
// PACKET FORMAT (CLAUDE.md UART Streaming Hardware Contract):
//   Byte 0: target_id          [7:0]
//   Byte 1: peak_lag_H         {5'd0, peak_lag[10:8]}  (zero-padded)
//   Byte 2: peak_lag_L         peak_lag[7:0]
//   Byte 3: corr_peak_H        corr_peak_out[15:8]
//   Byte 4: corr_peak_L        corr_peak_out[7:0]
//   Byte 5: snr                [7:0]
//   Byte 6: checksum           XOR of bytes 0-5
//   Byte 7: 0xFF               end marker
//
//   corr_peak bytes carry corr_peak_out[15:8]/[7:0] — the low 16 bits of
//   the 32-bit detected magnitude. The matched filter already applies
//   CORR_SHIFT=16, so this is the documented wire field (FC-5/FC-6).
//   otr_in is carried into the module but NOT in the current 8-byte
//   format per CLAUDE.md — reserved for a future packet revision.
//
// FSM: IDLE waits for data_valid, latches all inputs. SEND_Bn states each
//   issue tx_start for 1 cycle while !tx_busy, then wait for tx_busy to
//   rise and fall before advancing. After byte 7 completes -> IDLE.
// ============================================================

module packet_framer (
    input  wire        clk,
    input  wire        rst_n,
    // from peak_detector
    input  wire [7:0]  target_id,
    input  wire [31:0] corr_peak_in,
    input  wire [7:0]  snr_in,
    input  wire [10:0] peak_lag_in,
    input  wire        otr_in,      // carried but not in current 8-byte format — reserved
    input  wire        data_valid,  // 1-cycle strobe from peak_detector
    // to uart_tx
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy
);

    // ---------------------------------------------------------------
    // FSM states: IDLE + 8 byte states (issue) each split into ISSUE/WAIT
    // by a per-byte phase flag rather than 16 explicit states.
    // ---------------------------------------------------------------
    localparam [3:0] S_IDLE = 4'd0,
                     S_B0   = 4'd1,
                     S_B1   = 4'd2,
                     S_B2   = 4'd3,
                     S_B3   = 4'd4,
                     S_B4   = 4'd5,
                     S_B5   = 4'd6,
                     S_B6   = 4'd7,
                     S_B7   = 4'd8;

    reg [3:0] state;

    // Per-byte handshake phase:
    //   PH_ISSUE: assert tx_start when !tx_busy
    //   PH_WAIT_BUSY: wait for tx_busy to go HIGH (byte accepted)
    //   PH_WAIT_DONE: wait for tx_busy to go LOW (byte finished), advance
    localparam [1:0] PH_ISSUE     = 2'd0,
                     PH_WAIT_BUSY = 2'd1,
                     PH_WAIT_DONE = 2'd2;
    reg [1:0] phase;

    // Latched packet bytes (captured at data_valid).
    reg [7:0] b0, b1, b2, b3, b4, b5, b6, b7;
    // otr is latched too so it is available for a future packet revision.
    reg       otr_latched;

    // Checksum is combinational across the latched data bytes (XOR 0-5).
    wire [7:0] checksum_w = b0 ^ b1 ^ b2 ^ b3 ^ b4 ^ b5;

    // Map state -> outgoing byte (combinational mux over latched bytes).
    reg [7:0] cur_byte;
    always @(*) begin
        case (state)
            S_B0:    cur_byte = b0;
            S_B1:    cur_byte = b1;
            S_B2:    cur_byte = b2;
            S_B3:    cur_byte = b3;
            S_B4:    cur_byte = b4;
            S_B5:    cur_byte = b5;
            S_B6:    cur_byte = b6;
            S_B7:    cur_byte = b7;
            default: cur_byte = 8'h00;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            phase       <= PH_ISSUE;
            tx_data     <= 8'h00;
            tx_start    <= 1'b0;
            b0 <= 8'h00; b1 <= 8'h00; b2 <= 8'h00; b3 <= 8'h00;
            b4 <= 8'h00; b5 <= 8'h00; b6 <= 8'h00; b7 <= 8'h00;
            otr_latched <= 1'b0;
        end else begin
            // Default: tx_start is a 1-cycle strobe.
            tx_start <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (data_valid) begin
                        // Latch the full packet. data_valid arriving during
                        // a transmit is ignored (we are not in IDLE then).
                        b0 <= target_id;
                        b1 <= {5'd0, peak_lag_in[10:8]};
                        b2 <= peak_lag_in[7:0];
                        b3 <= corr_peak_in[15:8];
                        b4 <= corr_peak_in[7:0];
                        b5 <= snr_in;
                        // checksum over the just-latched bytes; recompute
                        // explicitly here since checksum_w reads the OLD b*.
                        b6 <= target_id
                              ^ {5'd0, peak_lag_in[10:8]}
                              ^ peak_lag_in[7:0]
                              ^ corr_peak_in[15:8]
                              ^ corr_peak_in[7:0]
                              ^ snr_in;
                        b7 <= 8'hFF;
                        otr_latched <= otr_in;
                        phase <= PH_ISSUE;
                        state <= S_B0;
                    end
                end
                // -------------------------------------------------------
                // All byte states share identical handshake logic.
                S_B0, S_B1, S_B2, S_B3, S_B4, S_B5, S_B6, S_B7: begin
                    case (phase)
                        PH_ISSUE: begin
                            if (!tx_busy) begin
                                tx_data  <= cur_byte;
                                tx_start <= 1'b1;        // 1-cycle strobe
                                phase    <= PH_WAIT_BUSY;
                            end
                        end
                        PH_WAIT_BUSY: begin
                            // Wait for uart_tx to accept the byte.
                            if (tx_busy)
                                phase <= PH_WAIT_DONE;
                        end
                        PH_WAIT_DONE: begin
                            // Byte finished transmitting.
                            if (!tx_busy) begin
                                phase <= PH_ISSUE;
                                if (state == S_B7)
                                    state <= S_IDLE;     // packet complete
                                else
                                    state <= state + 4'd1;
                            end
                        end
                        default: phase <= PH_ISSUE;
                    endcase
                end
                // -------------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
