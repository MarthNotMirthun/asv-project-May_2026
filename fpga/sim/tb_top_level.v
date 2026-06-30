// ============================================================
// Testbench:   tb_top_level
// Verifies:    Full pipeline integration (top_level.v) end to end —
//              AD9226 capture -> CIC -> FIR x2 -> matched filter x2 ->
//              peak detector -> packet framer -> uart_tx.
//
// CHECKS (per consolidated fix list build instructions):
//   1. Drives adc_data with a synthetic ~40kHz chirp-shaped input
//      (12-bit offset-binary, sine-approx counter).
//   2. Preloads matched_filter_1 / matched_filter_2 ref_mem arrays
//      directly via hierarchical assignment so correlation > 0
//      (top_level ties ref_wr_en LOW per FIX-B2, so we load the
//       reference the only other way available in sim).
//   3. Waits for uart_tx_out to emit a complete 8-byte UART packet,
//      detecting the start bit (falling edge) and sampling 10 bits per
//      byte at CLKS_PER_BIT=234 intervals.
//   4. Decodes all 8 bytes: verifies byte 7 = 0xFF, checksum = XOR of
//      bytes 0-5, and no X/Z on uart_tx_out during transmission.
//   5. ALL CHECKS PASSED / $finish on success, $fatal on failure.
//
// FIX coverage:
//   FIX-B1 : peak_detector config constants drive a real decision (the
//            packet's target_id / snr come from the gated decision).
//   FIX-B2 : ref_wr_en is held LOW by top_level — verified by the design
//            compiling and the reference being loaded via the sim-only
//            hierarchical path (not through the tied-off port).
//   FIX-B3 : packet bytes 3-4 are the saturating (corr_peak>>6) field; the
//            checksum check covers bytes 0-5 including this field.
//   FIX-W1 : adc_clk port toggles (checked).
//   FIX-W2 : a packet only emerges if the entire valid/OTR/data cascade is
//            wired correctly — packet emission is the end-to-end proof.
// ============================================================
`timescale 1ns / 1ps

module tb_top_level;

    // 27 MHz -> 37.037 ns period.
    localparam real    CLK_PERIOD = 37.037;
    localparam integer CLKS_PER_BIT = 234;
    localparam integer N_TAPS = 2109;

    reg         clk;
    reg         rst_n;
    reg  [11:0] adc_data;
    reg         adc_otr;
    wire        uart_tx_out;
    wire        adc_clk;

    // ---- DUT ----
    top_level dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .adc_data    (adc_data),
        .adc_otr     (adc_otr),
        .uart_tx_out (uart_tx_out),
        .adc_clk     (adc_clk)
    );

    // ---- 27 MHz clock ----
    initial clk = 1'b0;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // ---- adc_clk toggle monitor (FIX-W1) ----
    integer adc_clk_edges;
    reg     adc_clk_q;
    always @(posedge clk) begin
        adc_clk_q <= adc_clk;
        if (adc_clk !== adc_clk_q)
            adc_clk_edges <= adc_clk_edges + 1;
    end

    // ---- X/Z monitor on the serial line during active transmit ----
    integer xz_seen;

    // ============================================================
    // Synthetic 40 kHz chirp-shaped stimulus into adc_data.
    // 16-entry sine LUT (offset-binary, midscale 0x800). Advancing the
    // phase by ~PHASE_STEP each ADC sample period produces a ~40 kHz tone
    // at the 3.375 MHz ENCODE rate. We don't need a perfectly matched
    // chirp — we preload the reference with the SAME waveform so the
    // zero-lag correlation is guaranteed large and positive.
    // ============================================================
    // 12-bit offset-binary sine, peak swing ~+/-1500 around 0x800.
    function [11:0] sine12;
        input [3:0] ph;
        begin
            case (ph)
                4'd0:  sine12 = 12'h800; 4'd1:  sine12 = 12'hA3D;
                4'd2:  sine12 = 12'hC00; 4'd3:  sine12 = 12'hDA8;
                4'd4:  sine12 = 12'hEFF; 4'd5:  sine12 = 12'hFA8;
                4'd6:  sine12 = 12'hFFF; 4'd7:  sine12 = 12'hFA8;
                4'd8:  sine12 = 12'hEFF; 4'd9:  sine12 = 12'hDA8;
                4'd10: sine12 = 12'hC00; 4'd11: sine12 = 12'hA3D;
                4'd12: sine12 = 12'h800; 4'd13: sine12 = 12'h5C2;
                4'd14: sine12 = 12'h3FF; 4'd15: sine12 = 12'h257;
            endcase
        end
    endfunction

    // Advance phase synchronously with each ADC ENCODE rising edge so the
    // tone is locked to the actual sample rate the pipeline sees.
    reg [3:0] phase;
    reg       adc_clk_d;
    always @(posedge clk) begin
        if (!rst_n) begin
            phase     <= 4'd0;
            adc_clk_d <= 1'b0;
            adc_data  <= 12'h800;
        end else begin
            adc_clk_d <= adc_clk;
            // On each ENCODE rising edge, present the next sine sample.
            if (adc_clk & ~adc_clk_d) begin
                adc_data <= sine12(phase);
                phase    <= phase + 4'd1;   // ~16 samples/cycle -> ~40kHz region
            end
        end
    end

    // ============================================================
    // Reference-ROM preload (sim only). top_level ties ref_wr_en LOW
    // (FIX-B2), so we load the BSRAM arrays through the hierarchical
    // path. Fill both references with the same sine pattern so the
    // zero-lag correlation against the live window is large & positive.
    // ============================================================
    integer r;
    task preload_references;
        begin
            for (r = 0; r < N_TAPS; r = r + 1) begin
                // ch1 (Buoy 1, up-sweep) reference MATCHES the live signal
                // (centered sine, signed-16 INTEGER scale per FC-1) so its
                // zero-lag correlation is large & positive.
                dut.u_mf1.ref_mem[r] = $signed({4'd0, sine12(r[3:0])}) - 16'sd2048;
                // ch2 (Buoy 2, down-sweep) reference is zeroed so its
                // correlation against the same window is ~0. This makes ch1
                // strictly DOMINANT (FC-7 ratio gate) -> target_id = 0x01,
                // exercising a real detection through peak_detector (FIX-B1)
                // and a non-zero corr_peak through the FIX-B3 packing field.
                dut.u_mf2.ref_mem[r] = 16'sd0;
                // Clear the window memories so there are no X's pre-fill.
                dut.u_mf1.window_mem[r] = 16'sd0;
                dut.u_mf2.window_mem[r] = 16'sd0;
            end
        end
    endtask

    // ============================================================
    // UART byte receiver: detect start bit, sample 8 data bits LSB-first
    // at bit-period centers, then the stop bit.
    // ============================================================
    reg  [7:0] rx_bytes [0:7];
    integer    byte_count;
    integer    b, i;
    reg [7:0]  rx_shift;

    // Sample one full 8N1 frame starting from a detected falling edge.
    task get_uart_byte;
        output [7:0] data;
        integer k;
        begin
            // Wait for the line to be idle-high first, then a falling edge.
            @(negedge uart_tx_out);
            // Now at the start-bit edge. Move to the middle of the start bit.
            repeat (CLKS_PER_BIT/2) @(posedge clk);
            // Check X/Z at start bit.
            if (uart_tx_out === 1'bx || uart_tx_out === 1'bz) xz_seen = xz_seen + 1;
            // Sample 8 data bits, LSB first, advancing one bit period each.
            for (k = 0; k < 8; k = k + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                if (uart_tx_out === 1'bx || uart_tx_out === 1'bz) xz_seen = xz_seen + 1;
                rx_shift[k] = uart_tx_out;
            end
            // Advance to the stop bit and verify it is high.
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (uart_tx_out !== 1'b1) begin
                $display("FAILED: stop bit not HIGH — got %b", uart_tx_out);
                $fatal;
            end
            data = rx_shift;
        end
    endtask

    // ============================================================
    // Main stimulus / checking sequence
    // ============================================================
    integer  got_detection;
    integer  pkt_seen;
    reg [7:0] cks;

    initial begin
        // init
        rst_n        = 1'b0;
        adc_data     = 12'h800;
        adc_otr      = 1'b0;
        adc_clk_edges = 0;
        xz_seen      = 0;
        byte_count   = 0;
        pkt_seen     = 0;
        got_detection = 0;
        adc_clk_q    = 1'b0;

        // Hold reset a few cycles, then release.
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // Preload references AFTER reset deasserts (window/ref arrays are
        // user-array regs; load them once the design is out of reset).
        preload_references;

        // ----------------------------------------------------------
        // Run the pipeline. The matched filter needs 2109 valid samples
        // per window. With a new sample every ~64 system clocks, the first
        // correlation completes after ~135k clocks. We then wait for the
        // peak detector to decide and the framer to emit a packet.
        // Use a generous wall-clock guard so the sim cannot hang.
        // ----------------------------------------------------------

        // ----------------------------------------------------------
        // Capture packets in a loop. The FIRST few decisions may be
        // target_id=0x00 ("neither" — e.g. before ch1's window has built a
        // strong correlation, or a tie at startup). We keep capturing until
        // we see a real ch1 detection (target_id=0x01 with a non-zero
        // corr_peak field), proving FIX-B1 (config-gated decision) and
        // FIX-B3 (saturating >>6 packing) end to end. A forked watchdog
        // bounds the wall-clock so the sim cannot hang.
        // ----------------------------------------------------------
        got_detection = 0;
        fork : wait_for_detection
            begin
                while (got_detection == 0) begin
                    capture_packet;              // decode one full 8-byte packet
                    check_packet_structure;      // structural checks on every packet
                    pkt_seen = pkt_seen + 1;
                    if (rx_bytes[0] == 8'h01 &&
                        {rx_bytes[3], rx_bytes[4]} != 16'h0000)
                        got_detection = 1;
                end
                disable wait_for_detection;
            end
            begin
                repeat (5_000_000) @(posedge clk);  // ~185 ms budget @ 27MHz
                $display("FAILED: no ch1 detection packet within clock budget (pkts seen=%0d)", pkt_seen);
                $fatal;
            end
        join

        // ---- FIX-W1: adc_clk must have toggled ----
        if (adc_clk_edges < 4) begin
            $display("FAILED: adc_clk did not toggle (edges=%0d) — FIX-W1", adc_clk_edges);
            $fatal;
        end
        $display("PASS: adc_clk toggled (edges counted=%0d) — FIX-W1", adc_clk_edges);

        // ---- FIX-B1: a real detection was gated through peak_detector ----
        if (rx_bytes[0] !== 8'h01) begin
            $display("FAILED: expected target_id=0x01 detection got %h", rx_bytes[0]);
            $fatal;
        end
        $display("PASS: target_id=0x01 (ch1 dominant via FC-7 ratio gate) — FIX-B1");

        // ---- FIX-B3: corr_peak field is the non-zero saturating >>6 slice ----
        if ({rx_bytes[3], rx_bytes[4]} === 16'h0000) begin
            $display("FAILED: corr_peak field is zero on a real detection — FIX-B3");
            $fatal;
        end
        $display("PASS: corr_peak field (>>6 saturating) = %h%h non-zero — FIX-B3",
                 rx_bytes[3], rx_bytes[4]);

        // ---- snr proxy should be non-zero on a strong detection ----
        if (rx_bytes[5] === 8'h00)
            $display("NOTE: snr proxy = 0 (magnitude below SNR_SHIFT=12 threshold)");
        else
            $display("PASS: snr proxy non-zero = %h", rx_bytes[5]);

        $display("PASS: %0d packet(s) captured before ch1 detection", pkt_seen);

        $display("ALL CHECKS PASSED — top_level");
        $finish;
    end

    // ============================================================
    // Per-packet structural checks (byte7 end marker, checksum, no X/Z).
    // Runs on EVERY captured packet.
    // ============================================================
    task check_packet_structure;
        begin
            if (byte_count != 8) begin
                $display("FAILED: incomplete packet, byte_count=%0d", byte_count);
                $fatal;
            end
            // byte 7 = 0xFF end marker
            if (rx_bytes[7] !== 8'hFF) begin
                $display("FAILED: end marker byte7 expected FF got %h", rx_bytes[7]);
                $fatal;
            end
            // checksum = XOR of bytes 0..5
            cks = rx_bytes[0] ^ rx_bytes[1] ^ rx_bytes[2] ^
                  rx_bytes[3] ^ rx_bytes[4] ^ rx_bytes[5];
            if (rx_bytes[6] !== cks) begin
                $display("FAILED: checksum byte6 expected %h got %h", cks, rx_bytes[6]);
                $fatal;
            end
            // no X/Z observed on serial line during transmit
            if (xz_seen != 0) begin
                $display("FAILED: %0d X/Z samples observed on uart_tx_out", xz_seen);
                $fatal;
            end
            $display("  packet OK: id=%h lag=%h%h corr=%h%h snr=%h cks=%h end=%h",
                     rx_bytes[0], rx_bytes[1], rx_bytes[2], rx_bytes[3],
                     rx_bytes[4], rx_bytes[5], rx_bytes[6], rx_bytes[7]);
        end
    endtask

    // ============================================================
    // Capture a full 8-byte packet. get_uart_byte() blocks on each byte's
    // own start-bit falling edge, so this task decodes 8 consecutive bytes
    // in order. The framer drives bytes back-to-back with only the uart_tx
    // state turnaround as the inter-byte gap, so every byte begins with its
    // own start bit and get_uart_byte re-syncs cleanly to each one.
    // ============================================================
    task capture_packet;
        integer j;
        reg [7:0] db;
        begin
            for (j = 0; j < 8; j = j + 1) begin
                get_uart_byte(db);
                rx_bytes[j] = db;
                $display("  rx byte[%0d] = %h @ %0t", j, db, $time);
            end
            byte_count = 8;
        end
    endtask

    // Absolute simulation safety timeout (larger than the fork budget so the
    // in-sequence watchdog reports first with a more specific message).
    initial begin
        #220_000_000;  // 220 ms — beyond the ~185ms detection-loop budget
        $display("FAILED: global timeout — pipeline never produced a packet");
        $fatal;
    end

endmodule
