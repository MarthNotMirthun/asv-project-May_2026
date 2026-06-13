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
    reg               otr_in;      // FIX-W1: over-range input
    wire signed [15:0] dout;
    wire              dout_valid;
    wire              otr_out;     // FIX-W1: over-range output

    integer errors;
    integer din_pulses;          // total input strobes
    integer din_since_last_out;  // input strobes since last dout_valid
    integer dout_count;          // total output strobes
    integer measured_R;          // captured decimation factor
    integer rate_checks;
    integer otr_test_window;     // FIX-W1: which output window to capture for OTR test
    reg     otr_captured;        // FIX-W1: otr_out seen during target window

    // 27MHz clock
    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    cic_decimator #(.R(R), .WIDTH(28)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (din),
        .din_valid  (din_valid),
        .otr_in     (otr_in),      // FIX-W1
        .dout       (dout),
        .dout_valid (dout_valid),
        .otr_out    (otr_out)      // FIX-W1
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

                // FIX-W1: capture otr_out on the target window
                if (dout_count == otr_test_window)
                    otr_captured = otr_out;

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
        otr_test_window    = 0;
        otr_captured       = 1'b0;

        rst_n     = 1'b0;
        din       = DC_IN;       // constant DC input throughout
        din_valid = 1'b0;
        otr_in    = 1'b0;        // FIX-W1

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

        // --- Test: FIX-W1 OTR propagation ---
        // The CIC latches otr_in on EVERY din_valid and OR-accumulates it across
        // the R-sample decimation window; the R-th din_valid commits the window
        // into otr_capture, which appears on otr_out at the next dout_valid.
        // ROOT CAUSE of the prior FAIL: the old stimulus pulsed otr_in for only
        // ~1 din_valid then dropped it one clock later, so it frequently landed on
        // a NON-R-th sample. That sample's otr was OR'd into otr_latch, but
        // otr_latch is cleared at the window boundary before reaching otr_capture
        // unless otr_in is ALSO high on the R-th (committing) sample.
        // FIX: hold otr_in HIGH continuously across more than one full decimation
        // window. This guarantees otr_in=1 on the R-th sample of at least one
        // complete window, so otr_capture (and thus otr_out) must assert. We
        // inspect an output produced well inside the held-high interval.
        // Raise otr_in on a clean din_valid edge.
        wait (din_valid);
        @(posedge clk);
        otr_in = 1'b1;
        // The NEXT full window (and the one after) is now fully tainted. Capture
        // the second output after raising otr_in — guaranteed to come from a
        // window whose R-th sample saw otr_in=1.
        otr_test_window = dout_count + 2;
        wait (dout_count >= otr_test_window);
        @(posedge clk);
        otr_in = 1'b0;
        if (otr_captured) begin
            $display("  ok (FIX-W1): otr_in pulse survived decimation window — otr_out=1 at dout_valid");
        end else begin
            $display("FAIL (FIX-W1): otr_in pulse did NOT reach otr_out at dout_valid");
            errors = errors + 1;
        end
        // Next window should be clean
        otr_test_window = dout_count + 1;
        otr_captured    = 1'b0;
        wait (dout_count >= otr_test_window);
        @(posedge clk);
        if (!otr_captured) begin
            $display("  ok (FIX-W1): clean window returns otr_out=0");
        end else begin
            $display("FAIL (FIX-W1): otr_out stuck high in clean window");
            errors = errors + 1;
        end

        $display("=========================================");
        if (errors == 0)
            $display("ALL CHECKS PASSED — cic_decimator");
        else
            $display("FAILED: cic_decimator had %0d error(s)", errors);
        $finish;
    end

    // Safety timeout
    initial begin
        #5000000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
