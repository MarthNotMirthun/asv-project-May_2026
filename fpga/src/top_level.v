// ============================================================
// Module:      top_level
// Description: Full ASV acoustic-homing FPGA pipeline. Chains all 9
//              verified modules end to end:
//                AD9226 capture -> CIC decimation -> dual FIR banks ->
//                dual matched-filter correlators -> peak detector /
//                active-target selector -> 8-byte packet framer ->
//                UART TX to the Pi /dev/ttyAMA0.
// Target:      Tang Nano 20K (GW2AR-18), 27MHz system clock
// Pipeline:    AD9226 -> adc_interface -> cic_decimator ->
//              fir_filter_bank1/2 -> matched_filter_1/2 ->
//              peak_detector -> packet_framer -> uart_tx -> Pi UART
// Latency:     Dominated by the 2109-sample matched-filter window:
//              2109 samples * 64 sys clk/sample ~= 134,976 clocks
//              (~5 ms) to the first correlation result, then ~200 Hz.
// Resources:   ~4 of 48 HW multipliers (1 per FIR bank, 1 per matched
//              filter), ~14 of 46 BSRAM blocks (matched-filter window +
//              reference arrays), well within budget.
// Author:      fpga-verilog-engineer agent
// Date:        2026-06-29
// ============================================================
//
// FIX-W1: the ENCODE output port is named exactly `adc_clk` so it matches
//   the IO_LOC "adc_clk" string in top_level.cst (Gowin matches IO_LOC by
//   exact port name). Do NOT rename it to adc_clk_out.
//
// FIX-W3 (target_id autonomy): peak_detector emits target_id = 1/2/0
//   AUTONOMOUSLY via FC-7 relative (ratio) gating — the FPGA receives NO
//   active-buoy command. The Pi's fpga_uart_node MUST filter incoming
//   packets by the mission state machine's currently-expected buoy; a
//   packet whose target_id does not match the active mission leg is
//   discarded on the Pi side, not here.
//
// FIX-N2 (reference chirp routing): the two matched-filter reference ROMs
//   are loaded by the Pi over UART (a separate uart_rx config path, Week 6).
//   ROUTING CONTRACT: up-sweep reference -> matched_filter_1 (mf1),
//   down-sweep reference -> matched_filter_2 (mf2). The Pi MUST load them
//   in this order. In this top level the ref-load ports are tied off
//   (FIX-B2) until the uart_rx load path is integrated; correlation against
//   an all-zero reference yields corr_peak = 0 (safe: no false detection).
// ============================================================

