// Testbench: tb_adc_interface
// Description: Tests adc_interface.v with the FPGA-generated ENCODE clock model.
//   - adc_clk (ENCODE) toggles every CLK_DIV_HALF=4 system clocks -> period 8 sys clks
//   - The DUT fills a 7-ENCODE-cycle pipeline before it begins streaming samples
//     (AD9226 datasheet Rev B pipeline latency = 7 ENCODE cycles)
//   - Once streaming, on each ENCODE rising edge sample_valid pulses 1 sys clock and
//     sample_out latches the data present on the bus AT that emit edge.
//     OTR is a pass-through flag: sample_out == adc_data even when OTR is HIGH
//     (the AD9226 itself drives 0xFFF/0x000 on the rails during overflow).
// Verification model:
//   The DUT samples the live bus value at the emit ENCODE edge. The TB therefore
//   captures (drive_val, drive_otr) at every ENCODE rising edge and, on the very
//   next system clock (where sample_valid is asserted), compares sample_out to that
//   captured value. This tracks the exact alignment of the DUT.
// Target sim: Icarus Verilog
// Clock: 27MHz (period 37.037ns)
// Author: fpga-pipeline-orchestrator
// Date: 2026-06-09

`timescale 1ns / 1ps

module tb_adc_interface;

    localparam integer CLK_DIV_HALF = 4;

    reg         clk;
    reg         rst_n;
    reg  [11:0] adc_data;
    reg         otr;
    wire        adc_clk;
    wire [11:0] sample_out;
    wire        sample_otr;
    wire        sample_valid;

    integer errors;
    integer enc_edges;          // count of ENCODE rising edges seen
    integer valid_count;        // count of sample_valid pulses
    integer otr_clamped_seen;   // count of OTR-flagged samples verified
    reg     midscale_seen;      // FIX-B1 directed: 0x800 -> 0x000 verified
    reg     posfs_seen;         // FIX-B1 directed: 0xFFF -> 0x7FF verified
    reg     negfs_seen;         // FIX-B1 directed: 0x000 -> 0x800 verified

    // 27MHz clock: period 37.037ns -> half period 18.5185ns
    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    adc_interface #(.CLK_DIV_HALF(CLK_DIV_HALF)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .adc_data     (adc_data),
        .otr          (otr),
        .adc_clk      (adc_clk),
        .sample_out   (sample_out),
        .sample_otr   (sample_otr),
        .sample_valid (sample_valid)
    );

    // ENCODE rising-edge detection inside the TB (mirror of DUT logic).
    reg adc_clk_d;
    wire enc_rising = adc_clk & ~adc_clk_d;
    always @(posedge clk) adc_clk_d <= adc_clk;

    // ---------------------------------------------------------------
    // Stimulus: adc_data is a counter incrementing each ENCODE edge.
    // OTR is asserted for exactly 3 ENCODE edges while adc_data is near 0x800.
    // Both are updated on the ENCODE rising edge, so they are stable across
    // that edge and into the following system clock where the DUT samples.
    // ---------------------------------------------------------------
    reg [11:0] drive_val;
    reg        drive_otr;

    // Snapshot of what was on the bus at the most recent ENCODE edge,
    // i.e. the value the DUT will emit on the next sample_valid pulse.
    reg [11:0] emit_data;
    reg        emit_otr;
    reg        emit_known;     // a snapshot is available to compare against

    always @(posedge clk) begin
        if (!rst_n) begin
            enc_edges  <= 0;
            drive_val  <= 12'h7F0;
            drive_otr  <= 1'b0;
            emit_data  <= 12'h000;
            emit_otr   <= 1'b0;
            emit_known <= 1'b0;
        end else if (enc_rising) begin
            // snapshot the bus value present at THIS edge (DUT samples this live)
            emit_data  <= drive_val;
            emit_otr   <= drive_otr;
            emit_known <= 1'b1;
            enc_edges  <= enc_edges + 1;

            // advance the driven value for the next ENCODE edge
            drive_val <= drive_val + 12'd1;
            // OTR high for exactly 3 ENCODE edges (covers 0x800,0x801,0x802).
            // This window starts ~16 ENCODE edges after reset, well past the
            // 7-edge DUT pipeline fill, so all 3 OTR-flagged samples are streamed.
            if ((drive_val >= 12'h800) && (drive_val <= 12'h802))
                drive_otr <= 1'b1;
            else
                drive_otr <= 1'b0;
        end
    end

    // Present the driven value combinationally on the bus.
    always @(*) begin
        adc_data = drive_val;
        otr      = drive_otr;
    end

    // ---------------------------------------------------------------
    // Check sample_valid pulses against the last ENCODE-edge snapshot.
    // ---------------------------------------------------------------
    reg [11:0] expected_sample;
    always @(posedge clk) begin
        if (rst_n && sample_valid) begin
            valid_count = valid_count + 1;

            if (^sample_out === 1'bx) begin
                $display("FAIL: sample_out has X/Z = %b at t=%0t", sample_out, $time);
                errors = errors + 1;
            end

            if (emit_known) begin
                // AD9226 offset binary -> two's complement: MSB inverted.
                expected_sample = {~emit_data[11], emit_data[10:0]};
                if (sample_out !== expected_sample) begin
                    $display("FAIL: sample_out=0x%03h expected 0x%03h (otr=%b raw=0x%03h) t=%0t",
                             sample_out, expected_sample, emit_otr, emit_data, $time);
                    errors = errors + 1;
                end

                // FIX-W1: registered OTR must align to the same conversion as sample_out.
                if (sample_otr !== emit_otr) begin
                    $display("FAIL: sample_otr=%b expected %b (raw=0x%03h) t=%0t",
                             sample_otr, emit_otr, emit_data, $time);
                    errors = errors + 1;
                end else begin
                    $display("  ok: sample_otr correctly aligned to sample_valid (otr=%b)", sample_otr);
                end

                if (emit_otr) begin
                    otr_clamped_seen = otr_clamped_seen + 1;
                    $display("  ok: OTR flag set -> sample_out=0x%03h (raw 0x%03h)",
                             sample_out, emit_data);
                end else begin
                    $display("  ok: MSB-flip sample_out=0x%03h (raw 0x%03h)", sample_out, emit_data);
                end

                // FIX-B1 directed checks: the streaming counter sweeps through 0x800.
                // 0x800 (0V midscale) -> 0x000 signed.
                if (emit_data == 12'h800) begin
                    if (sample_out == 12'h000) begin
                        midscale_seen = 1'b1;
                        $display("  ok: MSB-flip verified — 0x800 raw -> 0x000 signed");
                    end else begin
                        $display("FAIL: 0x800 raw -> 0x%03h, expected 0x000", sample_out);
                        errors = errors + 1;
                    end
                end
                // 0xFFF (+FS) -> 0x7FF signed.
                if (emit_data == 12'hFFF) begin
                    if (sample_out == 12'h7FF) begin
                        posfs_seen = 1'b1;
                        $display("  ok: MSB-flip verified — 0xFFF raw -> 0x7FF signed (+FS)");
                    end else begin
                        $display("FAIL: 0xFFF raw -> 0x%03h, expected 0x7FF", sample_out);
                        errors = errors + 1;
                    end
                end
                // 0x000 (-FS) -> 0x800 signed (-2048).
                if (emit_data == 12'h000) begin
                    if (sample_out == 12'h800) begin
                        negfs_seen = 1'b1;
                        $display("  ok: MSB-flip verified — 0x000 raw -> 0x800 signed (-FS)");
                    end else begin
                        $display("FAIL: 0x000 raw -> 0x%03h, expected 0x800", sample_out);
                        errors = errors + 1;
                    end
                end
            end
        end
    end

    // adc_clk must never be X/Z after reset.
    always @(posedge clk) begin
        if (rst_n) begin
            if (adc_clk === 1'bx || adc_clk === 1'bz) begin
                $display("FAIL: adc_clk is X/Z at t=%0t", $time);
                errors = errors + 1;
            end
        end
    end

    initial begin
        errors           = 0;
        valid_count      = 0;
        otr_clamped_seen = 0;
        midscale_seen    = 1'b0;
        posfs_seen       = 1'b0;
        negfs_seen       = 1'b0;
        rst_n            = 1'b0;
        adc_clk_d        = 1'b0;

        repeat (10) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // The drive counter starts at 0x7F0 and increments each ENCODE edge.
        // Stream until it has swept midscale (0x800), +FS (0xFFF) and -FS (0x000)
        // exactly once each — a single 12-bit wrap, so 0x800 is hit only once
        // (3 OTR-flagged samples) before re-reaching it at edge 4096.
        while (!(midscale_seen && posfs_seen && negfs_seen)) @(posedge clk);
        repeat (10) @(posedge clk);

        $display("=========================================");
        $display("  ENCODE edges seen:      %0d", enc_edges);
        $display("  sample_valid pulses:    %0d", valid_count);
        $display("  OTR samples verified:   %0d (expected 3)", otr_clamped_seen);
        if (otr_clamped_seen !== 3) begin
            $display("FAIL: expected exactly 3 OTR-flagged samples, saw %0d", otr_clamped_seen);
            errors = errors + 1;
        end
        if (!midscale_seen) begin
            $display("FAIL: never observed 0x800 midscale directed case");
            errors = errors + 1;
        end
        if (!posfs_seen) begin
            $display("FAIL: never observed 0xFFF +FS directed case");
            errors = errors + 1;
        end
        if (!negfs_seen) begin
            $display("FAIL: never observed 0x000 -FS directed case");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: adc_interface ENCODE timing, MSB-flip + OTR alignment verified, no X/Z");
        else
            $display("FAIL: adc_interface had %0d error(s)", errors);
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
