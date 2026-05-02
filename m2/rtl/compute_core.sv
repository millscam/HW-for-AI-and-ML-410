// =============================================================================
// Module      : compute_core
// Project     : Sign-Language Gesture Recognition Accelerator (M2)
// File        : project/m2/rtl/compute_core.sv
//
// Description :
//   Fused BGR-to-grayscale and in-range threshold pixel engine.  This is the
//   Phase-1 compute core targeting the OpenCV cvtColor(BGR→GRAY) + inRange /
//   bitwise_and hot-path identified as the M1 software bottleneck (22 s / 10
//   passes, ~40 fps, ~4.5 GB/s implied traffic per sw_baseline.md).
//
//   Datapath — 2-stage pipeline (one result per clock, 2-cycle latency):
//     Stage 1  parallel multiply   gray_partial = R×77  +  G×150  +  B×29
//     Stage 2  accumulate & shift  gray = gray_partial[15:8]   (÷256, i.e. >>8)
//                                  mask = (gray ≥ lo_thresh) & (gray ≤ hi_thresh)
//
//   Integer BT.601 coefficients (×256, rounded):
//     R: 0.299 × 256 ≈ 77    G: 0.587 × 256 ≈ 150    B: 0.114 × 256 ≈ 29
//   Maximum partial sum: 255×77 + 255×150 + 255×29 = 65 280 < 2^16 → no overflow.
//
// Clock domain : single clock (clk), rising-edge triggered
// Reset        : synchronous, active-high (rst) — all pipeline registers → 0
//
// Port table:
//   Name        Dir   Width   Description
//   ----------  ----  ------  -------------------------------------------------
//   clk          in     1     System clock (all FFs on this single domain)
//   rst          in     1     Synchronous active-high reset
//   valid_in     in     1     Input pixel valid strobe (hold stable while high)
//   b_in         in     8     Blue  channel, unsigned, 0–255
//   g_in         in     8     Green channel, unsigned, 0–255
//   r_in         in     8     Red   channel, unsigned, 0–255
//   lo_thresh    in     8     Lower bound for in-range check (inclusive)
//   hi_thresh    in     8     Upper bound for in-range check (inclusive)
//   valid_out    out    1     Output valid; asserts exactly 2 cycles after valid_in
//   gray_out     out    8     Grayscale luminance, unsigned 0–255
//   mask_out     out    1     1 if gray_out ∈ [lo_thresh, hi_thresh], else 0
// =============================================================================

`default_nettype none

module compute_core (
    input  wire        clk,
    input  wire        rst,

    // Input pixel stream
    input  wire        valid_in,
    input  wire [7:0]  b_in,
    input  wire [7:0]  g_in,
    input  wire [7:0]  r_in,

    // Threshold parameters (can be held constant or updated each cycle)
    input  wire [7:0]  lo_thresh,
    input  wire [7:0]  hi_thresh,

    // Output pixel stream (2-cycle latency)
    output logic       valid_out,
    output logic [7:0] gray_out,
    output logic       mask_out
);

    // =========================================================================
    // Stage 1 — Parallel multiply
    //   Each product width is sized to the exact maximum value:
    //     R×77  max = 255×77  = 19 635  → 15 bits (2^14 = 16 384 < 19 635 < 2^15)
    //     G×150 max = 255×150 = 38 250  → 16 bits (2^15 = 32 768 < 38 250 < 2^16)
    //     B×29  max = 255×29  =  7 395  → 13 bits (2^12 =  4 096 <  7 395 < 2^13)
    //   Threshold bounds pipelined alongside data to keep control synchronous.
    // =========================================================================
    logic        s1_valid;
    logic [14:0] s1_r77;    // R * 77
    logic [15:0] s1_g150;   // G * 150
    logic [12:0] s1_b29;    // B * 29
    logic [7:0]  s1_lo;
    logic [7:0]  s1_hi;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
            s1_r77   <= 15'd0;
            s1_g150  <= 16'd0;
            s1_b29   <= 13'd0;
            s1_lo    <= 8'd0;
            s1_hi    <= 8'd0;
        end else begin
            s1_valid <= valid_in;
            s1_r77   <= r_in * 8'd77;    // 15-bit context from target
            s1_g150  <= g_in * 8'd150;   // 16-bit context from target
            s1_b29   <= b_in * 8'd29;    // 13-bit context from target
            s1_lo    <= lo_thresh;
            s1_hi    <= hi_thresh;
        end
    end

    // =========================================================================
    // Combinational adder tree between stages
    //   All three terms zero-extended to 16 bits before adding.
    //   Total max = 19 635 + 38 250 + 7 395 = 65 280 < 65 536 (2^16) → no carry out.
    // =========================================================================
    logic [15:0] s2_sum;
    assign s2_sum = ({1'b0, s1_r77} + s1_g150) + {3'b000, s1_b29};

    // =========================================================================
    // Stage 2 — Accumulate, shift, and threshold
    //   gray = s2_sum >> 8  (bits [15:8] of the 16-bit sum)
    //   mask = 1 if gray is within the [lo, hi] in-range band
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            gray_out  <= 8'd0;
            mask_out  <= 1'b0;
        end else begin
            valid_out <= s1_valid;
            gray_out  <= s2_sum[15:8];
            mask_out  <= (s2_sum[15:8] >= s1_lo) && (s2_sum[15:8] <= s1_hi);
        end
    end

endmodule

`default_nettype wire