module top_level (
    input  wire        clk,          // 27MHz system clock        (top_level.cst pin 4)
    input  wire        rst_n,        // synchronous active-low rst (top_level.cst pin 88, S1)
    input  wire [11:0] adc_data,     // AD9226 parallel data D[11:0]
    input  wire        adc_otr,      // AD9226 OTR pin
    output wire        uart_tx_out,  // serial TX to Pi /dev/ttyAMA0 (top_level.cst pin 86)
    output wire        adc_clk       // FIX-W1: ENCODE clock to AD9226 — name MUST be adc_clk
);

    // ===========================================================
    // FIX-B1: peak_detector config constants (K_SHIFT / FLOOR /
    // SNR_SHIFT are INPUT PORTS on peak_detector, not parameters —
    // they must be driven here).
    //   K_SHIFT  = 2  -> ratio gate: detect ch1 when |ch1| > (|ch2| << 2)
    //                    = 4x dominance (and vice-versa for ch2).
    //   FLOOR    = 0  -> permissive absolute floor for bring-up.
    //   SNR_SHIFT= 12 -> snr = saturate(|peak| >> 12, 8); gradient alive
    //                    to magnitudes ~1M before saturating at 0xFF.
    // ===========================================================
    localparam [4:0]  PD_K_SHIFT   = 5'd2;
    localparam [31:0] PD_FLOOR     = 32'd0;
    localparam [4:0]  PD_SNR_SHIFT = 5'd12;

    // ===========================================================
    // Inter-module nets (FIX-W2: every valid + OTR + data strobe wired).
    // ===========================================================

    // adc_interface -> cic_decimator
    wire signed [11:0] adc_sample;
    wire               adc_sample_valid;
    wire               adc_sample_otr;

    // cic_decimator -> both FIR banks
    wire signed [15:0] cic_dout;
    wire               cic_dout_valid;
    wire               cic_otr_out;

    // fir_filter_bank1 -> matched_filter_1
    wire signed [15:0] fir1_dout;
    wire               fir1_dout_valid;
    wire               fir1_otr_out;

    // fir_filter_bank2 -> matched_filter_2
    wire signed [15:0] fir2_dout;
    wire               fir2_dout_valid;
    wire               fir2_otr_out;

    // matched_filter_1 -> peak_detector (ch1)
    wire signed [31:0] mf1_corr_peak;
    wire [10:0]        mf1_peak_lag;
    wire               mf1_corr_valid;
    wire               mf1_otr_out;

    // matched_filter_2 -> peak_detector (ch2)
    wire signed [31:0] mf2_corr_peak;
    wire [10:0]        mf2_peak_lag;
    wire               mf2_corr_valid;
    wire               mf2_otr_out;

    // peak_detector -> packet_framer
    wire [7:0]         pd_target_id;
    wire [31:0]        pd_corr_peak_out;
    wire [7:0]         pd_snr_out;
    wire [10:0]        pd_peak_lag_out;
    wire               pd_otr_out;
    wire               pd_data_valid;

    // packet_framer <-> uart_tx
    wire [7:0]         framer_tx_data;
    wire               framer_tx_start;
    wire               uart_tx_busy;

    // ===========================================================
    // Stage 1: AD9226 parallel capture + ENCODE generation
    // ===========================================================
    adc_interface u_adc (
        .clk          (clk),
        .rst_n        (rst_n),
        .adc_data     (adc_data),
        .otr          (adc_otr),
        .adc_clk      (adc_clk),            // FIX-W1: ENCODE out, exact name
        .sample_out   (adc_sample),
        .sample_otr   (adc_sample_otr),
        .sample_valid (adc_sample_valid)
    );

    // ===========================================================
    // Stage 2: CIC decimation (3.375MHz -> 421.875kSPS, R=8 N=3)
    // FIX-W2: adc.sample_valid -> cic.din_valid, adc.sample_otr -> cic.otr_in
    // ===========================================================
    cic_decimator u_cic (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (adc_sample),
        .din_valid  (adc_sample_valid),
        .otr_in     (adc_sample_otr),
        .dout       (cic_dout),
        .dout_valid (cic_dout_valid),
        .otr_out    (cic_otr_out)
    );

    // ===========================================================
    // Stage 3a: FIR bandpass bank 1 (38.5-41.5kHz, up-sweep path)
    // FIX-W2: cic.dout/_valid/otr fan out to BOTH FIR banks identically.
    // ===========================================================
    fir_filter_bank1 u_fir1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (cic_dout),
        .din_valid  (cic_dout_valid),
        .otr_in     (cic_otr_out),
        .dout       (fir1_dout),
        .dout_valid (fir1_dout_valid),
        .otr_out    (fir1_otr_out)
    );

    // ===========================================================
    // Stage 3b: FIR bandpass bank 2 (38.5-41.5kHz, down-sweep path)
    // ===========================================================
    fir_filter_bank2 u_fir2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (cic_dout),
        .din_valid  (cic_dout_valid),
        .otr_in     (cic_otr_out),
        .dout       (fir2_dout),
        .dout_valid (fir2_dout_valid),
        .otr_out    (fir2_otr_out)
    );

    // ===========================================================
    // Stage 4a: matched filter 1 (up-sweep reference, Buoy 1, ch1)
    // FIX-B2: ref-load ports tied off safely (ref_wr_en LOW prevents a
    //   stuck-high write from corrupting the reference ROM). The Pi's
    //   uart_rx load path (Week 6) will drive these instead. FIX-N2:
    //   up-sweep reference routes here.
    // ===========================================================
    matched_filter_1 u_mf1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (fir1_dout),
        .din_valid  (fir1_dout_valid),
        .otr_in     (fir1_otr_out),
        // FIX-B2: safe tie-off of the reference-load interface
        .ref_wr_en  (1'b0),
        .ref_addr   (12'd0),
        .ref_din    (16'sd0),
        .corr_peak  (mf1_corr_peak),
        .peak_lag   (mf1_peak_lag),
        .corr_valid (mf1_corr_valid),
        .otr_out    (mf1_otr_out)
    );

    // ===========================================================
    // Stage 4b: matched filter 2 (down-sweep reference, Buoy 2, ch2)
    // FIX-B2: ref-load ports tied off safely. FIX-N2: down-sweep here.
    // ===========================================================
    matched_filter_2 u_mf2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (fir2_dout),
        .din_valid  (fir2_dout_valid),
        .otr_in     (fir2_otr_out),
        // FIX-B2: safe tie-off of the reference-load interface
        .ref_wr_en  (1'b0),
        .ref_addr   (12'd0),
        .ref_din    (16'sd0),
        .corr_peak  (mf2_corr_peak),
        .peak_lag   (mf2_peak_lag),
        .corr_valid (mf2_corr_valid),
        .otr_out    (mf2_otr_out)
    );

    // ===========================================================
    // Stage 5: peak detector / active-target selector
    // FIX-B1: config ports driven by localparam constants.
    // FIX-W2: mf1/mf2 corr_peak/peak_lag/corr_valid/otr wired to the
    //   matching ch1/ch2 ports.
    // ===========================================================
    peak_detector u_pd (
        .clk            (clk),
        .rst_n          (rst_n),
        // Channel 1 (matched_filter_1, up-sweep)
        .corr_peak_ch1  (mf1_corr_peak),
        .peak_lag_ch1   (mf1_peak_lag),
        .otr_ch1        (mf1_otr_out),
        .corr_valid_ch1 (mf1_corr_valid),
        // Channel 2 (matched_filter_2, down-sweep)
        .corr_peak_ch2  (mf2_corr_peak),
        .peak_lag_ch2   (mf2_peak_lag),
        .otr_ch2        (mf2_otr_out),
        .corr_valid_ch2 (mf2_corr_valid),
        // FIX-B1: config constants
        .K_SHIFT        (PD_K_SHIFT),
        .FLOOR          (PD_FLOOR),
        .SNR_SHIFT      (PD_SNR_SHIFT),
        // Outputs
        .target_id      (pd_target_id),
        .corr_peak_out  (pd_corr_peak_out),
        .snr_out        (pd_snr_out),
        .peak_lag_out   (pd_peak_lag_out),
        .otr_out        (pd_otr_out),
        .data_valid     (pd_data_valid)
    );

    // ===========================================================
    // Stage 6: 8-byte packet framer
    // FIX-W2: pd.* -> framer.*, framer.tx_data/tx_start -> uart, uart.tx_busy -> framer
    // FIX-B3 (in packet_framer.v): bytes 3-4 = saturating (corr_peak>>6).
    // ===========================================================
    packet_framer u_framer (
        .clk          (clk),
        .rst_n        (rst_n),
        .target_id    (pd_target_id),
        .corr_peak_in (pd_corr_peak_out),
        .snr_in       (pd_snr_out),
        .peak_lag_in  (pd_peak_lag_out),
        .otr_in       (pd_otr_out),
        .data_valid   (pd_data_valid),
        .tx_data      (framer_tx_data),
        .tx_start     (framer_tx_start),
        .tx_busy      (uart_tx_busy)
    );

    // ===========================================================
    // Stage 7: UART transmitter (8N1, 115200 baud @ 27MHz, CLKS_PER_BIT=234)
    // ===========================================================
    uart_tx u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (framer_tx_start),
        .tx_data  (framer_tx_data),
        .tx       (uart_tx_out),
        .tx_busy  (uart_tx_busy)
    );

endmodule
