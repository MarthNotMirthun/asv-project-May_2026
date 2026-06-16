// ============================================================
// Module:      matched_filter_2
// Description: Block cross-correlator for the 42-46 kHz LFM chirp
//              (Buoy 2). Accumulates a 2109-sample capture window
//              into BSRAM, then runs a fixed-alignment (zero-lag)
//              2109-MAC correlation against the stored reference
//              chirp. Emits corr_peak (scaled magnitude), peak_lag
//              (fixed 0 in V1), corr_valid, and OTR once per window.
// Target:      Tang Nano 20K (GW2AR-18), 27MHz system clock
// Pipeline:    fir_filter_bank2 -> THIS -> peak_detector (ch 2)
// Latency:     One result per 2109 din_valid strobes (~200 Hz at
//              421,875 SPS). MAC sweep takes ~2113 system clocks,
//              fully hidden inside the 2109*64-clock window-fill time.
// Resources:   ~1 HW multiplier (16x16 signed, time-shared),
//              4 BSRAM blocks (2 reference ROM + 2 window buffer),
//              ~200 LUTs.
// Author:      fpga-verilog-engineer agent
// Date:        2026-06-16
// ============================================================
//
// ARCHITECTURE (FIX-B1 — BLOCK correlation, NOT sliding):
//   A per-sample sliding correlation needs 2109 MACs per input sample,
//   but samples arrive only every 64 system clocks (27e6 / 421,875).
//   2109 >> 64, so a single-MAC sliding datapath cannot keep up.
//   Instead: buffer 2109 samples into a window BSRAM, then after the
//   window fills, sweep 2109 MACs (1 per clock) against the reference
//   BSRAM and emit ONE result. 200 Hz output >> 20 Hz UART rate (10x
//   margin). No per-sample recomputation anywhere.
//   Verification: corr_valid pulses once every 2109 din_valid strobes.
//
// ACCUMULATOR / SCALING CONTRACT (FIX-B2, FIX-B3 — the 48->32->16 chain):
//   Worst-case |sum| = 2109 * (32767 * 32767) = 2.264e12.
//   log2(2.264e12) = 41.04 -> 43 bits minimum. Internal accumulator is
//   48-bit signed (byte-aligned, ~5 bits of margin) so it can NEVER
//   wrap. Wrapping would invert the SNR gradient and steer the vehicle
//   AWAY from the buoy, so this width is mandatory.
//
//   corr_peak = accumulator >>> CORR_SHIFT, saturating to signed 32-bit.
//   CORR_SHIFT = 16 is the DOCUMENTED scaling contract for the
//   downstream peak_detector. UART TX sends corr_peak[31:16] (the upper
//   16 bits of the 32-bit output) in packet bytes 3-4. The peak_detector
//   computes snr = corr_peak / noise_floor with BOTH operands in this
//   same >>>16 scale. Any module that consumes corr_peak MUST assume
//   CORR_SHIFT = 16. Do not change CORR_SHIFT without updating
//   peak_detector and the UART packing simultaneously.
//
// REFERENCE CHIRP FORMAT (FIX-W3, FC-1 — signed-16 INTEGER, NOT Q1.15):
//   The reference chirp is loaded into BSRAM via ref_wr_en/ref_addr/
//   ref_din at signed-16 INTEGER scale, matching the FIR-bank output
//   amplitude (~6640 counts for a 1Vpp signal at this gain) — NOT a
//   x32768 Q1.15 normalization. The Pi's fpga_uart_node loads the
//   reference over UART before correlation is enabled. Do NOT
//   reintroduce Q1.15 scaling at this stage boundary.
//
// LAG SEARCH SCOPE (FIX-W2, FC-5 — V1 coarse, zero lag only):
//   A full 2109x2109 lag search is ~4.4M MACs, far over the per-block
//   budget. V1 implements a FIXED-ALIGNMENT (zero-lag) correlation only;
//   peak_lag is hard-tied to 0. peak_lag is diagnostic / a hook for the
//   V2 TDOA dual-receiver bearing upgrade — it is NOT converted to range
//   (NO ToF, NO range_cm — FC-5). The homing algorithm uses corr_peak /
//   snr only (FC-6). The 11-bit width leaves room for future multi-lag.
//
// OTR PROPAGATION (FIX-W1, FC-2 — window-OR semantics):
//   otr_in is OR-latched across all 2109 samples of the current window
//   and emitted as otr_out alongside corr_valid. Samples are NEVER
//   dropped when otr_in=1 (dropping would misalign the lag axis); the
//   sample is buffered regardless and only the flag is OR'd.
// ============================================================

