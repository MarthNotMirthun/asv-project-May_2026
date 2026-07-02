// Module: uart_rx
// Description: UART receiver, 8N1, 2-FF synchronized async input, mid-bit
//              sampling. Assembles received bytes into 4-byte
//              [addr_hi][addr_lo][data_hi][data_lo] frames for the Pi ->
//              FPGA config-write path (K_SHIFT/FLOOR/SNR_SHIFT registers,
//              and eventually matched-filter reference-chirp BSRAM loads
//              -- see FC-7, TRAJECTORY.md).
// Target: Tang Nano 20K (GW2AR-18)
// Clock: 27MHz (CLKS_PER_BIT=234 -> ~115200 baud, matches uart_tx.v exactly)
// Author: fpga-verilog-engineer agent
// Date: 2026-07-01
//
// ============================================================
// REVISION HISTORY -- protocol widened from the original 2-byte
// [addr:8][data:8] spec after dsp-signal-validator review (Stage 1B of
// the project's 6-agent pipeline, see pipeline_prompt.txt) found FOUR
// BLOCKERs against the 8-bit version:
//   1. 8-bit addr_out (256 locations) cannot reach the 2109-deep
//      reference-chirp BSRAM (needs 12 bits; 2 channels + config = 4221
//      addressable targets needed).
//   2. 8-bit data_out cannot carry a signed-16 reference-chirp sample
//      (FC-1) OR peak_detector.v's 32-bit FLOOR register (confirmed by
//      reading peak_detector.v: `input wire [31:0] FLOOR` -- FLOOR lives
//      in the same 32-bit magnitude space as corr_peak, NOT 8 bits).
//   3. No region field to disambiguate "config register" addresses from
//      "reference chirp" addresses sharing one flat space.
//   4. matched_filter_1/2.v's ref_mem has no load-complete gate against
//      the live MAC sweep -- a torn write mid-correlation would corrupt
//      the FC-6 homing gradient. (Flagged forward, NOT fixed here --
//      see "DEFERRED" section below.)
//
// FIX APPLIED (this module, items 1 & 2 only): widened the wire frame
// from 2 bytes to 4: [addr_hi:8][addr_lo:8][data_hi:8][data_lo:8],
// big-endian. This gives addr_out[15:0] (65,536 locations -- ample for
// 4221 real targets) and a proper signed 16-bit data_out matching FC-1
// exactly. hw-validation-equivalent electrical review (2-FF sync,
// mid-bit sampling, CLKS_PER_BIT=234) is unchanged from the original
// single-byte receiver FSM and still holds.
//
// DEFERRED (items 3 & 4, NOT fixed in this module -- out of scope for a
// PHY-layer UART receiver, belongs to a not-yet-built config-register-
// bank / BSRAM-loader consumer module):
//   Documented address-map CONVENTION for that future consumer to
//   enforce (uart_rx.v itself does not decode or validate these ranges,
//   it only delivers raw addr/data pairs reliably):
//     0x0000-0x0001 : FLOOR   (hi16 then lo16, two consecutive frames
//                     assembled by the consumer into one 32-bit value)
//     0x0002        : K_SHIFT (low 5 bits of data_out used, rest ignored)
//     0x0003        : SNR_SHIFT (low 5 bits of data_out used)
//     0x1000-0x183C : channel-1 (up-sweep) reference chirp, 2109 words
//     0x2000-0x283C : channel-2 (down-sweep) reference chirp, 2109 words
//   Item 4 (load-gate against matched_filter_1/2.v's live ref_mem reads)
//   requires touching already-synthesis-verified MF RTL and is
//   explicitly left for that future BSRAM-loader task -- doing it here
//   would be unplanned scope creep into critical-path RTL that
//   TRAJECTORY.md documents as "RTL UNCHANGED" (FC-7).
// ============================================================
//
// HARDWARE NOTES:
//  - `rx` is asynchronous to `clk` (Pi's UART TX runs on its own
//    free-running clock) -> passed through a 2-FF synchronizer before
//    any logic touches it (standard single-bit async-input CDC practice).
//  - Start bit re-checked at its midpoint before committing to S_DATA;
//    a bit not still low there is treated as a glitch, FSM returns to
//    S_IDLE (rejects noise on the idle-high line).
//  - Stop bit checked at frame end; a LOW stop bit (framing error)
//    silently drops the byte rather than passing corrupt data downstream.
//  - CLKS_PER_BIT=234: 27,000,000 / 115200 = 234.375 -> floor 234,
//    27e6/234 = 115,384.6 baud (+0.16% vs 115200) -- IDENTICAL divisor
//    and error already verified for uart_tx.v; RX and TX share one clock
//    domain so both directions drift together (WARNING item from
//    dsp-signal-validator: confirmed matched, no fix needed).
//
// PIN ASSIGNMENT STATUS: uart_rx.cst assigns `rx` to a CANDIDATE pin
// only. Unlike adc_interface.cst/uart_tx.cst (both verified against the
// Sipeed schematic PDF + pin-label diagram), this project's
// hw-validation agent could not be run for this module in this session
// (blocked by an unrelated tool-permission issue), so the specific
// header pad for `rx` is UNVERIFIED. Do not wire the Pi TX line to the
// FPGA using uart_rx.cst's pin until a schematic cross-check confirms
// it is a free, LVCMOS33, header-broken-out pad with no bank conflict --
// same discipline as PV-1/2/3 in TRAJECTORY.md.

