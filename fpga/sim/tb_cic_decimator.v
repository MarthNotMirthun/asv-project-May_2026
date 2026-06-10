// Testbench: tb_cic_decimator
// Description: Verifies the 3-stage R=8 CIC decimator.
//   1. DC test  : constant din=0x100 with din_valid every 8 sys clocks.
//                 DC gain = R^N = 512; output = (256*512) >>> 5 = 4096 = 0x1000.
//   2. Rate test: count din_valid pulses between consecutive dout_valid pulses,
//                 assert == R = 8; report measured decimation factor.
//   3. X/Z check on dout after reset.
// Target sim: Icarus Verilog. 27MHz system clock (period 37.037ns).
// Author: fpga-pipeline-orchestrator
// Date: 2026-06-09

`timescale 1ns / 1ps

module tb_cic_decimator;

    localparam integer R          = 8;
    localparam integer DIN_PERIOD = 8;       // sys clocks between din_valid (mirrors adc_clk)
    localparam signed [11:0] DC_IN = 12'h100; // 256
    localparam signed [15:0] DC_EXPECTED = 16'h1000; // FIX-B2: 256*512 >>> 5 = 131072>>5 = 4096

    reg               clk;
    reg               rst_n;
    reg signed [11:0] din;
    reg               din_valid;
    wire signed [15:0] dout;
    wire              dout_valid;

    integer errors;
    integer din_pulses;          // total input strobes
    integer din_since_last_out;  // input strobes since last dout_valid
    integer dout_count;          // total output strobes
    integer measured_R;          // captured decimation factor
    integer rate_checks;

    // 27MHz clock
    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    cic_decimator #(.R(R), .WIDTH(28)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (din),
        .din_valid  (din_valid),
        .dout       (dout),
        .dout_valid (dout_valid)
    );

    // ---------------------------------------------------------------
    // din_valid generator: pulse high for 1 cycle every DIN_PERIOD clocks.
    // ---------------------------------------------------------------
    integer vcount;
    always @(posedge clk) begin
        if (!rst_n) begin
            vcount    <= 0;
            din_valid <= 1'b0;
        end else begin
            if (vcount == DIN_PERIOD-1) begin
                vcount    <= 0;
                din_valid <= 1'b1;
            end else begin
                vcount    <= vcount + 1;
                din_valid <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------
    // Monitors: count input/output strobes, measure decimation factor,
    // and check for X/Z on dout.
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (din_valid) begin
                din_pulses        = din_pulses + 1;
                din_since_last_out = din_since_last_out + 1;
            end

            if (dout_valid) begin
                dout_count = dout_count + 1;

                // X/Z check
                if (^dout === 1'bx) begin
                    $display("FAIL: dout has X/Z = %b at t=%0t", dout, $time);
                    errors = errors + 1;
                end

                // Rate check: inputs consumed since previous output should equal R.
                // (Skip the very first output, before which the counter is warming.)
                if (dout_count > 1) begin
                    if (din_since_last_out !== R) begin
                        $display("FAIL: decimation factor = %0d inputs/output, expected %0d (t=%0t)",
                                 din_since_last_out, R, $time);
                        errors = errors + 1;
                    end else begin
                        measured_R  = din_since_last_out;
                        rate_checks = rate_checks + 1;
                    end
                end
                din_since_last_out = 0;
            end
        end
    end

    initial begin
        errors             = 0;
        din_pulses         = 0;
        din_since_last_out = 0;
        dout_count         = 0;
        measured_R         = 0;
        rate_checks        = 0;

        rst_n     = 1'b0;
        din       = DC_IN;       // constant DC input throughout
        din_valid = 1'b0;

        repeat (10) @(posedge clk);
        rst_n <= 1'b1;

        // Run long enough for the integrators/combs to settle to DC gain
        // and to collect many output samples for the rate check.
        // Need >= R outputs; each output is R*DIN_PERIOD = 64 sys clocks.
        // Run ~40 output samples worth.
        repeat (40 * R * DIN_PERIOD) @(posedge clk);

        // ---- DC settling check ----
        if (dout === DC_EXPECTED) begin
            $display("  ok: FIX-B2 shift=5 verified — DC dout=0x%04h == expected 0x%04h (256*512>>>5=4096)",
                     dout, DC_EXPECTED);
        end else begin
            $display("FAIL: DC test dout=0x%04h, expected 0x%04h", dout, DC_EXPECTED);
            errors = errors + 1;
        end

        $display("  measured decimation factor R = %0d (over %0d output intervals)",
                 measured_R, rate_checks);
        if (measured_R !== R) begin
            $display("FAIL: measured decimation factor %0d != %0d", measured_R, R);
            errors = errors + 1;
        end
        if (rate_checks < 5) begin
            $display("FAIL: too few rate checks (%0d) — did the filter produce output?", rate_checks);
            errors = errors + 1;
        end

        $display("  totals: din_pulses=%0d dout_count=%0d", din_pulses, dout_count);

        $display("=========================================");
        if (errors == 0)
            $display("PASS: cic_decimator DC gain, decimation rate verified, no X/Z");
        else
            $display("FAIL: cic_decimator had %0d error(s)", errors);
        $display("SIMULATION COMPLETE");
        $finish;
    end

    // Safety timeout
    initial begin
        #5000000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
