// =============================================================================
// Module      : tb_compute_core
// File        : project/m2/tb/tb_compute_core.sv
// Project     : Sign-Language Gesture Recognition Accelerator (M2)
//
// Testbench for compute_core — fused BGR-to-grayscale + in-range threshold.
//
// Reference values are computed INDEPENDENTLY before running the DUT using the
// BT.601 integer formula:
//   gray = (R*77 + G*150 + B*29) >> 8
//   mask = 1  if  lo_thresh <= gray <= hi_thresh,  else 0
//
// Test vectors cover:
//   vec 0 — black pixel       (all-zeros baseline)
//   vec 1 — pure red          (R channel only)
//   vec 2 — pure green        (G channel only)
//   vec 3 — pure blue         (B channel only)
//   vec 4 — white             (all channels saturated)
//   vec 5 — skin-tone-like    (representative M1 Phase-1 hot-path pixel)
//   vec 6 — dark background   (exercises mask_out = 0)
//   vec 7 — mid-gray          (equal R/G/B, mid-range threshold check)
//
// Independent hand-computed reference table:
//   vec  B    G    R    R*77  G*150  B*29   sum    gray  lo   hi  mask
//    0:   0    0    0       0      0     0      0      0    0  255    1
//    1:   0    0  255   19635      0     0  19635     76    0  255    1
//    2:   0  255    0       0  38250     0  38250    149    0  255    1
//    3: 255    0    0       0      0  7395   7395     28    0  255    1
//    4: 255  255  255   19635  38250  7395  65280    255    0  255    1
//    5: 100  150  200   15400  22500  2900  40800    159  100  200    1
//    6:  10   30   20    1540   4500   290   6330     24  100  200    0
//    7: 128  128  128    9856  19200  3712  32768    128  100  200    1
//
// Pipeline latency: 2 clock cycles (input → valid_out).
// Simulation: iverilog -g2012 tb_compute_core.sv compute_core.sv -o sim.out
//             vvp sim.out
// Pass criterion: final line contains "PASS".
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_compute_core;

    // -------------------------------------------------------------------------
    // DUT interface signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst;
    logic        valid_in;
    logic [7:0]  b_in, g_in, r_in;
    logic [7:0]  lo_thresh, hi_thresh;
    logic        valid_out;
    logic [7:0]  gray_out;
    logic        mask_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    compute_core dut (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (valid_in),
        .b_in      (b_in),
        .g_in      (g_in),
        .r_in      (r_in),
        .lo_thresh (lo_thresh),
        .hi_thresh (hi_thresh),
        .valid_out (valid_out),
        .gray_out  (gray_out),
        .mask_out  (mask_out)
    );

    // -------------------------------------------------------------------------
    // 10 ns period clock (100 MHz)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // =========================================================================
    // Reference test vectors — all values derived independently of the DUT
    // =========================================================================
    localparam NUM_VEC = 8;

    // Stimulus arrays (element-by-element init in initial block for iverilog compat)
    logic [7:0] tv_b     [0:NUM_VEC-1];
    logic [7:0] tv_g     [0:NUM_VEC-1];
    logic [7:0] tv_r     [0:NUM_VEC-1];
    logic [7:0] tv_lo    [0:NUM_VEC-1];
    logic [7:0] tv_hi    [0:NUM_VEC-1];

    // Expected outputs (computed by hand — see table in header)
    logic [7:0] exp_gray [0:NUM_VEC-1];
    logic       exp_mask [0:NUM_VEC-1];

    // =========================================================================
    // Stimulus driver and output checker
    // =========================================================================
    integer i;
    integer out_idx;
    integer fail_count;

    initial begin