module uart_rx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire              clk,
    input  wire              rst_n,       // synchronous active-low reset
    input  wire              rx,          // async serial in from Pi TX (via 2-FF sync)
    output reg  signed [15:0] data_out,   // signed-16 data word (FC-1) of the completed frame
    output reg               data_valid,  // one-cycle pulse when a full 4-byte frame is captured
    output reg        [15:0] addr_out     // 16-bit address word of the completed frame
);

    // ---- 2-FF synchronizer (CDC: rx is asynchronous to clk) ----
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // ---- Byte-level receiver FSM ----
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  rx_shift;
    reg        byte_valid;   // one-cycle pulse: byte_data holds a complete byte
    reg [7:0]  byte_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            clk_count  <= 16'd0;
            bit_index  <= 3'd0;
            rx_shift   <= 8'd0;
            byte_valid <= 1'b0;
            byte_data  <= 8'd0;
        end else begin
            byte_valid <= 1'b0;  // default: single-cycle pulse
            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (rx_sync == 1'b0) begin        // falling edge candidate
                        state <= S_START;
                    end
                end
                // -------------------------------------------------
                S_START: begin
                    // Confirm the start bit at its midpoint (glitch reject).
                    if (clk_count < (CLKS_PER_BIT / 2) - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count <= 16'd0;
                        if (rx_sync == 1'b0) begin
                            state <= S_DATA;
                        end else begin
                            state <= S_IDLE;           // was a glitch, not a start bit
                        end
                    end
                end
                // -------------------------------------------------
                S_DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count <= 16'd0;
                        rx_shift[bit_index] <= rx_sync;  // LSB first (matches uart_tx.v)
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
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 16'd1;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= S_IDLE;
                        // Stop bit must read HIGH; otherwise a framing error
                        // occurred -- drop the byte rather than propagate it.
                        if (rx_sync == 1'b1) begin
                            byte_data  <= rx_shift;
                            byte_valid <= 1'b1;
                        end
                    end
                end
                // -------------------------------------------------
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // ---- 4-byte frame assembler: [addr_hi][addr_lo][data_hi][data_lo] ----
    // Big-endian on the wire. A byte dropped by the framing-error guard
    // above shifts phase by one byte; this resyncs automatically on the
    // 4th subsequent byte since there is no length field to desync
    // further (same bounded-resync property as the original 2-byte design).
    reg [1:0]  frame_phase;   // 0=addr_hi,1=addr_lo,2=data_hi,3=data_lo
    reg [7:0]  addr_hi_latch, addr_lo_latch, data_hi_latch;

    always @(posedge clk) begin
        if (!rst_n) begin
            frame_phase   <= 2'd0;
            addr_hi_latch <= 8'd0;
            addr_lo_latch <= 8'd0;
            data_hi_latch <= 8'd0;
            addr_out      <= 16'd0;
            data_out      <= 16'sd0;
            data_valid    <= 1'b0;
        end else begin
            data_valid <= 1'b0;  // default: single-cycle pulse
            if (byte_valid) begin
                case (frame_phase)
                    2'd0: begin
                        addr_hi_latch <= byte_data;
                        frame_phase   <= 2'd1;
                    end
                    2'd1: begin
                        addr_lo_latch <= byte_data;
                        frame_phase   <= 2'd2;
                    end
                    2'd2: begin
                        data_hi_latch <= byte_data;
                        frame_phase   <= 2'd3;
                    end
                    2'd3: begin
                        addr_out   <= {addr_hi_latch, addr_lo_latch};
                        data_out   <= $signed({data_hi_latch, byte_data});
                        data_valid <= 1'b1;
                        frame_phase <= 2'd0;
                    end
                    default: frame_phase <= 2'd0;
                endcase
            end
        end
    end

endmodule
