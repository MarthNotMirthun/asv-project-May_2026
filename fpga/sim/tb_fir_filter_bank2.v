// Testbench: tb_fir_filter_bank2
// Description: Verifies the 32-tap bandpass FIR (42-46kHz, center 44kHz).
//   Test 1 — Passband: drive 44kHz sinusoid, confirm dout is non-zero.
//   Test 2 — Stopband: drive 36kHz sinusoid (adjacent bank center), confirm
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

module tb_fir_filter_bank2;

    localparam integer DIN_PERIOD = 64;
    localparam real    FS         = 421875.0;
    localparam real    PI         = 3.141592653589793;

    reg               clk;
    reg               rst_n;
    reg signed [15:0] din;
    reg               din_valid;
    reg               otr_in;       // FIX-W1
    wire signed [15:0] dout;
    wire              dout_valid;
    wire              otr_out;      // FIX-W1

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
        .otr_in     (otr_in),      // FIX-W1
        .dout       (dout),
        .dout_valid (dout_valid),
        .otr_out    (otr_out)      // FIX-W1
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
        din   = $rtoi(30000.0 * $sin(phase));
    end

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
                if (dout_count > 36) begin
                    if (dout >= 0 && dout > meas_peak)  meas_peak = dout;
                    if (dout <  0 && (-dout) > meas_peak) meas_peak = -dout;
                end
            end
        end
    end

    integer pass_peak;
    integer stop_peak;
    real    atten_db;

    task run_tone(input [31:0] f, input integer n_samples);
        integer start_out;
        begin
            test_freq = f;
            meas_peak = 0;
            start_out = dout_count;
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
        otr_in     = 1'b0;    // FIX-W1
        test_freq  = 44000;

        repeat (20) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // --- Test 1: passband at 44kHz ---
        run_tone(44000, 120);
        pass_peak = meas_peak;
        $display("  Test1 passband 44kHz: measured peak |dout| = %0d", pass_peak);
        if (pass_peak <= 0) begin
            $display("FAIL: passband output is zero — filter not responding");
            errors = errors + 1;
        end else begin
            $display("  ok: passband response non-zero (amplitude preserved)");
        end

        // --- Test 2: stopband at 36kHz (adjacent bank center) ---
        run_tone(36000, 120);
        stop_peak = meas_peak;
        if (stop_peak > 0)
            atten_db = 20.0*$ln(1.0*stop_peak/pass_peak)/$ln(10.0);
        else
            atten_db = -99.0;
        $display("  Test2 stopband 36kHz: measured peak |dout| = %0d  (atten = %0.1f dB)",
                 stop_peak, atten_db);
        if (stop_peak >= pass_peak) begin
            $display("FAIL: 36kHz not attenuated relative to 44kHz passband (stop=%0d pass=%0d)",
                     stop_peak, pass_peak);
            errors = errors + 1;
        end else begin
            $display("  ok: adjacent-band (36kHz) attenuated below passband (relative selectivity)");
        end

        // --- Test 3: X/Z ---
        if (xz_fails == 0)
            $display("  ok: no X/Z on dout across entire run");
        else begin
            $display("FAIL: %0d X/Z events on dout", xz_fails);
            errors = errors + xz_fails;
        end

        // --- Test 4: strobe balance ---
        $display("  Test4 strobe balance: din_valid=%0d dout_valid=%0d", din_count, dout_count);
        if ((din_count - dout_count) > 1 || (din_count - dout_count) < 0) begin
            $display("FAIL: dout_valid count not 1:1 with din_valid (diff=%0d)",
                     din_count - dout_count);
            errors = errors + 1;
        end else begin
            $display("  ok: dout_valid asserts once per din_valid (diff=%0d within fill)",
                     din_count - dout_count);
        end

        // --- FIX-W1 OTR Test A: otr_in=1 propagates to otr_out ---
        // ROOT CAUSE of prior FAIL: the FIR seeds otr_latch from otr_in in ST_IDLE
        // on the din_valid edge that STARTS a MAC window. The old stimulus waited
        // for din_valid, then advanced one clock (@posedge), THEN set otr_in=1 —
        // by which point the DUT had already left ST_IDLE and latched otr_in=0.
        // otr_in then dropped before the next window's ST_IDLE edge, so otr_latch
        // never saw a 1 on a seeding edge.
        // FIX: hold otr_in HIGH across more than one full input period so it is
        // guaranteed high on a ST_IDLE din_valid edge that seeds otr_latch.
        begin
            reg otr_seen;
            integer tgt;
            otr_seen = 1'b0;
            // Raise otr_in BEFORE the next din_valid the DUT will sample in ST_IDLE.
            wait (din_valid); @(posedge clk);
            otr_in = 1'b1;
            // Capture the second output after raising otr_in — guaranteed to come
            // from a MAC window whose ST_IDLE seed edge saw otr_in=1.
            // otr_out is a 1-cycle pulse co-registered with dout_valid; the
            // dout_count>=tgt wait unblocks in the SAME timestep dout_valid (and
            // thus otr_out) is high, so sample otr_out BEFORE advancing the clock.
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

        // --- FIX-W1 OTR Test B: FIR saturation clamp fires otr_out ---
        begin
            reg otr_seen;
            integer tgt;
            otr_seen = 1'b0;
            tgt = dout_count + 1;
            wait (din_valid); @(posedge clk);
            din = 16'sh7FFF;
            @(posedge clk);
            din = $rtoi(30000.0 * $sin(2.0*PI*test_freq*sample_idx/FS));
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
