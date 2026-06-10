// Timing test wrapper for fir_filter_bank1.
// Exposes only clk, rst_n, and one LED output so all data ports
// stay internal — avoids bank voltage conflicts from auto-placed IOs.
// Add fir_filter_bank1.v + this file to a Gowin project, set this
// as top module, use fir_test_top.cst, run P&R, check timing report.
// Delete this file after timing is confirmed — it has no place in the
// final pipeline.

module fir_test_top (
    input  wire clk,
    input  wire rst_n,
    output wire led          // XOR of dout — prevents optimizer removing FIR
);
    // Simple counter drives din_valid every 64 clocks (~422kSPS at 27MHz).
    reg [5:0]  cnt;
    reg signed [15:0] din;
    reg        din_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt       <= 6'd0;
            din       <= 16'sd0;
            din_valid <= 1'b0;
        end else begin
            cnt       <= cnt + 6'd1;
            din_valid <= (cnt == 6'd63);
            if (cnt == 6'd0)
                din <= din + 16'sd1;   // slowly incrementing test ramp
        end
    end

    wire signed [15:0] dout;
    wire               dout_valid;

    fir_filter_bank1 dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .din       (din),
        .din_valid (din_valid),
        .dout      (dout),
        .dout_valid(dout_valid)
    );

    // XOR-reduce dout so the optimizer cannot prune the FIR logic.
    assign led = ^dout;

endmodule
