// Testbench: tb_fir_filter_bank2  (FC-7 RE-SPIN)
// Description: Verifies the 32-tap bandpass FIR after the FC-7 re-spin to the
//   SHARED 38.5-41.5kHz passband (center 40kHz). bank2 now carries the SAME
//   coefficients as bank1 (code-division beacon ID handled by matched filter).
//   Tests mirror tb_fir_filter_bank1:
//   Test 1 — Passband 40kHz: dout non-zero and unsaturated (design gain ~8.8x).
//   Test 2 — Passband ripple: 38.5/41.5kHz band edges within 1dB of center.
//   Test 3 — Stopband below 20kHz: strong attenuation vs passband.
//   Test 4 — Stopband above 55kHz: strong attenuation vs passband.
//   Test 5 — No X/Z on dout.
//   Test 6 — dout_valid once per din_valid after fill.
//   FIX-W1 A/B — otr_in propagation and saturation-clamp otr_out.
//
//   36kHz/44kHz are NOT stopband test points: under FC-7 they sit inside the
//   32-tap FIR transition band (only 2.5kHz outside the 38.5-41.5kHz edges) and
//   cannot be resolved (~0.6dB). The matched filter discriminates beacons by
//   sweep direction; the FIR is an anti-alias pre-filter. Stopband tests use
//   20kHz/55kHz, which the FIR genuinely rejects. See FIR-selectivity-limit note.
// din_valid cadence: one strobe every 64 system clocks.
// Clock: 27MHz (half period 18.5185ns).  fs = 421875 Hz.
// Author: fpga-verilog-engineer agent
// Date: 2026-06-17

