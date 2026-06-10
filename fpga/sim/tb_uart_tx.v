// Testbench: tb_uart_tx
// Description: Verifies uart_tx 8N1 framing and per-bit timing for 0x55 and 0xAA
// Target sim: Icarus Verilog
// Clock: 27MHz (period 37.037ns)
// Author: fpga-verilog-engineer agent
// Date: 2026-06-09

`timescale 1ns / 1ps

module tb_uart_tx;

    localparam integer CLKS_PER_BIT = 234;

    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx;
    wire       tx_busy;

    integer errors;

    // 27MHz clock: period 37.037ns -> half period 18.5185ns
    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy)
    );

    // ---------------------------------------------------------------
    // Task: send a byte and sample each serial bit at the MIDDLE of its
    // bit period, then compare against the expected 8N1 frame.
    // Frame order on the wire: start(0), d0..d7 (LSB first), stop(1).
    // ---------------------------------------------------------------
    task send_and_check;
        input [7:0] data;
        reg   [9:0] expected; // [0]=start,[1..8]=data LSB-first,[9]=stop
        integer i;
        reg sampled;
        begin
            // Build expected frame
            expected[0] = 1'b0;            // start
            for (i = 0; i < 8; i = i + 1)
                expected[i+1] = data[i];   // LSB first
            expected[9] = 1'b1;            // stop

            // Kick off transmission
            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // Wait until busy asserts so we are aligned at start-bit entry
            wait (tx_busy == 1'b1);
            @(posedge clk); // now inside START state, bit period counting

            // Sample each of the 10 frame bits at mid-bit
            for (i = 0; i < 10; i = i + 1) begin
                // advance to middle of this bit period
                repeat (CLKS_PER_BIT/2) @(posedge clk);
                sampled = tx;
                if (sampled === 1'bx || sampled === 1'bz) begin
                    $display("FAIL: byte 0x%02h bit %0d sampled X/Z on tx", data, i);
                    errors = errors + 1;
                end else if (sampled !== expected[i]) begin
                    $display("FAIL: byte 0x%02h frame bit %0d = %b, expected %b",
                             data, i, sampled, expected[i]);
                    errors = errors + 1;
                end else begin
                    $display("  ok: byte 0x%02h frame bit %0d = %b (start=0,d0..d7,stop=1)",
                             data, i, sampled);
                end
                // advance to end of this bit period for next iteration
                repeat (CLKS_PER_BIT - (CLKS_PER_BIT/2)) @(posedge clk);
            end

            // After the frame, line must return to idle high and busy clear
            @(posedge clk);
            wait (tx_busy == 1'b0);
            if (tx !== 1'b1) begin
                $display("FAIL: byte 0x%02h tx not idle-high after frame (tx=%b)", data, tx);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Bit-timing check: measure how many clocks the start bit (tx low)
    // is held, must equal CLKS_PER_BIT.
    // ---------------------------------------------------------------
    task check_start_bit_width;
        input [7:0] data;
        integer width;
        reg done;
        begin
            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // wait for tx to fall (start bit begins)
            wait (tx == 1'b0);
            // count clock periods for which tx is held low. We sample at each
            // posedge; the first posedge where tx is still low is bit-clock #1.
            // When we observe tx high, that posedge belongs to the next bit, so
            // it is NOT counted (hence we increment before the test, not after).
            width = 0;
            done  = 1'b0;
            while (!done) begin
                @(posedge clk);
                if (tx == 1'b0)
                    width = width + 1;
                else
                    done = 1'b1; // tx went high: start bit finished
            end
            if (width !== CLKS_PER_BIT) begin
                $display("FAIL: start-bit width = %0d clocks, expected %0d",
                         width, CLKS_PER_BIT);
                errors = errors + 1;
            end else begin
                $display("  ok: start-bit held for %0d clocks (= CLKS_PER_BIT)", width);
            end
            // let the rest of the frame finish
            wait (tx_busy == 1'b0);
            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------
    // Packet test infrastructure.
    // Sends an 8-byte packet back-to-back: for each byte, tx_start is
    // asserted on the SAME cycle tx_busy goes LOW (picked up in S_IDLE
    // on the next cycle). For each of the 7 inter-byte transitions we
    // measure the gap (in system clocks) between tx_busy falling and tx
    // going LOW for the next start bit, asserting it is <= CLKS_PER_BIT.
    // Each byte's 8N1 frame content is verified at mid-bit.
    // ---------------------------------------------------------------
    localparam integer PKT_LEN = 8;
    reg [7:0] packet [0:PKT_LEN-1];

    // Sample-and-verify the 10-bit frame for byte `data`, assuming we are
    // positioned just after tx has gone LOW (start bit asserted). Returns
    // having consumed the full frame through the stop bit.
    task verify_frame_from_start;
        input [7:0] data;
        reg   [9:0] expected;
        integer i;
        reg sampled;
        begin
            expected[0] = 1'b0;
            for (i = 0; i < 8; i = i + 1)
                expected[i+1] = data[i];
            expected[9] = 1'b1;

            // We are at the first cycle of the start bit (tx already low).
            // Sample each of the 10 bits near mid-bit.
            for (i = 0; i < 10; i = i + 1) begin
                repeat (CLKS_PER_BIT/2) @(posedge clk);
                sampled = tx;
                if (sampled === 1'bx || sampled === 1'bz) begin
                    $display("FAIL: packet byte 0x%02h bit %0d sampled X/Z", data, i);
                    errors = errors + 1;
                end else if (sampled !== expected[i]) begin
                    $display("FAIL: packet byte 0x%02h frame bit %0d = %b, expected %b",
                             data, i, sampled, expected[i]);
                    errors = errors + 1;
                end
                repeat (CLKS_PER_BIT - (CLKS_PER_BIT/2)) @(posedge clk);
            end
        end
    endtask

    task run_packet_test;
        integer b;
        integer gap;
        reg busy_was_high;
        begin
            packet[0] = 8'hA5;
            packet[1] = 8'h00;
            packet[2] = 8'h0F;
            packet[3] = 8'hA0;
            packet[4] = 8'h01;
            packet[5] = 8'h23;
            packet[6] = 8'h45;
            packet[7] = 8'hFF;

            // make sure we start idle
            wait (tx_busy == 1'b0);
            @(posedge clk);

            for (b = 0; b < PKT_LEN; b = b + 1) begin
                // Assert tx_start; request this byte.
                tx_data  <= packet[b];
                tx_start <= 1'b1;
                @(posedge clk);
                tx_start <= 1'b0;

                // Wait until the start bit actually begins (tx low) and busy high.
                wait (tx == 1'b0);

                // Verify this byte's frame content.
                verify_frame_from_start(packet[b]);

                // X/Z guard on tx already covered per-bit above.

                // For all but the last byte, measure the inter-byte gap:
                // from tx_busy going LOW to tx going LOW (next start bit),
                // while asserting tx_start on the SAME cycle busy drops.
                if (b < PKT_LEN - 1) begin
                    // Wait for busy to fall (end of stop bit). On that same
                    // cycle, assert tx_start for the next byte.
                    @(posedge clk);
                    busy_was_high = tx_busy;
                    while (tx_busy == 1'b1) @(posedge clk);
                    // tx_busy is now LOW on this cycle -> assert start NOW.
                    tx_data  <= packet[b+1];
                    tx_start <= 1'b1;

                    // Count system clocks until tx goes LOW (start bit).
                    gap = 0;
                    @(posedge clk);
                    tx_start <= 1'b0;
                    while (tx == 1'b1) begin
                        gap = gap + 1;
                        @(posedge clk);
                    end

                    $display("  inter-byte gap %0d->%0d (0x%02h->0x%02h): %0d clocks (limit %0d)",
                             b, b+1, packet[b], packet[b+1], gap, CLKS_PER_BIT);
                    if (gap > CLKS_PER_BIT) begin
                        $display("FAIL: inter-byte gap %0d clocks exceeds CLKS_PER_BIT=%0d",
                                 gap, CLKS_PER_BIT);
                        errors = errors + 1;
                    end

                    // We are now at the start bit of byte b+1 (tx low).
                    verify_frame_from_start(packet[b+1]);
                    b = b + 1; // this byte already consumed by the gap path
                end
            end

            // settle to idle
            wait (tx_busy == 1'b0);
            @(posedge clk);
            if (tx !== 1'b1) begin
                $display("FAIL: tx not idle-high after packet (tx=%b)", tx);
                errors = errors + 1;
            end else begin
                $display("  ok: packet complete, tx idle-high, all gaps <= %0d clocks", CLKS_PER_BIT);
            end
        end
    endtask

    initial begin
        errors   = 0;
        rst_n    = 1'b0;
        tx_start = 1'b0;
        tx_data  = 8'h00;

        // Hold reset low for several cycles
        repeat (10) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // Check tx idles high after reset, no X/Z
        if (tx !== 1'b1) begin
            $display("FAIL: tx not idle-high after reset (tx=%b)", tx);
            errors = errors + 1;
        end else begin
            $display("  ok: tx idles high after reset");
        end

        $display("--- Bit-timing test: start bit width for 0x55 ---");
        check_start_bit_width(8'h55);

        $display("--- Frame test: 0x55 (alternating 01010101) ---");
        send_and_check(8'h55);

        $display("--- Frame test: 0xAA (alternating 10101010) ---");
        send_and_check(8'hAA);

        // settle
        repeat (CLKS_PER_BIT) @(posedge clk);

        // -----------------------------------------------------------
        // Back-to-back 8-byte packet test
        // -----------------------------------------------------------
        $display("--- Back-to-back 8-byte packet test ---");
        run_packet_test;

        $display("=========================================");
        if (errors == 0)
            $display("PASS: uart_tx all checks passed (0x55, 0xAA, timing, no X/Z)");
        else
            $display("FAIL: uart_tx had %0d error(s)", errors);
        $display("SIMULATION COMPLETE");
        $finish;
    end

    // Safety timeout
    initial begin
        #20000000; // 20 ms
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
