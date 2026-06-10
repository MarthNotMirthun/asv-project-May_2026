// Module: cic_decimator
// Description: 3-stage CIC decimation filter, decimation factor R=8.
//   R=8 is correct here (NOT R=160 from an earlier CLAUDE.md note): the
//   3.375MHz adc_clk input decimated by 8 yields the 422kSPS target output.
//   Input rate : 3.375 MHz (adc_clk = 27MHz/8 from adc_interface), one sample
//                per din_valid strobe.
//   Output rate: 3.375 MHz / 8 = 421.875 kSPS (> 2 x 46 kHz signal max).
//   Stages N=3 (3 integrators @ input rate + 3 combs @ output rate).
//   Bit growth: B_max = 12 + N*log2(R) = 12 + 3*3 = 21 bits; signal MSB at bit 20.
//                28-bit datapath for margin.
//   DC gain    = R^N = 8^3 = 512.
//   Output     : c3 >>> 5 (shift = B_max-1 - 15 = 20-15 = 5) lands signal MSB at
//                bit 15, then a signed saturation clamp to [-32768,+32767].
//   Timing     : `decimate` fires 1 system clock after the R-th din_valid (it is a
//                registered 1-cycle delay). dout and dout_valid are co-registered in
//                the same `if (decimate)` block, so dout_valid is aligned to dout.
// Target: Tang Nano 20K (GW2AR-18). 27MHz system clock. Non-blocking assignments.
// Author: fpga-pipeline-orchestrator
// Date: 2026-06-09

module cic_decimator #(
    parameter integer R     = 8,    // decimation factor
    parameter integer WIDTH = 28    // internal datapath width
) (
    input  wire               clk,
    input  wire               rst_n,        // synchronous active-low reset
    input  wire signed [11:0] din,          // signed 12-bit input sample
    input  wire               din_valid,    // 1-cycle strobe per input sample
    output reg  signed [15:0] dout,         // decimated output (top 16 bits)
    output reg                dout_valid    // 1-cycle strobe per output sample
);

    // Sign-extend the 12-bit input to the internal datapath width.
    wire signed [WIDTH-1:0] din_ext = {{(WIDTH-12){din[11]}}, din};

    // ---------------------------------------------------------------
    // Integrator section (input rate, gated by din_valid).
    // Standard cascade using registered previous-stage outputs:
    //   int1[n] = int1[n-1] + din[n]
    //   int2[n] = int2[n-1] + int1[n-1]
    //   int3[n] = int3[n-1] + int2[n-1]
    // 2's-complement wrap is intended CIC behavior; combs undo it.
    // ---------------------------------------------------------------
    reg signed [WIDTH-1:0] int1, int2, int3;

    // ---------------------------------------------------------------
    // Decimation strobe: counts input samples, fires once per R inputs.
    // ---------------------------------------------------------------
    reg [$clog2(R)-1:0] dec_count;
    reg                 decimate;

    // ---------------------------------------------------------------
    // Comb section (output rate, gated by `decimate`).
    // Each comb is a differentiator with a 1-sample (output-rate) delay:
    //   c1[m] = int3[m]  - int3[m-1]
    //   c2[m] = c1[m]    - c1[m-1]
    //   c3[m] = c2[m]    - c2[m-1]
    // The combinational chain within one `decimate` strobe is valid CIC;
    // the delay registers hold each stage's previous output-rate input.
    // ---------------------------------------------------------------
    reg signed [WIDTH-1:0] comb1_d, comb2_d, comb3_d; // output-rate delay regs

    // local wires for the combinational comb chain (within a decimate)
    wire signed [WIDTH-1:0] c1 = int3 - comb1_d;
    wire signed [WIDTH-1:0] c2 = c1   - comb2_d;
    wire signed [WIDTH-1:0] c3 = c2   - comb3_d;

    // Output scaling: shift=5 = (B_max-1 - 15) = (20-15); B_max=12+N*log2(R)=21.
    // Lands the signal MSB (bit 20) at bit 15 of the 16-bit output word.
    // A saturation clamp prevents a full-scale transient from wrapping past +2^15.
    wire signed [WIDTH-1:0] c3_shifted = c3 >>> 5;

    always @(posedge clk) begin
        if (!rst_n) begin
            int1       <= {WIDTH{1'b0}};
            int2       <= {WIDTH{1'b0}};
            int3       <= {WIDTH{1'b0}};
            dec_count  <= {$clog2(R){1'b0}};
            decimate   <= 1'b0;
            comb1_d    <= {WIDTH{1'b0}};
            comb2_d    <= {WIDTH{1'b0}};
            comb3_d    <= {WIDTH{1'b0}};
            dout       <= 16'sd0;
            dout_valid <= 1'b0;
        end else begin
            decimate   <= 1'b0;   // default
            dout_valid <= 1'b0;   // default

            // ---- Integrators (input rate) ----
            if (din_valid) begin
                int1 <= int1 + din_ext;
                int2 <= int2 + int1;
                int3 <= int3 + int2;

                if (dec_count == R-1) begin
                    dec_count <= {$clog2(R){1'b0}};
                    decimate  <= 1'b1;
                end else begin
                    dec_count <= dec_count + 1'b1;
                end
            end

            // ---- Combs (output rate) ----
            if (decimate) begin
                comb1_d <= int3;   // delay <- this stage's current input
                comb2_d <= c1;
                comb3_d <= c2;

                // Output: c3 >>> 5 with signed saturation clamp to [-32768,+32767].
                dout       <= (c3_shifted >  28'sh0007FFF) ?  16'sh7FFF :
                              (c3_shifted < -28'sh0008000) ? (-16'sh7FFF - 16'sh1) :
                              c3_shifted[15:0];
                dout_valid <= 1'b1;
            end
        end
    end

endmodule
