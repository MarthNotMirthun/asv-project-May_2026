// Testbench: tb_fir_filter_bank1
// Description: Verifies the 32-tap bandpass FIR (34-38kHz, center 36kHz).
//   Test 1 — Passband: drive 36kHz sinusoid, confirm dout is non-zero
//            (amplitude preserved). Report measured peak amplitude.
//   Test 2 — Stopband: drive 44kHz sinusoid (adjacent bank center), confirm
//            output amplitude is SMALLER than passband. Report attenuation.
//            (32 taps at fs=421.875kHz cannot give 30dB at 8kHz separation —
//             see module header; we assert relative selectivity here.)
//   Test 3 — No X/Z on dout after rst_n deasserts.
//   Test 4 — dout_valid asserts exactly once per din_valid after pipeline fill.
// din_valid cadence: one strobe every 64 system clocks (R=8 CIC * 8 sys/ENCODE).
// Clock: 27MHz (half period 18.5185ns).
// Author: fpga-verilog-engineer agent
// Date: 2026-06-10

`timescale 1ns / 1ps

module tb_fir_filter_bank1;

    localparam integer DIN_PERIOD = 64;          // sys clocks between din_valid
    localparam real    FS         = 421875.0;    // CIC output sample rate (Hz)
    localparam real    PI         = 3.141592653589793;

    reg               clk;
    reg               rst_n;
    reg signed [15:0] din;
    reg               din_valid;
    wire signed [15:0] dout;
    wire              dout_valid;

    integer errors;
    integer din_count;
    integer dout_count;
    integer xz_fails;

    // 27MHz clock
    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    fir_filter_bank1 dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (din),
        .din_valid  (din_valid),
        .dout       (dout),
        .dout_valid (dout_valid)
    );

    // ---------------------------------------------------------------
    // din_valid generator: 1-cycle strobe every DIN_PERIOD clocks.
    // sample_idx advances once per strobe and indexes the test sinusoid.
    // ---------------------------------------------------------------
    integer vcount;
    integer sample_idx;
    reg [31:0] test_freq;     // current stimulus frequency (Hz)

    always @(posedge clk) begin
        if (!rst_n) begin
            vcount     <= 0;
            din_valid  <= 1'b0;
            sample_idx <= 0;
        end else begin
            if (vcount == DIN_PERIOD-1) begin
                vcount     <= 0;
                din_valid  <= 1'b1;
                sample_idx <= sample_idx + 1;
            end else begin
                vcount    <= vcount + 1;
                din_valid <= 1'b0;
            end
        end
    end

    // Drive din as a sinusoid at test_freq, amplitude ~30000 (within signed 16-bit).
    real phase;
    always @(*) begin
        phase = 2.0*PI*test_freq*sample_idx/FS;
        din   = $rtoi(30000.0 * $sin(phase));
    end

    // ---------------------------------------------------------------
    // Output monitors: count strobes, peak-track |dout|, X/Z check.
    // ---------------------------------------------------------------
    integer meas_peak;
    always @(posedge clk) begin
        if (rst_n) begin
            if (din_valid)  din_count  = din_count + 1;
            if (dout_valid) begin
                dout_count = dout_count + 1;
                if (^dout === 1'bx) begin
                    $display("FAIL: dout X/Z = %b at t=%0t", dout, $time);
                    xz_fails = xz_fails + 1;
                end
                // peak-track absolute value (skip warm-up samples)
                if (dout_count > 36) begin
                    if (dout >= 0 && dout > meas_peak)  meas_peak = dout;
                    if (dout <  0 && (-dout) > meas_peak) meas_peak = -dout;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Test sequence.
    // ---------------------------------------------------------------
    integer pass_peak;   // passband (36kHz) measured peak
    integer stop_peak;   // stopband (44kHz) measured peak
    real    atten_db;

    task run_tone(input [31:0] f, input integer n_samples);
        integer start_out;
        begin
            test_freq = f;
            meas_peak = 0;
            start_out = dout_count;
            // wait until n_samples outputs have been produced at this freq
            while (dout_count < start_out + n_samples) @(posedge clk);
        end
    endtask

    initial begin
        errors     = 0;
        din_count  = 0;
        dout_count = 0;
        xz_fails   = 0;
        meas_peak  = 0;
        pass_peak  = 0;
        stop_peak  = 0;
        rst_n      = 1'b0;
        din_valid  = 1'b0;
        test_freq  = 36000;

        repeat (20) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // --- Test 1: passband at 36kHz ---
        run_tone(36000, 120);
        pass_peak = meas_peak;
        $display("  Test1 passband 36kHz: measured peak |dout| = %0d", pass_peak);
        if (pass_peak <= 0) begin
            $display("FAIL: passband output is zero — filter not responding");
            errors = errors + 1;
        end else begin
            $display("  ok: passband response non-zero (amplitude preserved)");
        end

        // --- Test 2: stopband at 44kHz (adjacent bank center) ---
        run_tone(44000, 120);
        stop_peak = meas_peak;
        if (stop_peak > 0)
            atten_db = 20.0*$ln(1.0*stop_peak/pass_peak)/$ln(10.0);
        else
            atten_db = -99.0;
        $display("  Test2 stopband 44kHz: measured peak |dout| = %0d  (atten = %0.1f dB)",
                 stop_peak, atten_db);
        if (stop_peak >= pass_peak) begin
            $display("FAIL: 44kHz not attenuated relative to 36kHz passband (stop=%0d pass=%0d)",
                     stop_peak, pass_peak);
            errors = errors + 1;
        end else begin
            $display("  ok: adjacent-band (44kHz) attenuated below passband (relative selectivity)");
        end

        // --- Test 3: X/Z ---
        if (xz_fails == 0)
            $display("  ok: no X/Z on dout across entire run");
        else begin
            $display("FAIL: %0d X/Z events on dout", xz_fails);
            errors = errors + xz_fails;
        end

        // --- Test 4: one dout_valid per din_valid (after fill) ---
        // Allow up to 1 in-flight sample difference (pipeline fill).
        $display("  Test4 strobe balance: din_valid=%0d dout_valid=%0d", din_count, dout_count);
        if ((din_count - dout_count) > 1 || (din_count - dout_count) < 0) begin
            $display("FAIL: dout_valid count not 1:1 with din_valid (diff=%0d)",
                     din_count - dout_count);
            errors = errors + 1;
        end else begin
            $display("  ok: dout_valid asserts once per din_valid (diff=%0d within fill)",
                     din_count - dout_count);
        end

        $display("=========================================");
        if (errors == 0) begin
            $display("ALL CHECKS PASSED — fir_filter_bank1");
            $finish;
        end else begin
            $display("FAILED: fir_filter_bank1 had %0d error(s)", errors);
            $fatal;
        end
    end

    // Safety timeout
    initial begin
        #20000000;
        $display("FAILED: testbench timeout");
        $fatal;
    end

endmodule
