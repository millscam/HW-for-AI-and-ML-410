// =============================================================================
// Module      : synth_top  (M3: 2-lane parallel pixel engine)
// Project     : Sign-Language Gesture Recognition Accelerator (M4)
// File        : project/m4/rtl/synth_top.sv
// Lineage     : CF07/M3 signoff target (2-lane); OpenLane synthesis uses this module.
// Source      : derived from project/m2/rtl/compute_core.sv (single-lane)
//
// Description :
//   2-lane version of the M2 compute_core, used as the synthesis target for
//   the M3 throughput push. Each cycle two independent BGR pixels enter the
//   datapath in parallel; they share clk, rst, valid_in and the lo/hi
//   thresholds. After the 2-cycle pipeline, two grayscale + mask pairs come
//   out per cycle, gated by a single valid_out.
//
//   Throughput model (independent of the synthesis report):
//     fps  =  CLK_HZ * LANES / (1920 * 1080)
//     e.g. 77 MHz * 2 / 2_073_600  ~=  74 fps
//          83 MHz * 2 / 2_073_600  ~=  80 fps
//
//   Datapath per lane (unchanged from M2):
//     Stage 1: parallel multiplies  R*77, G*150, B*29   (BT.601 *256)
//     Stage 2: zero-extend, sum, then >> 8 (i.e. take s2_sum[15:8])
//              mask = (gray >= lo_thresh) && (gray <= hi_thresh)
//
//   Integer BT.601 coefficients (*256, rounded):
//     R: 0.299 * 256 ~= 77   G: 0.587 * 256 ~= 150   B: 0.114 * 256 ~= 29
//   Max partial sum: 255*77 + 255*150 + 255*29 = 65_280 < 2^16 -> no overflow.
//
// Clock domain : single clock (clk), rising-edge triggered
// Reset        : synchronous, active-high (rst). The threshold inputs (lo/hi)
//                are pipelined once so they stay in lock-step with the
//                data through stage 2.
//
// Port table:
//   Name         Dir   Width  Description
//   -----------  ----  -----  ------------------------------------------------
//   clk           in     1    System clock (all FFs on this single domain)
//   rst           in     1    Synchronous active-high reset
//   valid_in      in     1    Strobe (both lanes consume on the same cycle)
//   b_in_0/1      in     8    Lane n blue  channel, unsigned 0-255
//   g_in_0/1      in     8    Lane n green channel, unsigned 0-255
//   r_in_0/1      in     8    Lane n red   channel, unsigned 0-255
//   lo_thresh     in     8    Shared lower bound for in-range mask (inclusive)
//   hi_thresh     in     8    Shared upper bound for in-range mask (inclusive)
//   valid_out     out    1    Output valid; asserts exactly 2 cycles after
//                             valid_in (both lanes are in lockstep)
//   gray_out_0/1  out    8    Lane n grayscale luminance, unsigned 0-255
//   mask_out_0/1  out    1    Lane n 1 iff gray_out_n in [lo_thresh, hi_thresh]
// =============================================================================

`default_nettype none

module synth_top (
    input  wire        clk,
    input  wire        rst,

    input  wire        valid_in,

    // Lane 0 input pixel
    input  wire [7:0]  b_in_0,
    input  wire [7:0]  g_in_0,
    input  wire [7:0]  r_in_0,

    // Lane 1 input pixel
    input  wire [7:0]  b_in_1,
    input  wire [7:0]  g_in_1,
    input  wire [7:0]  r_in_1,

    // Shared thresholds
    input  wire [7:0]  lo_thresh,
    input  wire [7:0]  hi_thresh,

    // Lane 0 output pixel
    output logic       valid_out,
    output logic [7:0] gray_out_0,
    output logic       mask_out_0,

    // Lane 1 output pixel
    output logic [7:0] gray_out_1,
    output logic       mask_out_1
);

    // =========================================================================
    // Stage 1 - Shared control + per-lane parallel multiplies
    //   s1_valid / s1_lo / s1_hi are shared by both lanes (single set of FFs)
    //   so the 2 lanes do not double the fanout of valid_in / lo_thresh /
    //   hi_thresh by themselves.
    // =========================================================================
    logic        s1_valid;
    logic [7:0]  s1_lo;
    logic [7:0]  s1_hi;

    logic [14:0] s1_r77_0;
    logic [15:0] s1_g150_0;
    logic [12:0] s1_b29_0;

    logic [14:0] s1_r77_1;
    logic [15:0] s1_g150_1;
    logic [12:0] s1_b29_1;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid  <= 1'b0;
            s1_lo     <= 8'd0;
            s1_hi     <= 8'd0;

            s1_r77_0  <= 15'd0;
            s1_g150_0 <= 16'd0;
            s1_b29_0  <= 13'd0;

            s1_r77_1  <= 15'd0;
            s1_g150_1 <= 16'd0;
            s1_b29_1  <= 13'd0;
        end else begin
            s1_valid  <= valid_in;
            s1_lo     <= lo_thresh;
            s1_hi     <= hi_thresh;

            s1_r77_0  <= r_in_0 * 8'd77;
            s1_g150_0 <= g_in_0 * 8'd150;
            s1_b29_0  <= b_in_0 * 8'd29;

            s1_r77_1  <= r_in_1 * 8'd77;
            s1_g150_1 <= g_in_1 * 8'd150;
            s1_b29_1  <= b_in_1 * 8'd29;
        end
    end

    // =========================================================================
    // Combinational adder tree between stages (one per lane)
    //   All three terms zero-extended to 16 bits before adding.
    //   Total max = 19_635 + 38_250 + 7_395 = 65_280 < 2^16 -> no carry out.
    // =========================================================================
    logic [15:0] s2_sum_0;
    logic [15:0] s2_sum_1;

    assign s2_sum_0 = ({1'b0, s1_r77_0} + s1_g150_0) + {3'b000, s1_b29_0};
    assign s2_sum_1 = ({1'b0, s1_r77_1} + s1_g150_1) + {3'b000, s1_b29_1};

    // =========================================================================
    // Stage 2 - Accumulate, shift, threshold (per lane)
    //   gray = s2_sum >> 8   (i.e. s2_sum[15:8])
    //   mask = 1 iff gray is within the [lo, hi] in-range band
    //   valid_out is shared (both lanes always finish together).
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out  <= 1'b0;

            gray_out_0 <= 8'd0;
            mask_out_0 <= 1'b0;

            gray_out_1 <= 8'd0;
            mask_out_1 <= 1'b0;
        end else begin
            valid_out  <= s1_valid;

            gray_out_0 <= s2_sum_0[15:8];
            mask_out_0 <= (s2_sum_0[15:8] >= s1_lo) && (s2_sum_0[15:8] <= s1_hi);

            gray_out_1 <= s2_sum_1[15:8];
            mask_out_1 <= (s2_sum_1[15:8] >= s1_lo) && (s2_sum_1[15:8] <= s1_hi);
        end
    end

endmodule

`default_nettype wire
