// Module: adc_interface
// Description: AD9226 12-bit parallel capture with FPGA-generated ENCODE clock
//              and pipeline latency alignment. OTR is passed through as a flag;
//              data is captured unchanged (the AD9226 itself drives 0xFFF/0x000
//              on the rails during overflow).
// Target: Tang Nano 20K (GW2AR-18)
// System clock: 27MHz. ENCODE (adc_clk) = 27MHz / 8 = 3.375MHz (within 1-5MHz spec).
// HW note: AD9226 pipeline latency = 7 ENCODE cycles (datasheet Rev B).
// HW note: AD9226 DRVDD must be wired to 3.3V to match Tang Nano 20K 3.3V GPIO.
// Author: fpga-verilog-engineer agent
// Date: 2026-06-09

module adc_interface #(
    // ENCODE clock = system clk / (2*CLK_DIV_HALF).
    // CLK_DIV_HALF=4 -> divide-by-8 -> 3.375MHz from 27MHz.
    parameter integer CLK_DIV_HALF = 4
) (
    input  wire        clk,          // 27MHz system clock
    input  wire        rst_n,        // synchronous active-low reset
    input  wire [11:0] adc_data,     // AD9226 parallel data bus D[11:0]
    input  wire        otr,          // AD9226 out-of-range flag (1 = over/under range)
    output reg         adc_clk,      // FPGA-generated ENCODE clock to AD9226 (rising-edge sample)
    output reg signed [11:0] sample_out,   // signed two's-complement sample (AD9226 offset binary MSB-inverted per datasheet); declared signed to match cic_decimator's signed din (FIX-N1)
    output reg         sample_otr,   // registered OTR flag, aligned to sample_out's conversion
    output reg         sample_valid  // 1-cycle strobe each captured sample
);

    // ---------------------------------------------------------------
    // ENCODE clock generation: toggle adc_clk every CLK_DIV_HALF cycles
    // ---------------------------------------------------------------
    reg [$clog2(CLK_DIV_HALF):0] div_count;
    reg                          adc_clk_q;   // delayed copy for rising-edge detect

    wire adc_clk_rising = adc_clk & ~adc_clk_q;

    // ---------------------------------------------------------------
    // 7-cycle (ENCODE-cycle) pipeline latency alignment.
    // The AD9226 presents valid data 7 ENCODE cycles after the rising
    // edge that triggered the conversion (datasheet Rev B). We track each
    // rising edge and emit sample_valid on the 7th subsequent rising edge,
    // latching the data (and the registered OTR) belonging to that conversion.
    // ---------------------------------------------------------------
    reg [2:0] lat_count;   // counts ENCODE rising edges since a conversion start (0..7)
    reg       lat_active;  // a conversion is in flight through the pipeline

    always @(posedge clk) begin
        if (!rst_n) begin
            div_count    <= 0;
            adc_clk      <= 1'b0;
            adc_clk_q    <= 1'b0;
            lat_count    <= 3'd0;
            lat_active   <= 1'b0;
            sample_out   <= 12'h000;
            sample_otr   <= 1'b0;
            sample_valid <= 1'b0;
        end else begin
            // --- ENCODE clock divider ---
            adc_clk_q <= adc_clk;
            if (div_count == CLK_DIV_HALF - 1) begin
                div_count <= 0;
                adc_clk   <= ~adc_clk;
            end else begin
                div_count <= div_count + 1'b1;
            end

            // default: no strobe unless we complete a conversion this cycle
            sample_valid <= 1'b0;

            // --- pipeline-latency aligned capture, advanced on ENCODE rising edges ---
            if (adc_clk_rising) begin
                if (!lat_active) begin
                    // first rising edge after reset/idle starts the pipeline fill
                    lat_active <= 1'b1;
                    lat_count  <= 3'd1;
                end else if (lat_count < 3'd7) begin
                    lat_count <= lat_count + 3'd1;
                end else begin
                    // 7th ENCODE cycle reached: data on the bus is valid -> capture.
                    // AD9226 outputs offset binary (0x800 = 0V midscale). Invert the
                    // MSB to convert to two's complement so 0x800->0x000, 0xFFF->0x7FF,
                    // 0x000->0x800 (-2048). Required: cic_decimator declares signed din.
                    // {~adc_data[11], adc_data[10:0]} is the offset-binary->twos-comp map.
                    sample_out   <= {~adc_data[11], adc_data[10:0]}; // signed twos-comp
                    sample_otr   <= otr;           // OTR aligned to this conversion
                    sample_valid <= 1'b1;          // 1-cycle strobe
                    lat_count    <= 3'd7;          // steady state: one sample per ENCODE edge
                end
            end
        end
    end

endmodule
