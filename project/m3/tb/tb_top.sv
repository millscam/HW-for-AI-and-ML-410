// =============================================================================
// Module      : tb_top
// File        : project/m3/tb/tb_top.sv
// Project     : Sign-Language Gesture Recognition Accelerator (M3)
//
// End-to-end co-simulation testbench for the integrated top module.
// ALL stimulus is applied through the AXI4-Stream slave port (s_*) and ALL
// results are read back through the AXI4-Stream master port (m_*).
// No signal inside compute_core or the interface sub-module is accessed
// directly; the testbench only sees the external ports of top.sv.
//
// Kernel exercised:
//   BGR-to-grayscale + in-range threshold — the Phase-1 hot-path identified
//   in M1 profiling (cvtColor + inRange on 1920×1080 sign-language frames,
//   ~22 s / 10 passes at software baseline, ~40 fps target).
//
// AXI4-Stream framing:
//   s_tdata[23:0] = {B[7:0], G[7:0], R[7:0]}
//   s_tuser[15:0] = {hi_thresh[7:0], lo_thresh[7:0]}
//   m_tdata[8:0]  = {mask_out, gray_out[7:0]}
//
// Pipeline latency (top.sv): 2 clock cycles from accepted input to m_tvalid.
//   Clock edge N  : Stage 1 captures pixel (compute_core)
//   Clock edge N+1: Stage 2 fires → core_valid_out=1
//   Clock edge N+2: Interface output register → m_tvalid=1, m_tdata valid
//
// Reference values — independent BT.601 hand calculation (NOT from a prior DUT run):
//   gray = (R*77 + G*150 + B*29) >> 8
//   mask = 1 iff lo_thresh ≤ gray ≤ hi_thresh
//
// vec  B    G    R    R×77  G×150  B×29   sum    gray  lo   hi  mask
//  0:   0    0    0       0      0     0      0      0    0  255    1
//  1:   0    0  255   19635      0     0  19635     76    0  255    1
//  2:   0  255    0       0  38250     0  38250    149    0  255    1
//  3: 255    0    0       0      0  7395   7395     28    0  255    1
//  4: 255  255  255   19635  38250  7395  65280    255    0  255    1
//  5: 100  150  200   15400  22500  2900  40800    159  100  200    1
//  6:  10   30   20    1540   4500   290   6330     24  100  200    0
//  7: 128  128  128    9856  19200  3712  32768    128  100  200    1
//
// Pass criterion: final line contains "PASS".
// Compile:
//   iverilog -g2012 -DDUMP_VCD -o sim/sim_top.out tb/tb_top.sv
//       rtl/top.sv rtl/interface.sv ../m2/rtl/compute_core.sv
// Simulate:
//   cd sim && vvp sim_top.out | tee cosim_run.log
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_top;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam CLK_HALF = 5;       // 10 ns period (100 MHz)
    localparam NUM_VEC  = 8;       // number of reference pixels
    localparam PIPE_LAT = 2;       // pipeline depth: input → m_tvalid (clock edges)

    // -------------------------------------------------------------------------
    // DUT port signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst;

    logic        s_tvalid;
    wire         s_tready;         // driven by DUT (backpressure)
    logic [23:0] s_tdata;
    logic [15:0] s_tuser;
    logic        s_tlast;

    wire         m_tvalid;         // driven by DUT
    logic        m_tready;
    wire  [8:0]  m_tdata;          // [8]=mask [7:0]=gray, driven by DUT
    wire         m_tlast;          // driven by DUT

    // -------------------------------------------------------------------------
    // DUT — only external top-level AXI4-Stream ports are connected here.
    //   compute_core and interface internals are NOT accessed by this testbench.
    // -------------------------------------------------------------------------
    top dut (
        .clk      (clk),
        .rst      (rst),
        .s_tvalid (s_tvalid),
        .s_tready (s_tready),
        .s_tdata  (s_tdata),
        .s_tuser  (s_tuser),
        .s_tlast  (s_tlast),
        .m_tvalid (m_tvalid),
        .m_tready (m_tready),
        .m_tdata  (m_tdata),
        .m_tlast  (m_tlast)
    );

    // -------------------------------------------------------------------------
    // Clock generator — 10 ns period (100 MHz for simulation)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always  #CLK_HALF clk = ~clk;

    // =========================================================================
    // Reference vectors — all values derived independently by hand calculation.
    // =========================================================================
    logic [7:0] tv_b    [0:NUM_VEC-1];
    logic [7:0] tv_g    [0:NUM_VEC-1];
    logic [7:0] tv_r    [0:NUM_VEC-1];
    logic [7:0] tv_lo   [0:NUM_VEC-1];
    logic [7:0] tv_hi   [0:NUM_VEC-1];
    logic [7:0] exp_gray[0:NUM_VEC-1];
    logic       exp_mask[0:NUM_VEC-1];

    integer i, out_idx, fail_count;
    logic   last_tlast_seen;   // captured m_tlast when the last result appeared

    // =========================================================================
    // Stimulus and checker
    // =========================================================================
    initial begin
