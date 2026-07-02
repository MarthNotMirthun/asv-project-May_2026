// Testbench: tb_uart_rx
// Description: Verifies uart_rx 8N1 framing, 2-FF sync, glitch rejection,
//              framing-error byte drop, and 4-byte [addr_hi][addr_lo]
//              [data_hi][data_lo] frame assembly (incl. negative FC-1
//              signed-16 values).
// Target sim: Icarus Verilog
// Clock: 27MHz (period 37.037ns)
// Author: fpga-verilog-engineer agent
// Date: 2026-07-01

`timescale 1ns / 1ps

module tb_uart_rx;

    localparam integer CLKS_PER_BIT = 234;

    reg  clk;
    reg  rst_n;
    reg  rx;
    wire signed [15:0] data_out;
    wire        data_valid;
    wire [15:0] addr_out;

    integer errors;

    // 27MHz clock: period 37.037ns -> half period 18.5185ns
    initial clk = 1'b0;
    always #18.5185 clk = ~clk;

    // ---------------------------------------------------------------
    // Continuous monitor: data_valid is a single-cycle pulse that lands
    // mid-transmission (during the 4th byte's stop bit, ~9.5 bit periods
    // after that byte's start), NOT after the testbench's bit-banging
    // task returns. Polling for it afterwards misses it entirely, so
    // latch it as it happens and have the check tasks read the latch.
    // ---------------------------------------------------------------
    reg        seen_valid;
    reg [15:0] seen_addr;
    reg signed [15:0] seen_data;

    always @(posedge clk) begin
        if (data_valid) begin
            seen_valid <= 1'b1;
            seen_addr  <= addr_out;
            seen_data  <= data_out;
        end
    end

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (rx),
        .data_out   (data_out),
        .data_valid (data_valid),
        .addr_out   (addr_out)
    );

    // ---------------------------------------------------------------
    // Task: bit-bang one 8N1 byte onto rx (idle high, start=0, d0..d7
    // LSB first, stop=1), each bit held for CLKS_PER_BIT clocks.
    // ---------------------------------------------------------------
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx = 1'b0;                       // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];                // LSB first
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx = 1'b1;                       // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // Bit-bang one byte with a BAD (low) stop bit, to trigger the
    // framing-error guard in uart_rx.v's S_STOP state.
    task send_byte_bad_stop;
        input [7:0] data;
        integer i;
        begin
            rx = 1'b0;                       // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx = 1'b0;                       // BAD stop bit (should be 1)
            repeat (CLKS_PER_BIT) @(posedge clk);
            rx = 1'b1;                       // release line back to idle
        end
    endtask

    // Send a full 4-byte frame and check the resulting addr_out/data_out,
    // using the seen_valid/seen_addr/seen_data latch (see monitor above)
    // since the actual data_valid pulse fires mid-transmission.
    task send_frame_and_check;
        input [15:0] addr;
        input signed [15:0] data;
        begin
            seen_valid = 1'b0;
            send_byte(addr[15:8]);
            send_byte(addr[7:0]);
            send_byte(data[15:8]);
            send_byte(data[7:0]);
            repeat (4) @(posedge clk);  // margin past the last byte's pulse point

            if (!seen_valid) begin
                $display("FAIL: frame addr=0x%04h data=%0d never asserted data_valid", addr, data);
                errors = errors + 1;
            end else begin
                if (seen_addr !== addr) begin
                    $display("FAIL: addr_out=0x%04h, expected 0x%04h", seen_addr, addr);
                    errors = errors + 1;
                end
                if (seen_data !== data) begin
                    $display("FAIL: data_out=%0d, expected %0d", seen_data, data);
                    errors = errors + 1;
                end
                if (seen_addr === addr && seen_data === data) begin
                    $display("  ok: frame addr=0x%04h data=%0d captured correctly", addr, data);
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n  = 1'b0;
        rx     = 1'b1;  // idle high

        repeat (10) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        if (data_valid !== 1'b0) begin
            $display("FAIL: data_valid not low after reset");
            errors = errors + 1;
        end else begin
            $display("  ok: data_valid low after reset");
        end

        // ---- Basic positive-value frame ----
        $display("--- Frame test: addr=0x1000, data=+12345 ---");
        send_frame_and_check(16'h1000, 16'sd12345);

        // ---- Negative signed-16 value (FC-1 sign integrity) ----
        $display("--- Frame test: addr=0x1001, data=-12345 (sign check) ---");
        send_frame_and_check(16'h1001, -16'sd12345);

        // ---- Full-scale negative (most negative signed-16) ----
        $display("--- Frame test: addr=0x2000, data=-32768 (full-scale negative) ---");
        send_frame_and_check(16'h2000, -16'sd32768);

        // ---- Config-register-range address (per documented convention) ----
        $display("--- Frame test: addr=0x0002 (K_SHIFT slot), data=4 ---");
        send_frame_and_check(16'h0002, 16'sd4);

        // ---- Back-to-back frames ----
        $display("--- Back-to-back frame test ---");
        send_frame_and_check(16'h1002, 16'sd100);
        send_frame_and_check(16'h1003, -16'sd200);

        // ---- Glitch rejection: a start-bit-looking pulse shorter than
        // half a bit period must NOT be captured as a byte. ----
        $display("--- Glitch rejection test ---");
        seen_valid = 1'b0;
        rx = 1'b0;
        repeat (CLKS_PER_BIT / 4) @(posedge clk);   // too short to reach the midpoint check
        rx = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
        if (seen_valid) begin
            $display("FAIL: glitch was captured as a valid frame byte");
            errors = errors + 1;
        end else begin
            $display("  ok: glitch correctly rejected, no data_valid");
        end
        // Confirm the receiver still works normally after a rejected glitch.
        send_frame_and_check(16'h1004, 16'sd777);

        // ---- Framing error: bad stop bit (held low instead of high) must
        // silently drop the byte rather than propagating corrupt data. ----
        $display("--- Framing-error (bad stop bit) test ---");
        seen_valid = 1'b0;
        send_byte_bad_stop(8'hAA);
        repeat (CLKS_PER_BIT) @(posedge clk);
        if (seen_valid) begin
            $display("FAIL: frame with a bad stop bit still produced data_valid");
            errors = errors + 1;
        end else begin
            $display("  ok: bad-stop-bit byte dropped, no data_valid");
        end
        // Confirm the receiver resyncs and works normally on the next
        // full frame after the dropped byte.
        send_frame_and_check(16'h1005, 16'sd321);

        // X/Z guard on outputs throughout.
        if (data_out === 16'bx || addr_out === 16'bx) begin
            $display("FAIL: X state observed on data_out/addr_out");
            errors = errors + 1;
        end

        $display("=========================================");
        if (errors == 0)
            $display("PASS: uart_rx all checks passed");
        else
            $display("FAIL: uart_rx had %0d error(s)", errors);
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
