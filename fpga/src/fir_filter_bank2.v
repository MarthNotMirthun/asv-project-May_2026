// ============================================================
// Module:      fir_filter_bank2
// Description: 32-tap symmetric linear-phase bandpass FIR, 38.5-41.5kHz
//              (SHARED transducer passband, center 40kHz). Sequential
//              1-MAC-per-clock datapath; one output sample per input sample.
//              FC-7 (Jun 17): band moved from 42-46kHz to the shared
//              38.5-41.5kHz passband — IDENTICAL coefficients to
//              fir_filter_bank1. Both buoys transmit in the same 3kHz
//              transducer passband; beacon ID is CODE-DIVISION (Buoy 1 =
//              up-sweep, Buoy 2 = down-sweep) and is resolved downstream by
//              the matched filter reference chirp, NOT by FIR band. This
//              bank2 instance is retained as a separate datapath because the
//              pipeline wires bank2 -> matched_filter_2.
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
// COEFFICIENT DESIGN (windowed-sinc bandpass, Hamming window) — FC-7 RE-SPIN
//   fs = 421875 Hz EXACTLY (CIC output rate, NOT 400000 — see CLAUDE.md)
//   N  = 32 taps, passband 38.5-41.5kHz, bandwidth 3kHz, center 40kHz.
//   Signed-16 INTEGER scale (FC-1, NOT Q1.15): float taps normalized so
//   max|coeff| -> 32767, rounded to nearest int16. IDENTICAL coefficient set
//   to fir_filter_bank1 (both banks share the 38.5-41.5kHz passband per FC-7).
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
//   band-limiting pre-filter. Beacon discrimination is supplied entirely by
//   the matched filter: bank2 -> matched_filter_2 correlates against the
//   DOWN-sweep (41.5->38.5kHz) reference chirp (Buoy 2). The testbench asserts
//   passband retention at 40kHz and relative attenuation at 36kHz / 44kHz.
// ============================================================

module fir_filter_bank2 #(
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
    // FC-7 38.5-41.5kHz signed-16 INTEGER coefficient table (compile-time
    // constants, symmetric). Synthesizable case-statement ROM — Gowin
    // ignores initial blocks. IDENTICAL table to fir_filter_bank1 per FC-7.
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

    // FIX-W1: over-range latch (see bank1 for rationale).
    reg                   otr_latch;

    wire signed [ACCW-1:0] acc_q15 = acc >>> 15;
    localparam signed [ACCW-1:0] SAT_MAX =  38'sd32767;
    localparam signed [ACCW-1:0] SAT_MIN = -38'sd32768;
    // FIX-W1: a fired saturation clamp is itself an over-range event.
    wire clamp_fired = (acc_q15 > SAT_MAX) || (acc_q15 < SAT_MIN);
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
            dout_valid <= 1'b0;
            otr_out    <= 1'b0;     // FIX-W1: default; pulses only with dout_valid

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
                        mul_b     <= coeff_rom(6'd0);
                        prod_pend <= 1'b1;
                        idx       <= 6'd1;
                        state     <= ST_LOAD;
                        otr_latch <= otr_in;   // FIX-W1: seed window from this sample
                    end
                end
                ST_LOAD: begin
                    otr_latch <= otr_latch | otr_in;  // FIX-W1: OR across window
                    if (idx < N) begin
                        mul_a     <= shift[idx];
                        mul_b     <= coeff_rom(idx);
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
