// ============================================================
// Module:      peak_detector
// Description: Dual-channel active-target selector for the two
//              sweep-direction matched filters (Buoy 1 = up-sweep
//              ch1, Buoy 2 = down-sweep ch2). Takes |corr_peak| of
//              each channel, applies RELATIVE (ratio) gating with an
//              absolute FLOOR, emits target_id / corr_peak / snr /
//              peak_lag / otr for the packet_framer. SNR-gradient
//              homing per FC-5/FC-6 — NO range/ToF conversion.
// Target:      Tang Nano 20K (GW2AR-18), 27MHz system clock
// Pipeline:    matched_filter_1/2 -> THIS -> packet_framer -> uart_tx
// Latency:     Detection result registered 2 clocks after the second
//              corr_valid strobe of a window pair (abs stage + latch
//              stage + decision stage are pipelined).
// Resources:   ~150 LUTs, 0 multipliers, 0 BSRAM (all compares/shifts
//              in registers; no noise-floor history buffer).
// Author:      fpga-verilog-engineer agent
// Date:        2026-06-17
// ============================================================
//
// FC-7 DUAL-CHANNEL RELATIVE GATING (MANDATORY):
//   ch1 = Buoy 1 (UP-sweep), ch2 = Buoy 2 (DOWN-sweep). Both share the
//   38.5-41.5 kHz passband; sweep direction is the only discriminator.
//   Sweep-direction isolation is only ~12.2 dB while the near/far signal
//   spread across 1-10 m in air is ~33 dB. A single fixed absolute
//   threshold CANNOT separate genuine far Buoy 2 from near Buoy 1's
//   crosstalk into ch2. The relative (ratio) gate is invariant to
//   absolute level and tracks geometry automatically:
//     ch1_dominant = (abs_ch1 > (abs_ch2 << K_SHIFT)) && (abs_ch1 > FLOOR)
//     ch2_dominant = (abs_ch2 > (abs_ch1 << K_SHIFT)) && (abs_ch2 > FLOOR)
//   Neither / both / stale -> target_id = 0x00 (NEVER guess a target).
//   Single-channel absolute thresholding is FORBIDDEN.
//
// ABSOLUTE VALUE (FC-7): free-running correlation against an
//   unsynchronized buoy produces NEGATIVE corr_peak values routinely.
//   Signed '>' comparisons would break, so both inputs are converted to
//   unsigned 32-bit magnitude BEFORE any compare or SNR computation.
//   |-2^31| overflows 32 bits by exactly one code; corr_peak from the
//   matched filter saturates to CORR_MIN = -2^31 only at full clip, so we
//   clamp abs(-2^31) to 2^31-1 (0x7FFF_FFFF) to keep all math in 32 bits.
//
// CROSS-EPOCH STALENESS (cross-epoch protection): each channel's latched
//   magnitude carries an age counter that resets on its own corr_valid
//   and increments every clock otherwise. If age exceeds one full
//   correlation window pair (2 * N_TAPS = 4218 clocks) the channel is
//   marked stale and excluded from detection, so a fresh ch2 result can
//   never be compared against a stale ch1 result from a prior window.
//
// SCALING CONTRACT (matched_filter CORR_SHIFT=16): corr_peak arrives
//   already >>>16-scaled. snr is a saturating right-shift proxy of the
//   detected channel's magnitude (snr = saturate(|peak| >> SNR_SHIFT, 8)),
//   monotonically increasing with corr_peak_out -> valid homing gradient.
//
// OTR (FC-2): otr_out = latch_otr1 | latch_otr2, ALWAYS, regardless of
//   detection result, so saturated readings always reach the Pi.
// ============================================================

