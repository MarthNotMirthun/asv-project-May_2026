// ============================================================
// Module:      fir_filter_bank1
// Description: 32-tap symmetric linear-phase bandpass FIR, 38.5-41.5kHz
//              (SHARED transducer passband, center 40kHz). Sequential
//              1-MAC-per-clock datapath; one output sample per input sample.
//              FC-7 (Jun 17): band moved from 34-38kHz to the shared
//              38.5-41.5kHz passband. Beacon ID is now CODE-DIVISION
//              (up-sweep vs down-sweep LFM) and resolved by the matched
//              filter reference chirp, NOT by FIR band. Bank1 and bank2 now
//              carry IDENTICAL coefficients; both instances are retained
//              because the pipeline wires bank1 -> matched_filter_1 and
//              bank2 -> matched_filter_2 as separate datapaths.
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
// COEFFICIENT DESIGN (windowed-sinc bandpass, Hamming window) — FC-7 RE-SPIN
//   fs = 421875 Hz EXACTLY (CIC output rate, NOT 400000 — see CLAUDE.md)
//   N  = 32 taps, passband 38.5-41.5kHz, bandwidth 3kHz, center 40kHz.
//   Signed-16 INTEGER scale (FC-1, NOT Q1.15): float taps normalized so
//   max|coeff| -> 32767, rounded to nearest int16. Applied as a fractional
//   gain internally; the >>>15 in the datapath rescales the accumulator.
//   Symmetric: h[i] == h[31-i] (verified by design script). Max |coeff| = 32767.
//
//   int16 taps (max-normalized):
//     -2645, -2132,  -744,  2182,  6391, 10096, 10525,  5529,
//     -4660,-16708,-25218,-25241,-15011,  2632, 21071, 32767,
//     32767, 21071,  2632,-15011,-25241,-25218,-16708, -4660,
//      5529, 10525, 10096,  6391,  2182,  -744, -2132, -2645
//
//   SELECTIVITY ROLE (per FIR-selectivity-limit memory): a 32-tap FIR at this
//   fs cannot achieve sharp adjacent-band rejection. Under FC-7 both beacons
//   occupy the SAME 38.5-41.5kHz band, so this FIR is purely an anti-alias /
//   band-limiting pre-filter — it isolates the 3kHz transducer band and rolls
//   off DC and out-of-band energy. Beacon discrimination is supplied entirely
//   by the matched filter, which correlates against the up-sweep (bank1 ->
//   matched_filter_1) vs down-sweep (bank2 -> matched_filter_2) reference
//   chirp. The testbench asserts passband retention at 40kHz and relative
//   attenuation at 36kHz / 44kHz stopband edges.
// ============================================================

module fir_filter_bank1 #(
    parameter integer N    = 32,   // number of taps
    parameter integer ACCW = 38    // accumulator width: 32-bit product + 5 guard + margin
) (
    input  wire               clk,        // 27MHz system clock
    input  wire               rst_n,      // synchronous active-low reset
    input  wire signed [15:0] din,        // from cic_decimator dout
    input  wire               din_valid,  // from cic_decimator dout_valid (~422kSPS strobe)
    input  wire               otr_in,     // FIX-W1: over-range flag from cic_decimator otr_out
    output reg  signed [15:0] dout,       // FIX-N2: signed-16 INTEGER sample scale. The Q1.15 coeffs are applied as a fractional gain INTERNALLY and the >>>15 already removed the Q1.15 scaling — dout is therefore a plain integer sample, NOT Q1.15. Downstream matched_filter reference chirp MUST use this same integer scale, NOT Q1.15.
    output reg                dout_valid, // 1-cycle strobe, co-registered with dout
    output reg                otr_out     // FIX-W1: over-range seen in MAC window OR clamp fired
);

    // ---------------------------------------------------------------
    // FC-7 38.5-41.5kHz signed-16 INTEGER coefficient table —
    // synthesizable case-statement ROM. Gowin ignores initial blocks
    // during synthesis; a function maps tap index to coefficient value
    // and infers LUT ROM. (Identical table to fir_filter_bank2 per FC-7.)
    // ---------------------------------------------------------------
    function signed [15:0] coeff_rom;
        input [5:0] addr;
        case (addr)
            6'd0:  coeff_rom = -16'sd2645;  6'd1:  coeff_rom = -16'sd2132;
            6'd2:  coeff_rom = -16'sd744;   6'd3:  coeff_rom =  16'sd2182;
            6'd4:  coeff_rom =  16'sd6391;  6'd5:  coeff_rom =  16'sd10096;
            6'd6:  coeff_rom =  16'sd10525; 6'd7:  coeff_rom =  16'sd5529;
            6'd8:  coeff_rom = -16'sd4660;  6'd9:  coeff_rom = -16'sd16708;
            6'd10: coeff_rom = -16'sd25218; 6'd11: coeff_rom = -16'sd25241;
            6'd12: coeff_rom = -16'sd15011; 6'd13: coeff_rom =  16'sd2632;
            6'd14: coeff_rom =  16'sd21071; 6'd15: coeff_rom =  16'sd32767;
            6'd16: coeff_rom =  16'sd32767; 6'd17: coeff_rom =  16'sd21071;
            6'd18: coeff_rom =  16'sd2632;  6'd19: coeff_rom = -16'sd15011;
            6'd20: coeff_rom = -16'sd25241; 6'd21: coeff_rom = -16'sd25218;
            6'd22: coeff_rom = -16'sd16708; 6'd23: coeff_rom = -16'sd4660;
            6'd24: coeff_rom =  16'sd5529;  6'd25: coeff_rom =  16'sd10525;
            6'd26: coeff_rom =  16'sd10096; 6'd27: coeff_rom =  16'sd6391;
            6'd28: coeff_rom =  16'sd2182;  6'd29: coeff_rom = -16'sd744;
            6'd30: coeff_rom = -16'sd2132;  6'd31: coeff_rom = -16'sd2645;
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

    // FIX-W1: over-range latch — OR'd across the MAC window, then OR'd with a
    // fired saturation clamp at output time. Seeded in ST_IDLE, cleared after
    // the output is registered in ST_DRAIN.
    reg                   otr_latch;

    // Q2.30 >> 15 -> Q1.15; saturate to signed 16-bit.
    wire signed [ACCW-1:0] acc_q15 = acc >>> 15;
    localparam signed [ACCW-1:0] SAT_MAX =  38'sd32767;
    localparam signed [ACCW-1:0] SAT_MIN = -38'sd32768;

    // FIX-W1: a fired saturation clamp is itself an over-range event.
    wire clamp_fired = (acc_q15 > SAT_MAX) || (acc_q15 < SAT_MIN);

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
            otr_latch  <= 1'b0;     // FIX-W1
            otr_out    <= 1'b0;     // FIX-W1
            for (k = 0; k < N; k = k + 1)
                shift[k] <= 16'sd0;
        end else begin
            dout_valid <= 1'b0;     // default
            otr_out    <= 1'b0;     // FIX-W1: default; pulses only with dout_valid

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
                        otr_latch <= otr_in;   // FIX-W1: seed window from this sample
                    end
                end
                // -----------------------------------------------------
                ST_LOAD: begin
                    otr_latch <= otr_latch | otr_in;  // FIX-W1: OR across window
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
                        // FIX-W1: over-range = window otr OR a fired saturation clamp.
                        otr_out    <= otr_latch | clamp_fired;
                        otr_latch  <= 1'b0;     // clear for next window
                        state      <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