`ifdef DUMP_VCD
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
`endif

        // ------ independent BT.601 reference table ------
        tv_b[0]=  0; tv_g[0]=  0; tv_r[0]=  0; tv_lo[0]=  0; tv_hi[0]=255; exp_gray[0]=  0; exp_mask[0]=1'b1;
        tv_b[1]=  0; tv_g[1]=  0; tv_r[1]=255; tv_lo[1]=  0; tv_hi[1]=255; exp_gray[1]= 76; exp_mask[1]=1'b1;
        tv_b[2]=  0; tv_g[2]=255; tv_r[2]=  0; tv_lo[2]=  0; tv_hi[2]=255; exp_gray[2]=149; exp_mask[2]=1'b1;
        tv_b[3]=255; tv_g[3]=  0; tv_r[3]=  0; tv_lo[3]=  0; tv_hi[3]=255; exp_gray[3]= 28; exp_mask[3]=1'b1;
        tv_b[4]=255; tv_g[4]=255; tv_r[4]=255; tv_lo[4]=  0; tv_hi[4]=255; exp_gray[4]=255; exp_mask[4]=1'b1;
        tv_b[5]=100; tv_g[5]=150; tv_r[5]=200; tv_lo[5]=100; tv_hi[5]=200; exp_gray[5]=159; exp_mask[5]=1'b1;
        tv_b[6]= 10; tv_g[6]= 30; tv_r[6]= 20; tv_lo[6]=100; tv_hi[6]=200; exp_gray[6]= 24; exp_mask[6]=1'b0;
        tv_b[7]=128; tv_g[7]=128; tv_r[7]=128; tv_lo[7]=100; tv_hi[7]=200; exp_gray[7]=128; exp_mask[7]=1'b1;

        // ------ initialise inputs ------
        rst      = 1'b1;
        s_tvalid = 1'b0;
        s_tdata  = 24'd0;
        s_tuser  = 16'd0;
        s_tlast  = 1'b0;
        m_tready = 1'b1;    // eager downstream consumer — always ready
        fail_count      = 0;
        out_idx         = 0;
        last_tlast_seen = 1'b0;

        $display("=============================================================");
        $display("  tb_top : M3 end-to-end co-simulation (AXI4-Stream path)   ");
        $display("=============================================================");
        $display("  DUT    : project/m3/rtl/top.sv");
        $display("  Path   : host -[slave AXI4-Stream]-> interface -> compute_core");
        $display("                -> interface -[master AXI4-Stream]-> host");
        $display("  Kernel : BGR-to-gray + in-range threshold (BT.601 x256)");
        $display("  Pixels : %0d representative 1920x1080 sign-language vectors", NUM_VEC);
        $display("-------------------------------------------------------------");
        $display("vec |  B   G   R  | gray | exp  | mask | exp  | chk");
        $display("----|-------------|------|------|------|------|-----");

        // ------ 2-cycle synchronous reset ------
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 1'b0;

        // ------ main test loop ------
        // Drive NUM_VEC pixels through the AXI4-Stream slave port, then
        // flush PIPE_LAT additional cycles to drain the last outputs.
        // With m_tready=1 always, s_tready=1 always (no backpressure), so
        // core_valid_in = s_tvalid on every cycle.
        // Output for vector[k] appears at iteration k + PIPE_LAT.
        for (i = 0; i < NUM_VEC + PIPE_LAT; i++) begin

            if (i < NUM_VEC) begin
                s_tvalid = 1'b1;
                s_tlast  = (i == NUM_VEC - 1) ? 1'b1 : 1'b0;
                s_tdata  = {tv_b[i], tv_g[i], tv_r[i]};
                s_tuser  = {tv_hi[i], tv_lo[i]};
            end else begin
                s_tvalid = 1'b0;
                s_tlast  = 1'b0;
            end

            @(posedge clk); #1;

            // Verify s_tready stayed high while we were sending (no unexpected stall).
            if (i < NUM_VEC && !s_tready) begin
                $display("FAIL: s_tready de-asserted at i=%0d (unexpected backpressure)", i);
                fail_count = fail_count + 1;
            end

            // Capture output on every cycle m_tvalid asserts.
            if (m_tvalid) begin
                if (m_tdata[7:0] === exp_gray[out_idx] &&
                    m_tdata[8]   === exp_mask[out_idx]) begin
                    $display(" %2d | %3d %3d %3d | %3d  | %3d  |  %0b   |  %0b   |  OK",
                        out_idx,
                        tv_b[out_idx], tv_g[out_idx], tv_r[out_idx],
                        m_tdata[7:0], exp_gray[out_idx],
                        m_tdata[8],   exp_mask[out_idx]);
                end else begin
                    $display(" %2d | %3d %3d %3d | %3d  | %3d  |  %0b   |  %0b   |  FAIL <<<",
                        out_idx,
                        tv_b[out_idx], tv_g[out_idx], tv_r[out_idx],
                        m_tdata[7:0], exp_gray[out_idx],
                        m_tdata[8],   exp_mask[out_idx]);
                    fail_count = fail_count + 1;
                end
                // Capture m_tlast when the last vector's result appears.
                if (out_idx == NUM_VEC - 1)
                    last_tlast_seen = m_tlast;

                out_idx = out_idx + 1;
            end
        end

        // ------ verify all outputs were received ------
        if (out_idx !== NUM_VEC) begin
            $display("ERROR: expected %0d outputs, received %0d", NUM_VEC, out_idx);
            fail_count = fail_count + 1;
        end

        // ------ verify m_tlast was 1 when the last result appeared ------
        // AXI4-Stream does not require TLAST to self-clear when TVALID goes low,
        // so we check it was asserted at the moment of the last valid transfer.
        if (last_tlast_seen !== 1'b1) begin
            $display("FAIL: m_tlast was not asserted with the last output (got %0b)", last_tlast_seen);
            fail_count = fail_count + 1;
        end else begin
            $display("  -- | m_tlast asserted with last result                    |  OK");
        end

        // ------ verify synchronous reset clears m_tvalid ------
        rst = 1'b1;
        @(posedge clk); #1;
        if (m_tvalid !== 1'b0) begin
            $display("FAIL: reset check — m_tvalid not cleared (got %0b)", m_tvalid);
            fail_count = fail_count + 1;
        end else begin
            $display("  -- | reset: m_tvalid cleared after rst=1                  |  OK");
        end
        rst = 1'b0;

        // ------ final verdict ------
        $display("=============================================================");
        if (fail_count == 0)
            $display("PASS -- all end-to-end checks passed");
        else
            $display("FAIL -- %0d check(s) did not match", fail_count);
        $display("=============================================================");

        $finish;
    end

endmodule

`default_nettype wire
