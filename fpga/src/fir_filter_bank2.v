// ============================================================
// Module:      fir_filter_bank2
// Description: 32-tap symmetric linear-phase bandpass FIR, 42-46kHz
//              (Buoy 2 chirp band, center 44kHz). Sequential 1-MAC-per-
//              clock datapath; one output sample per input sample.
// Target:      Tang Nano 20K (GW2AR-18), 27MHz system clock
// Pipeline:    cic_decimator -> THIS -> matched_filter (bank 2)
// Latency:     dout ready ~35 system clocks after a din_valid strobe
//              (load + N MAC issue/accumulate cycles + output register);
//              dout_valid co-registered with dout.
// Resources:   ~1 HW multiplier (16x16 signed, time-shared), ~120 LUTs,
//              0 BSRAM (coeffs are compile-time constants).
// Author:      fpga-verilog-engineer agent
// Date:        2026-06-10
// ============================================================
//
// COEFFICIENT DESIGN (windowed-sinc bandpass, Hamming window)
//   fs = 421875 Hz EXACTLY (CIC output rate, NOT 400000 — see CLAUDE.md)
//   N  = 32 taps, passband 42-46kHz, design bandwidth 4kHz, center 44kHz.
//   Q1.15: q[i] = round(float[i] * 32768), clamped to [-32768,+32767].
//   Symmetric: h[i] == h[31-i] (verified). Max |coeff| = 587 -> no Q1.15 overflow.
//
//   Q1.15 taps:
//     -36, -54, -59, -33,  42, 150, 233, 219,
//      70,-177,-411,-500,-365, -39, 337, 587,
//     587, 337, -39,-365,-500,-411,-177,  70,
//     219, 233, 150,  42, -33, -59, -54, -36
//
//   ACHIEVED SELECTIVITY (honest, simulation-confirmed): at fs=421.875kHz the
//   44kHz and 36kHz bands are only ~0.019 apart in normalized frequency while a
//   32-tap FIR resolves ~1/32=0.031. A 32-tap windowed FIR CANNOT reach 30dB
//   adjacent-band rejection at this 8kHz separation — physically impossible at
//   this tap count and sample rate. This bank gives ~2-3dB pre-selection plus
//   out-of-band roll-off; the matched filter supplies the real selectivity
//   (per the consolidated fix list note). The testbench therefore asserts
//   RELATIVE selectivity (passband response > adjacent-band response) rather
//   than an unachievable absolute 30dB. Conservative interpretation of an
//   internally-inconsistent fs/taps/30dB spec triad.
// ============================================================