module peak_detector (
    input  wire        clk,
    input  wire        rst_n,

    // Channel 1 (Buoy 1, up-sweep matched filter)
    input  wire signed [31:0] corr_peak_ch1,
    input  wire [10:0] peak_lag_ch1,
    input  wire        otr_ch1,
    input  wire        corr_valid_ch1,

    // Channel 2 (Buoy 2, down-sweep matched filter)
    input  wire signed [31:0] corr_peak_ch2,
    input  wire [10:0] peak_lag_ch2,
    input  wire        otr_ch2,
    input  wire        corr_valid_ch2,

    // UART-loadable config registers (synthesizable, hardcoded defaults
    // for now via reset values — uart_rx config-write path deferred Week 5)
    input  wire [4:0]  K_SHIFT,     // ratio gate shift: detect ch1 when |ch1| > (|ch2| << K_SHIFT)
    input  wire [31:0] FLOOR,       // minimum absolute detection threshold (unsigned)
    input  wire [4:0]  SNR_SHIFT,   // SNR proxy: snr = saturate(|corr_peak| >> SNR_SHIFT, 8)

    // Outputs to packet_framer
    output reg  [7:0]  target_id,    // 8'h01=Buoy1, 8'h02=Buoy2, 8'h00=neither
    output reg  [31:0] corr_peak_out,// magnitude of detected channel (unsigned after abs)
    output reg  [7:0]  snr_out,
    output reg  [10:0] peak_lag_out,
    output reg         otr_out,      // FC-2: otr_ch1 | otr_ch2
    output reg         data_valid    // 1-cycle strobe when outputs are updated
);

    // ---------------------------------------------------------------
    // Parameters / contracts
    // ---------------------------------------------------------------
    localparam integer N_TAPS    = 2109;          // matched-filter window length (FC-3 derived)
    // Age beyond one full window-pair (2*N_TAPS) marks a channel stale.
    localparam integer STALE_MAX = 2 * N_TAPS;    // 4218 clocks
    // Age counter width: must hold STALE_MAX without wrapping. 4218 < 2^13.
    localparam integer AGE_W     = 13;
    localparam [AGE_W-1:0] AGE_LIMIT = STALE_MAX[AGE_W-1:0]; // 4218
    localparam [AGE_W-1:0] AGE_HOLD  = {AGE_W{1'b1}};        // saturate value (8191)

    // abs() saturation cap: |-2^31| clamped to +2^31-1 to stay in 32 bits.
    localparam [31:0] ABS_MAX = 32'h7FFF_FFFF;

    // ---------------------------------------------------------------
    // Stage 0: combinational absolute value of each input
    // (blocking '=' here is illegal inside a clocked block; use a wire net)
    // ---------------------------------------------------------------
    // corr_peak_chN[31] is the sign bit. Negate when negative, clamp the
    // single overflow code (-2^31) to ABS_MAX.
    wire [31:0] abs_ch1_w = corr_peak_ch1[31]
                          ? ((corr_peak_ch1 == 32'sh8000_0000) ? ABS_MAX
                                                               : (~corr_peak_ch1 + 32'd1))
                          : corr_peak_ch1;
    wire [31:0] abs_ch2_w = corr_peak_ch2[31]
                          ? ((corr_peak_ch2 == 32'sh8000_0000) ? ABS_MAX
                                                               : (~corr_peak_ch2 + 32'd1))
                          : corr_peak_ch2;

    // ---------------------------------------------------------------
    // Stage 1: per-channel latches + age counters + seen flags
    // ---------------------------------------------------------------
    reg [31:0]      latch_abs1, latch_abs2;
    reg [10:0]      latch_lag1, latch_lag2;
    reg             latch_otr1, latch_otr2;
    reg [AGE_W-1:0] age_ch1, age_ch2;
    reg             seen_ch1, seen_ch2;    // has this channel ever produced a result?

    // Staleness (combinational view of the latched age)
    wire ch1_stale = (age_ch1 >= AGE_LIMIT);
    wire ch2_stale = (age_ch2 >= AGE_LIMIT);

    // ---------------------------------------------------------------
    // Stage 2: relative gating (registered shifts to avoid a long combo path)
    // Shift amount is K_SHIFT (<=31). A 64-bit shifted operand prevents
    // the comparison from wrapping when abs<<K_SHIFT exceeds 32 bits — a
    // wrapped compare is exactly the false-positive case FC-7 forbids.
    // ---------------------------------------------------------------
    wire [63:0] abs1_64        = {32'd0, latch_abs1};
    wire [63:0] abs2_64        = {32'd0, latch_abs2};
    wire [63:0] abs2_scaled    = abs2_64 << K_SHIFT;   // |ch2| << K_SHIFT
    wire [63:0] abs1_scaled    = abs1_64 << K_SHIFT;   // |ch1| << K_SHIFT

    wire ch1_dominant = (abs1_64 > abs2_scaled) && (latch_abs1 > FLOOR);
    wire ch2_dominant = (abs2_64 > abs1_scaled) && (latch_abs2 > FLOOR);

    // A detection decision is computed whenever either channel reports a
    // new valid AND both channels have been seen at least once. A channel
    // counts as "seen" if it was seen on a prior cycle OR is reporting its
    // valid this same cycle (so the very first window pair decides too).
    wire seen1_now = seen_ch1 | corr_valid_ch1;
    wire seen2_now = seen_ch2 | corr_valid_ch2;
    wire decide = (corr_valid_ch1 | corr_valid_ch2) & seen1_now & seen2_now;
    // Register the decide trigger so the decision uses the latch values
    // updated THIS cycle (latches and decide-pipe move together).
    reg decide_q;

    // ---------------------------------------------------------------
    // Saturating SNR proxy helper (combinational on the detected magnitude)
    // snr = (|peak| >> SNR_SHIFT) saturated to 8 bits (0xFF if > 255).
    // ---------------------------------------------------------------
    function [7:0] snr_proxy;
        input [31:0] mag;
        input [4:0]  shift;
        reg   [31:0] shifted;
        begin
            shifted = mag >> shift;
            if (shifted > 32'd255)
                snr_proxy = 8'hFF;
            else
                snr_proxy = shifted[7:0];
        end
    endfunction

    // ---------------------------------------------------------------
    // Main clocked process
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            latch_abs1    <= 32'd0;
            latch_abs2    <= 32'd0;
            latch_lag1    <= 11'd0;
            latch_lag2    <= 11'd0;
            latch_otr1    <= 1'b0;
            latch_otr2    <= 1'b0;
            age_ch1       <= AGE_HOLD;   // start stale until first real result
            age_ch2       <= AGE_HOLD;
            seen_ch1      <= 1'b0;
            seen_ch2      <= 1'b0;
            decide_q      <= 1'b0;

            target_id     <= 8'h00;
            corr_peak_out <= 32'd0;
            snr_out       <= 8'd0;
            peak_lag_out  <= 11'd0;
            otr_out       <= 1'b0;
            data_valid    <= 1'b0;
        end else begin
            // Defaults: single-cycle strobe.
            data_valid <= 1'b0;

            // -----------------------------------------------------------
            // Stage 1: latch on each channel's valid; age otherwise.
            // -----------------------------------------------------------
            if (corr_valid_ch1) begin
                latch_abs1 <= abs_ch1_w;
                latch_lag1 <= peak_lag_ch1;
                latch_otr1 <= otr_ch1;
                age_ch1    <= {AGE_W{1'b0}};
                seen_ch1   <= 1'b1;
            end else if (age_ch1 != AGE_HOLD) begin
                age_ch1    <= age_ch1 + 1'b1;   // saturate; never wrap past AGE_HOLD
            end

            if (corr_valid_ch2) begin
                latch_abs2 <= abs_ch2_w;
                latch_lag2 <= peak_lag_ch2;
                latch_otr2 <= otr_ch2;
                age_ch2    <= {AGE_W{1'b0}};
                seen_ch2   <= 1'b1;
            end else if (age_ch2 != AGE_HOLD) begin
                age_ch2    <= age_ch2 + 1'b1;
            end

            // Pipeline the decide trigger one cycle so the decision below
            // sees the latch values written by THIS same clock edge.
            decide_q <= decide;

            // -----------------------------------------------------------
            // Stage 2: detection decision (registered) on a decide event.
            // -----------------------------------------------------------
            if (decide_q) begin
                // OTR always propagates (FC-2), independent of detection.
                otr_out <= latch_otr1 | latch_otr2;

                if (ch1_dominant && !ch2_dominant && !ch1_stale && !ch2_stale) begin
                    target_id     <= 8'h01;
                    corr_peak_out <= latch_abs1;
                    snr_out       <= snr_proxy(latch_abs1, SNR_SHIFT);
                    peak_lag_out  <= latch_lag1;        // FC-5 diagnostic passthrough
                end else if (ch2_dominant && !ch1_dominant && !ch1_stale && !ch2_stale) begin
                    target_id     <= 8'h02;
                    corr_peak_out <= latch_abs2;
                    snr_out       <= snr_proxy(latch_abs2, SNR_SHIFT);
                    peak_lag_out  <= latch_lag2;
                end else begin
                    // Neither / both-high / tie / stale -> never guess.
                    target_id     <= 8'h00;
                    corr_peak_out <= 32'd0;
                    snr_out       <= 8'd0;
                    peak_lag_out  <= 11'd0;             // FC-5: 0 when neither
                end

                data_valid <= 1'b1;   // 1-cycle strobe: outputs updated
            end
        end
    end

endmodule