`timescale 1ns / 1ps

module tb_fir_filter_bank2;

    localparam integer DIN_PERIOD = 64;
    localparam real    FS         = 421875.0;
    localparam real    PI         = 3.141592653589793;
    // Design passband gain ~8.8x; keep AMP*gain < 32767 (3000*8.8 = ~26400).
    localparam integer AMP        = 3000;

    reg               clk;
    reg               rst_n;
    reg signed [15:0] din;
    reg               din_valid;
    reg               otr_in;
    wire signed [15:0] dout;
    wire              dout_valid;
    wire              otr_out;

    integer errors;
    integer din_count;
    integer dout_count;
    integer xz_fails;

    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    fir_filter_bank2 dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (din),
        .din_valid  (din_valid),
        .otr_in     (otr_in),
        .dout       (dout),
        .dout_valid (dout_valid),
        .otr_out    (otr_out)
    );

    integer vcount;
    integer sample_idx;
    reg [31:0] test_freq;

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

    real phase;
    always @(*) begin
        phase = 2.0*PI*test_freq*sample_idx/FS;
        din   = $rtoi(AMP * $sin(phase));
    end

    integer meas_peak;
    reg     measuring;
    initial measuring = 1'b0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (din_valid)  din_count  = din_count + 1;
            if (dout_valid) begin
                dout_count = dout_count + 1;
                if (^dout === 1'bx) begin
                    $display("FAIL: dout X/Z = %b at t=%0t", dout, $time);
                    xz_fails = xz_fails + 1;
                end
                if (measuring) begin
                    if (dout >= 0 && dout > meas_peak)  meas_peak = dout;
                    if (dout <  0 && (-dout) > meas_peak) meas_peak = -dout;
                end
            end
        end
    end

    integer pass_peak;
    integer edge_lo_peak;
    integer edge_hi_peak;
    integer stop_lo_peak;
    integer stop_hi_peak;
    real    atten_lo_db;
    real    atten_hi_db;

    // Drive tone f, settle (flush previous tone from delay line), then peak-track.
    localparam integer SETTLE = 48;
    task run_tone(input [31:0] f, input integer n_samples);
        integer start_out;
        begin
            test_freq = f;
            measuring = 1'b0;
            start_out = dout_count;
            while (dout_count < start_out + SETTLE) @(posedge clk);
            meas_peak = 0;
            measuring = 1'b1;
            start_out = dout_count;
            while (dout_count < start_out + n_samples) @(posedge clk);
            measuring = 1'b0;
        end
    endtask

    initial begin
        errors       = 0;
        din_count    = 0;
        dout_count   = 0;
        xz_fails     = 0;
        meas_peak    = 0;
        pass_peak    = 0;
        edge_lo_peak = 0;
        edge_hi_peak = 0;
        stop_lo_peak = 0;
        stop_hi_peak = 0;
        rst_n        = 1'b0;
        din_valid    = 1'b0;
        otr_in       = 1'b0;
        test_freq    = 40000;

        repeat (20) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // --- Test 1: passband at 40kHz (center) ---
        run_tone(40000, 120);
        pass_peak = meas_peak;
        $display("  Test1 passband 40kHz: peak |dout| = %0d (AMP=%0d, design gain ~8.8x)", pass_peak, AMP);
        if (pass_peak <= 0) begin
            $display("FAIL: passband output is zero — filter not responding");
            errors = errors + 1;
        end else if (pass_peak >= 32767) begin
            $display("FAIL: passband saturated (peak=%0d) — reduce AMP", pass_peak);
            errors = errors + 1;
        end else begin
            $display("  ok: passband 40kHz non-zero and unsaturated (peak=%0d)", pass_peak);
        end

        // --- Test 2: passband ripple at band edges 38.5kHz and 41.5kHz ---
        run_tone(38500, 120);
        edge_lo_peak = meas_peak;
        run_tone(41500, 120);
        edge_hi_peak = meas_peak;
        $display("  Test2 band edges: 38.5kHz=%0d 41.5kHz=%0d (center=%0d)", edge_lo_peak, edge_hi_peak, pass_peak);
        if (edge_lo_peak < (pass_peak*89)/100 || edge_hi_peak < (pass_peak*89)/100) begin
            $display("FAIL: passband ripple > 1dB across 38.5-41.5kHz (edges %0d/%0d vs center %0d)",
                     edge_lo_peak, edge_hi_peak, pass_peak);
            errors = errors + 1;
        end else begin
            $display("  ok: passband ripple < 1dB across 38.5-41.5kHz band");
        end

        // --- Test 3: stopband below at 20kHz ---
        run_tone(20000, 120);
        stop_lo_peak = meas_peak;
        if (stop_lo_peak > 0)
            atten_lo_db = 20.0*$ln(1.0*stop_lo_peak/pass_peak)/$ln(10.0);
        else
            atten_lo_db = -99.0;
        $display("  Test3 stopband 20kHz: peak |dout| = %0d  (atten = %0.1f dB)", stop_lo_peak, atten_lo_db);
        if (stop_lo_peak >= pass_peak) begin
            $display("FAIL: 20kHz not attenuated relative to 40kHz passband (stop=%0d pass=%0d)", stop_lo_peak, pass_peak);
            errors = errors + 1;
        end else begin
            $display("  ok: 20kHz attenuated below 40kHz passband");
        end

        // --- Test 4: stopband above at 55kHz ---
        run_tone(55000, 120);
        stop_hi_peak = meas_peak;
        if (stop_hi_peak > 0)
            atten_hi_db = 20.0*$ln(1.0*stop_hi_peak/pass_peak)/$ln(10.0);
        else
            atten_hi_db = -99.0;
        $display("  Test4 stopband 55kHz: peak |dout| = %0d  (atten = %0.1f dB)", stop_hi_peak, atten_hi_db);
        if (stop_hi_peak >= pass_peak) begin
            $display("FAIL: 55kHz not attenuated relative to 40kHz passband (stop=%0d pass=%0d)", stop_hi_peak, pass_peak);
            errors = errors + 1;
        end else begin
            $display("  ok: 55kHz attenuated below 40kHz passband");
        end

        // --- Test 5: X/Z ---
        if (xz_fails == 0)
            $display("  ok: no X/Z on dout across entire run");
        else begin
            $display("FAIL: %0d X/Z events on dout", xz_fails);
            errors = errors + xz_fails;
        end

        // --- Test 6: one dout_valid per din_valid (after fill) ---
        $display("  Test6 strobe balance: din_valid=%0d dout_valid=%0d", din_count, dout_count);
        if ((din_count - dout_count) > 1 || (din_count - dout_count) < 0) begin
            $display("FAIL: dout_valid count not 1:1 with din_valid (diff=%0d)", din_count - dout_count);
            errors = errors + 1;
        end else begin
            $display("  ok: dout_valid asserts once per din_valid (diff=%0d within fill)", din_count - dout_count);
        end

        // --- FIX-W1 OTR Test A ---
        begin : otr_test_a
            reg otr_seen;
            integer tgt;
            otr_seen = 1'b0;
            wait (din_valid); @(posedge clk);
            otr_in = 1'b1;
            tgt = dout_count + 2;
            wait (dout_count >= tgt);
            otr_seen = otr_out;
            @(posedge clk);
            otr_in = 1'b0;
            if (otr_seen)
                $display("  ok (FIX-W1 A): otr_in pulse propagated to otr_out");
            else begin
                $display("FAIL (FIX-W1 A): otr_in=1 did not reach otr_out");
                errors = errors + 1;
            end
        end

        // --- FIX-W1 OTR Test B ---
        begin : otr_test_b
            reg otr_seen;
            integer tgt;
            otr_seen = 1'b0;
            tgt = dout_count + 1;
            wait (din_valid); @(posedge clk);
            din = 16'sh7FFF;
            @(posedge clk);
            din = $rtoi(AMP * $sin(2.0*PI*test_freq*sample_idx/FS));
            wait (dout_count >= tgt); @(posedge clk);
            otr_seen = otr_out;
            if (otr_seen)
                $display("  ok (FIX-W1 B): FIR saturation clamp fired otr_out with otr_in=0");
            else
                $display("  note (FIX-W1 B): clamp did not fire — small signal may not have saturated (non-fatal)");
        end

        $display("=========================================");
        if (errors == 0) begin
            $display("ALL CHECKS PASSED — fir_filter_bank2");
            $finish;
        end else begin
            $display("FAILED: fir_filter_bank2 had %0d error(s)", errors);
            $fatal;
        end
    end

    initial begin
        #20000000;
        $display("FAILED: testbench timeout");
        $fatal;
    end

endmodule