module fir_filter_bank2 #(
    parameter integer N    = 32,   // number of taps
    parameter integer ACCW = 38    // accumulator width: 32-bit product + 5 guard + margin
) (
    input  wire               clk,        // 27MHz system clock
    input  wire               rst_n,      // synchronous active-low reset
    input  wire signed [15:0] din,        // from cic_decimator dout
    input  wire               din_valid,  // from cic_decimator dout_valid (~422kSPS strobe)
    output reg  signed [15:0] dout,       // filtered output (Q1.15-scaled to 16-bit)
    output reg                dout_valid  // 1-cycle strobe, co-registered with dout
);

    // ---------------------------------------------------------------
    // Q1.15 coefficient table (compile-time constants, symmetric).
    // ---------------------------------------------------------------
    reg signed [15:0] coeff [0:N-1];
    initial begin
        coeff[0]  = -16'sd36;  coeff[1]  = -16'sd54;   coeff[2]  = -16'sd59;
        coeff[3]  = -16'sd33;  coeff[4]  =  16'sd42;   coeff[5]  =  16'sd150;
        coeff[6]  =  16'sd233; coeff[7]  =  16'sd219;  coeff[8]  =  16'sd70;
        coeff[9]  = -16'sd177; coeff[10] = -16'sd411;  coeff[11] = -16'sd500;
        coeff[12] = -16'sd365; coeff[13] = -16'sd39;   coeff[14] =  16'sd337;
        coeff[15] =  16'sd587; coeff[16] =  16'sd587;  coeff[17] =  16'sd337;
        coeff[18] = -16'sd39;  coeff[19] = -16'sd365;  coeff[20] = -16'sd500;
        coeff[21] = -16'sd411; coeff[22] = -16'sd177;  coeff[23] =  16'sd70;
        coeff[24] =  16'sd219; coeff[25] =  16'sd233;  coeff[26] =  16'sd150;
        coeff[27] =  16'sd42;  coeff[28] = -16'sd33;   coeff[29] = -16'sd59;
        coeff[30] = -16'sd54;  coeff[31] = -16'sd36;
    end

    // ---------------------------------------------------------------
    // Tap delay line: shift[0] = newest sample.
    // ---------------------------------------------------------------
    reg signed [15:0] shift [0:N-1];

    // ---------------------------------------------------------------
    // Sequential MAC engine (identical structure to bank1; see that file's
    // header for the cycle-by-cycle timing rationale).
    //   - load operand pair for tap `idx` each cycle (idx = 0..N-1)
    //   - the 16x16 product is registered (1-cycle pipe) -> `prod`
    //   - `prod` is accumulated the cycle after its operands were issued
    //   - after all N products are accumulated, register+saturate the output
    // ---------------------------------------------------------------
    localparam ST_IDLE = 2'd0;
    localparam ST_LOAD = 2'd1;
    localparam ST_DRAIN= 2'd2;

    reg [1:0]             state;
    reg [5:0]             idx;
    reg [5:0]             acc_cnt;
    reg signed [ACCW-1:0] acc;

    reg signed [15:0]     mul_a, mul_b;
    reg signed [31:0]     prod;
    reg                   prod_pend;

    wire signed [ACCW-1:0] acc_q15 = acc >>> 15;
    localparam signed [ACCW-1:0] SAT_MAX =  38'sd32767;
    localparam signed [ACCW-1:0] SAT_MIN = -38'sd32768;
    wire signed [ACCW-1:0] prod_ext = {{(ACCW-32){prod[31]}}, prod};

    integer k;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            idx        <= 6'd0;
            acc_cnt    <= 6'd0;
            acc        <= {ACCW{1'b0}};
            mul_a      <= 16'sd0;
            mul_b      <= 16'sd0;
            prod       <= 32'sd0;
            prod_pend  <= 1'b0;
            dout       <= 16'sd0;
            dout_valid <= 1'b0;
            for (k = 0; k < N; k = k + 1)
                shift[k] <= 16'sd0;
        end else begin
            dout_valid <= 1'b0;

            prod <= mul_a * mul_b;

            if (prod_pend) begin
                acc     <= acc + prod_ext;
                acc_cnt <= acc_cnt + 6'd1;
            end
            prod_pend <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (din_valid) begin
                        shift[0] <= din;
                        for (k = 1; k < N; k = k + 1)
                            shift[k] <= shift[k-1];

                        acc       <= {ACCW{1'b0}};
                        acc_cnt   <= 6'd0;
                        mul_a     <= din;
                        mul_b     <= coeff[0];
                        prod_pend <= 1'b1;
                        idx       <= 6'd1;
                        state     <= ST_LOAD;
                    end
                end
                ST_LOAD: begin
                    if (idx < N) begin
                        mul_a     <= shift[idx];
                        mul_b     <= coeff[idx];
                        prod_pend <= 1'b1;
                        idx       <= idx + 6'd1;
                    end else begin
                        state <= ST_DRAIN;
                    end
                end
                ST_DRAIN: begin
                    if (acc_cnt == N) begin
                        if (acc_q15 > SAT_MAX)
                            dout <= 16'sh7FFF;
                        else if (acc_q15 < SAT_MIN)
                            dout <= -16'sh8000;
                        else
                            dout <= acc_q15[15:0];
                        dout_valid <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
