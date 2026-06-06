// M4 representative workload: stream N pixel-pairs through synth_top (2 lanes).
// Cycle count extrapolated to full 1080p frame for bench/benchmark_data.csv.
`timescale 1ns/1ps
`default_nettype none

module tb_bench_synth_top;
    localparam int N_PAIRS = 512;
    localparam real CLK_HALF_NS = 6.5;  // 13 ns period = 76.9 MHz (M4 synthesis signoff)
    localparam int PIPE_LAT = 2;

    logic clk, rst, valid_in;
    logic [7:0] b0, g0, r0, b1, g1, r1, lo, hi;
    logic valid_out, mask0, mask1;
    logic [7:0] gray0, gray1;

    longint t0, t1, cycles;

    synth_top dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .b_in_0(b0), .g_in_0(g0), .r_in_0(r0),
        .b_in_1(b1), .g_in_1(g1), .r_in_1(r1),
        .lo_thresh(lo), .hi_thresh(hi),
        .valid_out(valid_out),
        .gray_out_0(gray0), .mask_out_0(mask0),
        .gray_out_1(gray1), .mask_out_1(mask1)
    );

    initial clk = 0;
    always #(CLK_HALF_NS) clk = ~clk;

    initial begin
        rst = 1; valid_in = 0;
        b0 = 0; g0 = 0; r0 = 0; b1 = 0; g1 = 0; r1 = 0;
        lo = 8'd0; hi = 8'd255;
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        t0 = $time;
        for (int i = 0; i < N_PAIRS; i++) begin
            @(posedge clk);
            valid_in = 1;
            b0 = 8'(i & 8'hFF);
            g0 = 8'((i >> 3) & 8'hFF);
            r0 = 8'((i >> 5) & 8'hFF);
            b1 = 8'(i + 1);
            g1 = 8'(i + 2);
            r1 = 8'(i + 3);
        end
        @(posedge clk);
        valid_in = 0;
        repeat (PIPE_LAT + 4) @(posedge clk);
        t1 = $time;
        cycles = (t1 - t0) / (2.0 * CLK_HALF_NS);

        $display("M4_BENCH N_PAIRS=%0d cycles=%0d", N_PAIRS, cycles);
        $display("M4_BENCH period_ns=%0d", 2 * CLK_HALF_NS);
        $finish;
    end
endmodule

`default_nettype wire