module matched_filter_2 (
    input  wire        clk,            // 27 MHz system clock
    input  wire        rst_n,          // synchronous active-low reset
    // Data input from FIR bank 2
    input  wire signed [15:0] din,     // signed-16 INTEGER scale (per FC-1)
    input  wire        din_valid,      // 1-clk strobe, ~421,875 SPS rate
    input  wire        otr_in,         // over-range from fir_filter_bank2
    // Reference chirp BSRAM load interface (from Pi via UART)
    input  wire        ref_wr_en,      // write enable for reference BSRAM
    input  wire [11:0] ref_addr,       // 12-bit address (0..2108) — FIX-N1
    input  wire signed [15:0] ref_din, // reference sample (integer scale) — FIX-W3
    // Outputs
    output reg  signed [31:0] corr_peak, // accumulator>>>CORR_SHIFT, saturating — FIX-B2/B3
    output reg  [10:0] peak_lag,       // FIX-W2: always 0 in V1, diagnostic
    output reg         corr_valid,     // 1-clk strobe when outputs valid
    output reg         otr_out         // FIX-W1: OR of otr_in across last window
);

    // ---------------------------------------------------------------
    // Parameters / contracts
    // ---------------------------------------------------------------
    localparam integer N_TAPS     = 2109;          // FIX-N4: window length (5ms @ 421,875 SPS)
    localparam integer CORR_SHIFT = 16;            // FIX-B3: scaling contract for peak_detector
    localparam integer ADDR_W     = 12;            // FIX-N1: 12-bit addr (2109 > 2^11)
    localparam integer ACCW       = 48;            // FIX-B2: 48-bit accumulator, no wrap

    // Saturating clamp limits for the 32-bit corr_peak output (FIX-B2).
    localparam signed [31:0] CORR_MAX = 32'sh7FFF_FFFF;
    localparam signed [31:0] CORR_MIN = -32'sh8000_0000;

    // ---------------------------------------------------------------
    // FIX-N2: two inferred BSRAMs (window buffer + reference ROM).
    // Window buffer: written as live samples arrive, read during MAC sweep.
    // Reference ROM: written by the Pi load interface, read during MAC sweep.
    // Both 2109x16; Gowin maps each to ~2 of the 18Kbit blocks.
    // ---------------------------------------------------------------
    reg signed [15:0] window_mem [0:N_TAPS-1];
    reg signed [15:0] ref_mem    [0:N_TAPS-1];

    // Reference BSRAM write port (Pi load path). Independent of correlation.
    always @(posedge clk) begin
        if (ref_wr_en)
            ref_mem[ref_addr] <= ref_din;
    end

    // ---------------------------------------------------------------
    // Window fill state
    // ---------------------------------------------------------------
    reg [ADDR_W-1:0] fill_addr;     // next window write index (0..N_TAPS-1)
    reg              window_full;   // pulses high for 1 clk when fill completes
    reg              otr_latch;     // FIX-W1: OR of otr_in across the window

    // ---------------------------------------------------------------
    // MAC sweep state
    // ---------------------------------------------------------------
    localparam ST_IDLE = 2'd0;      // waiting for a full window
    localparam ST_MAC  = 2'd1;      // issuing operand pairs / accumulating
    localparam ST_DONE = 2'd2;      // drain last product, emit result

    reg [1:0]            state;
    reg [ADDR_W-1:0]     mac_addr;      // operand index being issued (0..N_TAPS)
    reg [ADDR_W-1:0]     acc_cnt;       // products accumulated so far (0..N_TAPS)
    reg signed [ACCW-1:0] acc;          // FIX-B2: 48-bit accumulator

    // Operand registers + 1-cycle-pipelined product (FC: pipeline all MACs).
    reg signed [15:0]     mul_a, mul_b;
    reg signed [31:0]     prod;          // 16x16 -> 32-bit product
    reg                   prod_pend;     // a freshly-issued product valid next cycle
    reg                   otr_hold;      // window OTR snapshot, held during MAC sweep

    // Sign-extend the 32-bit product to the 48-bit accumulator width.
    wire signed [ACCW-1:0] prod_ext = {{(ACCW-32){prod[31]}}, prod};

    // FIX-B2/B3: arithmetic right-shift by CORR_SHIFT, then saturate to 32-bit.
    wire signed [ACCW-1:0] acc_shifted = acc >>> CORR_SHIFT;

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            fill_addr   <= {ADDR_W{1'b0}};
            window_full <= 1'b0;
            otr_latch   <= 1'b0;
            state       <= ST_IDLE;
            mac_addr    <= {ADDR_W{1'b0}};
            acc_cnt     <= {ADDR_W{1'b0}};
            acc         <= {ACCW{1'b0}};
            mul_a       <= 16'sd0;
            mul_b       <= 16'sd0;
            prod        <= 32'sd0;
            prod_pend   <= 1'b0;
            otr_hold    <= 1'b0;
            corr_peak   <= 32'sd0;
            peak_lag    <= 11'd0;
            corr_valid  <= 1'b0;
            otr_out     <= 1'b0;
        end else begin
            // Defaults: single-cycle strobes.
            corr_valid  <= 1'b0;
            otr_out     <= 1'b0;
            window_full <= 1'b0;

            // -----------------------------------------------------------
            // WINDOW FILL (runs continuously, independent of MAC sweep).
            // FIX-W1: load every sample regardless of otr_in; OR the flag.
            // -----------------------------------------------------------
            if (din_valid) begin
                window_mem[fill_addr] <= din;
                // OR otr across the window. Seed on the first sample (addr 0).
                if (fill_addr == {ADDR_W{1'b0}})
                    otr_latch <= otr_in;
                else
                    otr_latch <= otr_latch | otr_in;

                if (fill_addr == N_TAPS - 1) begin
                    fill_addr   <= {ADDR_W{1'b0}};
                    window_full <= 1'b1;        // trigger a MAC sweep
                end else begin
                    fill_addr <= fill_addr + 1'b1;
                end
            end

            // -----------------------------------------------------------
            // PIPELINED MULTIPLY (always registers current operands).
            // -----------------------------------------------------------
            prod <= mul_a * mul_b;

            // Accumulate the product issued on the PREVIOUS cycle.
            if (prod_pend) begin
                acc     <= acc + prod_ext;
                acc_cnt <= acc_cnt + 1'b1;
            end
            prod_pend <= 1'b0;   // default; set when a new operand pair is issued

            // -----------------------------------------------------------
            // MAC SWEEP STATE MACHINE
            // -----------------------------------------------------------
            case (state)
                // -------------------------------------------------------
                ST_IDLE: begin
                    if (window_full) begin
                        // Snapshot the window's OTR so a NEW fill that has
                        // already started cannot corrupt this result.
                        otr_hold  <= otr_latch;
                        // Begin the sweep: issue tap-0 operands.
                        acc       <= {ACCW{1'b0}};
                        acc_cnt   <= {ADDR_W{1'b0}};
                        mul_a     <= window_mem[0];
                        mul_b     <= ref_mem[0];
                        prod_pend <= 1'b1;
                        mac_addr  <= 12'd1;       // next operand index
                        state     <= ST_MAC;
                    end
                end
                // -------------------------------------------------------
                ST_MAC: begin
                    if (mac_addr < N_TAPS) begin
                        mul_a     <= window_mem[mac_addr];
                        mul_b     <= ref_mem[mac_addr];
                        prod_pend <= 1'b1;
                        mac_addr  <= mac_addr + 1'b1;
                    end else begin
                        // All N_TAPS operand pairs issued; last product draining.
                        state <= ST_DONE;
                    end
                end
                // -------------------------------------------------------
                ST_DONE: begin
                    // Wait until every product has been accumulated.
                    if (acc_cnt == N_TAPS[ADDR_W-1:0]) begin
                        // FIX-B2/B3: shift to the 32-bit scale, saturating clamp.
                        if (acc_shifted > CORR_MAX)
                            corr_peak <= CORR_MAX;
                        else if (acc_shifted < CORR_MIN)
                            corr_peak <= CORR_MIN;
                        else
                            corr_peak <= acc_shifted[31:0];

                        peak_lag   <= 11'd0;            // FIX-W2: fixed 0 in V1
                        otr_out    <= otr_hold;         // FIX-W1: window OTR
                        corr_valid <= 1'b1;             // FIX-B1: one pulse per window
                        state      <= ST_IDLE;
                    end
                end
                // -------------------------------------------------------
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