`ifdef DUMP_VCD
        $dumpfile("tb_compute_core.vcd");
        $dumpvars(0, tb_compute_core);
`endif

        // ------ load reference vectors (independent hand calculations) ------
        // vec  B    G    R   gray  lo   hi  mask
        tv_b[0]=  0; tv_g[0]=  0; tv_r[0]=  0; tv_lo[0]=  0; tv_hi[0]=255; exp_gray[0]=  0; exp_mask[0]=1'b1;
        tv_b[1]=  0; tv_g[1]=  0; tv_r[1]=255; tv_lo[1]=  0; tv_hi[1]=255; exp_gray[1]= 76; exp_mask[1]=1'b1;
        tv_b[2]=  0; tv_g[2]=255; tv_r[2]=  0; tv_lo[2]=  0; tv_hi[2]=255; exp_gray[2]=149; exp_mask[2]=1'b1;
        tv_b[3]=255; tv_g[3]=  0; tv_r[3]=  0; tv_lo[3]=  0; tv_hi[3]=255; exp_gray[3]= 28; exp_mask[3]=1'b1;
        tv_b[4]=255; tv_g[4]=255; tv_r[4]=255; tv_lo[4]=  0; tv_hi[4]=255; exp_gray[4]=255; exp_mask[4]=1'b1;
        tv_b[5]=100; tv_g[5]=150; tv_r[5]=200; tv_lo[5]=100; tv_hi[5]=200; exp_gray[5]=159; exp_mask[5]=1'b1;
        tv_b[6]= 10; tv_g[6]= 30; tv_r[6]= 20; tv_lo[6]=100; tv_hi[6]=200; exp_gray[6]= 24; exp_mask[6]=1'b0;
        tv_b[7]=128; tv_g[7]=128; tv_r[7]=128; tv_lo[7]=100; tv_hi[7]=200; exp_gray[7]=128; exp_mask[7]=1'b1;

        // ------ initialise all DUT inputs ------
        rst       = 1'b1;
        valid_in  = 1'b0;
        b_in      = 8'd0;
        g_in      = 8'd0;
        r_in      = 8'd0;
        lo_thresh = 8'd0;
        hi_thresh = 8'd255;
        fail_count = 0;
        out_idx    = 0;

        $display("=============================================================");
        $display("  tb_compute_core : compute_core BGR->Gray + threshold check ");
        $display("=============================================================");
        $display("vec |  B   G   R  | gray_out | exp_gray | mask | exp  | chk");
        $display("----|-------------|----------|----------|------|------|-----");

        // ------ single synchronous reset clock ------
        @(posedge clk); #1;
        rst = 1'b0;

        // ------ stream NUM_VEC inputs, collect outputs as they emerge ------
        // The DUT has exactly 2-cycle latency: output for vec[k] is valid
        // 2 posedges after vec[k] was applied.
        // We run NUM_VEC + 1 iterations:
        //   i = 0 .. NUM_VEC-1 : apply vec[i]
        //   i = NUM_VEC         : flush (valid_in=0) — last output appears here
        for (i = 0; i < NUM_VEC + 1; i++) begin

            if (i < NUM_VEC) begin
                valid_in  = 1'b1;
                b_in      = tv_b[i];
                g_in      = tv_g[i];
                r_in      = tv_r[i];
                lo_thresh = tv_lo[i];
                hi_thresh = tv_hi[i];
            end else begin
                valid_in  = 1'b0;
                b_in      = 8'd0;
                g_in      = 8'd0;
                r_in      = 8'd0;
            end

            @(posedge clk); #1;

            // Output for vec[out_idx] is available when valid_out asserts.
            // First valid_out appears at iteration i=1 (2 clocks after vec[0] input).
            if (valid_out) begin
                if (gray_out === exp_gray[out_idx] && mask_out === exp_mask[out_idx]) begin
                    $display(" %2d | %3d %3d %3d |    %3d   |    %3d   |   %0b  |   %0b  |  OK",
                             out_idx,
                             tv_b[out_idx], tv_g[out_idx], tv_r[out_idx],
                             gray_out, exp_gray[out_idx],
                             mask_out, exp_mask[out_idx]);
                end else begin
                    $display(" %2d | %3d %3d %3d |    %3d   |    %3d   |   %0b  |   %0b  |  FAIL <<<",
                             out_idx,
                             tv_b[out_idx], tv_g[out_idx], tv_r[out_idx],
                             gray_out, exp_gray[out_idx],
                             mask_out, exp_mask[out_idx]);
                    fail_count = fail_count + 1;
                end
                out_idx = out_idx + 1;
            end
        end

        // ------ verify all vectors were seen ------
        if (out_idx !== NUM_VEC) begin
            $display("ERROR: expected %0d outputs, received %0d", NUM_VEC, out_idx);
            fail_count = fail_count + 1;
        end

        // ------ also verify reset clears outputs ------
        rst = 1'b1;
        @(posedge clk); #1;
        if (valid_out !== 1'b0 || gray_out !== 8'd0 || mask_out !== 1'b0) begin
            $display("FAIL: reset check — valid_out=%0b gray_out=%0d mask_out=%0b (expected 0 0 0)",
                     valid_out, gray_out, mask_out);
            fail_count = fail_count + 1;
        end else begin
            $display(" -- | reset check       |     0    |     0    |   0  |   0  |  OK");
        end
        rst = 1'b0;

        // ------ final verdict ------
        $display("=============================================================");
        if (fail_count == 0)
            $display("PASS -- all %0d vectors matched expected output", NUM_VEC);
        else
            $display("FAIL -- %0d of %0d checks did not match", fail_count, NUM_VEC);
        $display("=============================================================");

        $finish;
    end

endmodule

`default_nettype wire
