// ============================================================
// Module:      fir_filter_bank1
// Description: 32-tap symmetric linear-phase bandpass FIR, 34-38kHz
//              (Buoy 1 chirp band, center 36kHz). Sequential 1-MAC-per-
//              clock datapath; one output sample per input sample.
// Target:      Tang Nano 20K (GW2AR-18), 27MHz system clock
// Pipeline:    cic_decimator -> THIS -> matched_filter (bank 1)
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
//   N  = 32 taps, passband 34-38kHz, design bandwidth 4kHz, center 36kHz.
//   Q1.15: q[i] = round(float[i] * 32768), clamped to [-32768,+32767].
//   Symmetric: h[i] == h[31-i] (verified). Max |coeff| = 598 -> no Q1.15 overflow.
//
//   Q1.15 taps:
//     -21,   4,  41,  90, 135, 144,  87, -45,
//    -221,-381,-451,-380,-166, 134, 422, 598,
//     598, 422, 134,-166,-380,-451,-381,-221,
//     -45,  87, 144, 135,  90,  41,   4, -21
//
//   ACHIEVED SELECTIVITY (honest, simulation-confirmed): at fs=421.875kHz the
//   36kHz and 44kHz bands are only ~0.019 apart in normalized frequency while a
//   32-tap FIR resolves ~1/32=0.031. A 32-tap windowed FIR CANNOT reach 30dB
//   adjacent-band rejection at this 8kHz separation — physically impossible at
//   this tap count and sample rate. This bank gives ~2-3dB pre-selection plus
//   DC/out-of-band roll-off; the matched filter supplies the real selectivity
//   (per the consolidated fix list note). The testbench therefore asserts
//   RELATIVE selectivity (passband response > adjacent-band response) rather
//   than an unachievable absolute 30dB. Conservative interpretation of an
//   internally-inconsistent fs/taps/30dB spec triad.
// ============================================================

module fir_filter_bank1 #(
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
    // Q1.15 coefficient table — synthesizable case-statement ROM.
    // Gowin ignores initial blocks during synthesis; a function
    // maps tap index to coefficient value and infers LUT ROM.
    // ---------------------------------------------------------------
    function signed [15:0] coeff_rom;
        input [5:0] addr;
        case (addr)
            6'd0:  coeff_rom = -16'sd21;  6'd1:  coeff_rom =  16'sd4;
            6'd2:  coeff_rom =  16'sd41;  6'd3:  coeff_rom =  16'sd90;
            6'd4:  coeff_rom =  16'sd135; 6'd5:  coeff_rom =  16'sd144;
            6'd6:  coeff_rom =  16'sd87;  6'd7:  coeff_rom = -16'sd45;
            6'd8:  coeff_rom = -16'sd221; 6'd9:  coeff_rom = -16'sd381;
            6'd10: coeff_rom = -16'sd451; 6'd11: coeff_rom = -16'sd380;
            6'd12: coeff_rom = -16'sd166; 6'd13: coeff_rom =  16'sd134;
            6'd14: coeff_rom =  16'sd422; 6'd15: coeff_rom =  16'sd598;
            6'd16: coeff_rom =  16'sd598; 6'd17: coeff_rom =  16'sd422;
            6'd18: coeff_rom =  16'sd134; 6'd19: coeff_rom = -16'sd166;
            6'd20: coeff_rom = -16'sd380; 6'd21: coeff_rom = -16'sd451;
            6'd22: coeff_rom = -16'sd381; 6'd23: coeff_rom = -16'sd221;
            6'd24: coeff_rom = -16'sd45;  6'd25: coeff_rom =  16'sd87;
            6'd26: coeff_rom =  16'sd144; 6'd27: coeff_rom =  16'sd135;
            6'd28: coeff_rom =  16'sd90;  6'd29: coeff_rom =  16'sd41;
            6'd30: coeff_rom =  16'sd4;   6'd31: coeff_rom = -16'sd21;
            default: coeff_rom = 16'sd0;
        endcase
    endfunction

    // ---------------------------------------------------------------
    // Tap delay line: shift[0] = newest sample.
    // ---------------------------------------------------------------
    reg signed [15:0] shift [0:N-1];

    // ---------------------------------------------------------------
    // Sequential MAC engine. Per input sample:
    //   - load operand pair for tap `idx` each cycle (idx = 0..N-1)
    //   - the 16x16 product is registered (1-cycle pipe) -> `prod`
    //   - `prod` is accumulated the cycle after its operands were issued
    //   - after all N products are accumulated, register+saturate the output
    // 64 sys clocks per input sample >> ~N+3 MAC cycles, so always completes.
    // ---------------------------------------------------------------
    localparam ST_IDLE = 2'd0;
    localparam ST_LOAD = 2'd1;   // issuing operand pairs
    localparam ST_DRAIN= 2'd2;   // last product still in flight

    reg [1:0]             state;
    reg [5:0]             idx;          // operand-pair index being issued (0..N)
    reg [5:0]             acc_cnt;      // products accumulated so far (0..N)
    reg signed [ACCW-1:0] acc;

    reg signed [15:0]     mul_a, mul_b;
    reg signed [31:0]     prod;         // 16x16 -> 32-bit Q2.30
    reg                   prod_pend;    // a freshly-issued product is valid next cycle

    // Q2.30 >> 15 -> Q1.15; saturate to signed 16-bit.
    wire signed [ACCW-1:0] acc_q15 = acc >>> 15;
    localparam signed [ACCW-1:0] SAT_MAX =  38'sd32767;
    localparam signed [ACCW-1:0] SAT_MIN = -38'sd32768;

    // Sign-extend the 32-bit product to the accumulator width.
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
            dout_valid <= 1'b0;     // default

            // Single pipelined multiplier (always registers current operands).
            prod <= mul_a * mul_b;

            // Accumulate the product issued on the PREVIOUS cycle.
            if (prod_pend) begin
                acc     <= acc + prod_ext;
                acc_cnt <= acc_cnt + 6'd1;
            end
            prod_pend <= 1'b0;      // default; set when we issue an operand pair

            case (state)
                // -----------------------------------------------------
                ST_IDLE: begin
                    if (din_valid) begin
                        // Shift the new sample into the delay line (NBA).
                        shift[0] <= din;
                        for (k = 1; k < N; k = k + 1)
                            shift[k] <= shift[k-1];

                        // Issue tap-0 operands. shift[0] is being written this cycle
                        // (NBA), so use `din` directly for tap 0.
                        acc       <= {ACCW{1'b0}};
                        acc_cnt   <= 6'd0;
                        mul_a     <= din;
                        mul_b     <= coeff_rom(6'd0);
                        prod_pend <= 1'b1;
                        idx       <= 6'd1;     // next operand index to issue
                        state     <= ST_LOAD;
                    end
                end
                // -----------------------------------------------------
                ST_LOAD: begin
                    if (idx < N) begin
                        mul_a     <= shift[idx];
                        mul_b     <= coeff_rom(idx);
                        prod_pend <= 1'b1;
                        idx       <= idx + 6'd1;
                    end else begin
                        // All N operand pairs issued; one product still draining.
                        state <= ST_DRAIN;
                    end
                end
                // -----------------------------------------------------
                ST_DRAIN: begin
                    // The final product is accumulated by the prod_pend logic above
                    // on the first cycle of DRAIN. Once acc_cnt reaches N, the full
                    // sum is in `acc` — register and saturate the output.
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
