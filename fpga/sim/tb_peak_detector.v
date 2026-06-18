// ============================================================
// Testbench: tb_peak_detector
// Verifies peak_detector.v dual-channel RELATIVE gating (FC-7),
// abs-value stage, SNR proxy, OTR propagation (FC-2), peak_lag
// passthrough (FC-5), and cross-epoch staleness protection.
// Each mandatory test case prints an explicit PASS/FAIL line.
// ============================================================
`timescale 1ns/1ps

module tb_peak_detector;

    reg         clk;
    reg         rst_n;

    reg  signed [31:0] corr_peak_ch1;
    reg  [10:0] peak_lag_ch1;
    reg         otr_ch1;
    reg         corr_valid_ch1;

    reg  signed [31:0] corr_peak_ch2;
    reg  [10:0] peak_lag_ch2;
    reg         otr_ch2;
    reg         corr_valid_ch2;

    reg  [4:0]  K_SHIFT;
    reg  [31:0] FLOOR;
    reg  [4:0]  SNR_SHIFT;

    wire [7:0]  target_id;
    wire [31:0] corr_peak_out;
    wire [7:0]  snr_out;
    wire [10:0] peak_lag_out;
    wire        otr_out;
    wire        data_valid;

    integer errors = 0;

    peak_detector dut (
        .clk(clk), .rst_n(rst_n),
        .corr_peak_ch1(corr_peak_ch1), .peak_lag_ch1(peak_lag_ch1),
        .otr_ch1(otr_ch1), .corr_valid_ch1(corr_valid_ch1),
        .corr_peak_ch2(corr_peak_ch2), .peak_lag_ch2(peak_lag_ch2),
        .otr_ch2(otr_ch2), .corr_valid_ch2(corr_valid_ch2),
        .K_SHIFT(K_SHIFT), .FLOOR(FLOOR), .SNR_SHIFT(SNR_SHIFT),
        .target_id(target_id), .corr_peak_out(corr_peak_out),
        .snr_out(snr_out), .peak_lag_out(peak_lag_out),
        .otr_out(otr_out), .data_valid(data_valid)
    );

    // 27 MHz clock (~37.037 ns period)
    initial clk = 1'b0;
    always #18.518 clk = ~clk;

    // Pulse both channels valid for one clock with the given operands,
    // then wait for the data_valid strobe (decision registered 1 cycle
    // after the latch cycle).
    task drive_both;
        input signed [31:0] c1; input [10:0] l1; input o1;
        input signed [31:0] c2; input [10:0] l2; input o2;
        begin
            @(negedge clk);
            corr_peak_ch1  = c1; peak_lag_ch1 = l1; otr_ch1 = o1; corr_valid_ch1 = 1'b1;
            corr_peak_ch2  = c2; peak_lag_ch2 = l2; otr_ch2 = o2; corr_valid_ch2 = 1'b1;
            @(negedge clk);
            corr_valid_ch1 = 1'b0;
            corr_valid_ch2 = 1'b0;
            // Wait for the registered decision strobe.
            wait (data_valid == 1'b1);
            @(negedge clk);   // settle outputs
        end
    endtask

    task check_target;
        input [127:0] name;
        input [7:0]   expected;
        begin
            if (target_id === expected)
                $display("PASS: %0s -> target_id=0x%02h", name, target_id);
            else begin
                $display("FAILED: %0s -> expected target_id=0x%02h got 0x%02h",
                         name, expected, target_id);
                errors = errors + 1;
            end
        end
    endtask

    // X/Z scan on the primary outputs.
    task check_no_xz;
        begin
            if (^{target_id, corr_peak_out, snr_out, peak_lag_out, otr_out, data_valid} === 1'bx) begin
                $display("FAILED: X/Z detected on outputs");
                errors = errors + 1;
            end
        end
    endtask

    integer w;

    initial begin
        // Power-on safe defaults (per spec): K_SHIFT=2 (k=4x),
        // FLOOR=0x0000_1000, SNR_SHIFT=16.
        K_SHIFT   = 5'd2;
        FLOOR     = 32'h0000_1000;
        SNR_SHIFT = 5'd16;

        corr_peak_ch1 = 0; peak_lag_ch1 = 0; otr_ch1 = 0; corr_valid_ch1 = 0;
        corr_peak_ch2 = 0; peak_lag_ch2 = 0; otr_ch2 = 0; corr_valid_ch2 = 0;

        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // -----------------------------------------------------------
        // TEST 1: Clean Buoy 1 detection (clarified worst-case operands)
        // ch1 = 0x7000_0000, ch2 = 0x0800_0000. ch1 > 4*ch2 -> Buoy 1,
        // and no false Buoy 2 (ch2 nowhere near 4*ch1).
        // -----------------------------------------------------------
        drive_both(32'h7000_0000, 11'd123, 1'b0, 32'h0800_0000, 11'd0, 1'b0);
        check_target("T1 worst-case ch1 dominant", 8'h01);
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 2: Clean Buoy 1 detection (strong ch1, weak ch2)
        // -----------------------------------------------------------
        drive_both(32'h7000_0000, 11'd55, 1'b0, 32'h0100_0000, 11'd0, 1'b0);
        check_target("T2 clean Buoy 1", 8'h01);
        if (peak_lag_out === 11'd55)
            $display("PASS: T2 peak_lag passthrough = %0d", peak_lag_out);
        else begin
            $display("FAILED: T2 peak_lag expected 55 got %0d", peak_lag_out);
            errors = errors + 1;
        end
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 3: Clean Buoy 2 detection
        // -----------------------------------------------------------
        drive_both(32'h0100_0000, 11'd0, 1'b0, 32'h7000_0000, 11'd777, 1'b0);
        check_target("T3 clean Buoy 2", 8'h02);
        if (peak_lag_out === 11'd777)
            $display("PASS: T3 peak_lag passthrough = %0d", peak_lag_out);
        else begin
            $display("FAILED: T3 peak_lag expected 777 got %0d", peak_lag_out);
            errors = errors + 1;
        end
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 4: Neither detected (both below FLOOR=0x1000)
        // -----------------------------------------------------------
        drive_both(32'h0000_0500, 11'd0, 1'b0, 32'h0000_0200, 11'd0, 1'b0);
        check_target("T4 both below FLOOR", 8'h00);
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 5: Ambiguous (both high, ratio < 4x)
        // ch1 = 0x4000_0000, ch2 = 0x3000_0000 -> neither dominates
        // -----------------------------------------------------------
        drive_both(32'h4000_0000, 11'd0, 1'b0, 32'h3000_0000, 11'd0, 1'b0);
        check_target("T5 ambiguous (ratio<4x)", 8'h00);
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 6: OTR propagation (otr_ch1=1, otr_ch2=0)
        // Use clean Buoy 1 operands so a detection still occurs.
        // -----------------------------------------------------------
        drive_both(32'h7000_0000, 11'd10, 1'b1, 32'h0100_0000, 11'd0, 1'b0);
        if (otr_out === 1'b1)
            $display("PASS: T6 OTR propagation otr_out=1");
        else begin
            $display("FAILED: T6 OTR propagation expected otr_out=1 got %b", otr_out);
            errors = errors + 1;
        end
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 7: Negative corr_peak (signed input) -> abs used
        // ch1 = -0x7000_0000 (strong negative), ch2 weak -> Buoy 1
        // -----------------------------------------------------------
        drive_both(-32'sh7000_0000, 11'd42, 1'b0, 32'h0100_0000, 11'd0, 1'b0);
        check_target("T7 negative ch1 (abs)", 8'h01);
        if (corr_peak_out === 32'h7000_0000)
            $display("PASS: T7 abs(ch1) = 0x%08h", corr_peak_out);
        else begin
            $display("FAILED: T7 abs(ch1) expected 0x70000000 got 0x%08h", corr_peak_out);
            errors = errors + 1;
        end
        check_no_xz();

        // -----------------------------------------------------------
        // TEST 8: Stale channel protection.
        // Refresh both channels, then drive ONLY ch2 valid repeatedly
        // for > 2*2109 clocks so ch1 ages out -> stale -> target 0x00.
        // -----------------------------------------------------------
        // First give both channels a fresh result.
        drive_both(32'h7000_0000, 11'd0, 1'b0, 32'h0100_0000, 11'd0, 1'b0);
        check_target("T8a pre-stale Buoy1", 8'h01);

        // Now let time pass with NO ch1 valid. Advance > 4218 clocks.
        // We do NOT pulse ch2 valid during the aging window (so no
        // decision fires while ch1 is going stale).
        @(negedge clk);
        corr_valid_ch1 = 1'b0;
        corr_valid_ch2 = 1'b0;
        for (w = 0; w < 4300; w = w + 1) @(negedge clk);

        // Now drive ch2 valid (ch1 is stale). Expect target 0x00.
        @(negedge clk);
        corr_peak_ch2 = 32'h7000_0000; peak_lag_ch2 = 11'd99; otr_ch2 = 1'b0;
        corr_valid_ch2 = 1'b1;
        @(negedge clk);
        corr_valid_ch2 = 1'b0;
        wait (data_valid == 1'b1);
        @(negedge clk);
        check_target("T8b ch1 stale -> neither", 8'h00);
        check_no_xz();

        // -----------------------------------------------------------
        if (errors == 0)
            $display("ALL CHECKS PASSED - peak_detector");
        else
            $display("FAILED: %0d check(s) failed - peak_detector", errors);
        $finish;
    end

    // Global timeout guard.
    initial begin
        #2000000;   // 2 ms sim cap
        $display("FAILED: timeout - peak_detector did not finish");
        $finish;
    end

endmodule
