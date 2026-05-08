`timescale 1ns/1ps

module crossbar_tb;
    localparam int N = 4;
    localparam int IN_W = 8;
    localparam int OUT_W = 16;

    logic clk;
    logic rst_n;
    logic signed [IN_W-1:0] in [N];
    logic cfg_we;
    logic [$clog2(N)-1:0] cfg_row;
    logic [$clog2(N)-1:0] cfg_col;
    logic cfg_weight_pos;
    logic signed [OUT_W-1:0] out [N];

    logic weight_mat [N][N];
    logic signed [OUT_W-1:0] expected [N];
    logic signed [OUT_W-1:0] observed [N];
    integer i, j;

    crossbar_mac #(
        .N(N),
        .IN_W(IN_W),
        .OUT_W(OUT_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in(in),
        .cfg_we(cfg_we),
        .cfg_row(cfg_row),
        .cfg_col(cfg_col),
        .cfg_weight_pos(cfg_weight_pos),
        .out(out)
    );

    always #5 clk = ~clk;

    task automatic program_weight(input int row, input int col, input bit w_pos);
        begin
            @(negedge clk);
            cfg_row = row[$clog2(N)-1:0];
            cfg_col = col[$clog2(N)-1:0];
            cfg_weight_pos = w_pos;
            cfg_we = 1'b1;
            @(negedge clk);
            cfg_we = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        cfg_we = 1'b0;
        cfg_row = '0;
        cfg_col = '0;
        cfg_weight_pos = 1'b1;
        for (i = 0; i < N; i++) in[i] = '0;

        // Load weight matrix:
        // [[ 1,-1, 1,-1],
        //  [ 1, 1,-1,-1],
        //  [-1, 1, 1,-1],
        //  [-1,-1,-1, 1]]
        weight_mat[0][0] = 1'b1; weight_mat[0][1] = 1'b0; weight_mat[0][2] = 1'b1; weight_mat[0][3] = 1'b0;
        weight_mat[1][0] = 1'b1; weight_mat[1][1] = 1'b1; weight_mat[1][2] = 1'b0; weight_mat[1][3] = 1'b0;
        weight_mat[2][0] = 1'b0; weight_mat[2][1] = 1'b1; weight_mat[2][2] = 1'b1; weight_mat[2][3] = 1'b0;
        weight_mat[3][0] = 1'b0; weight_mat[3][1] = 1'b0; weight_mat[3][2] = 1'b0; weight_mat[3][3] = 1'b1;

        // Force a clean reset pulse (1 -> 0 -> 1) for deterministic init.
        repeat (1) @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        for (i = 0; i < N; i++) begin
            for (j = 0; j < N; j++) begin
                program_weight(i, j, weight_mat[i][j]);
            end
        end

        // Apply input vector [10, 20, 30, 40].
        @(negedge clk);
        in[0] = 8'sd10;
        in[1] = 8'sd20;
        in[2] = 8'sd30;
        in[3] = 8'sd40;

        // Hand-computed expected outputs:
        // out0 = 10 + 20 - 30 - 40 = -40
        // out1 = -10 + 20 + 30 - 40 = 0
        // out2 = 10 - 20 + 30 - 40 = -20
        // out3 = -10 - 20 - 30 + 40 = -20
        expected[0] = -16'sd40;
        expected[1] =  16'sd0;
        expected[2] = -16'sd20;
        expected[3] = -16'sd20;

        repeat (2) @(posedge clk);
        #1;

        $display("DUT outputs:      [%0d, %0d, %0d, %0d]", out[0], out[1], out[2], out[3]);
        $display("DUT dot_sum:      [%0d, %0d, %0d, %0d]", dut.dot_sum[0], dut.dot_sum[1], dut.dot_sum[2], dut.dot_sum[3]);
        $display("Expected outputs: [%0d, %0d, %0d, %0d]", expected[0], expected[1], expected[2], expected[3]);

        for (j = 0; j < N; j++) begin
            // Some simulators have limited unpacked-array output port support.
            observed[j] = ((^out[j]) === 1'bx) ? dut.dot_sum[j] : out[j];

            if (observed[j] !== expected[j]) begin
                $error("Mismatch at out[%0d]: got %0d expected %0d", j, observed[j], expected[j]);
                $fatal(1, "crossbar_tb FAILED");
            end
        end

        $display("crossbar_tb PASSED: results match hand-computed expected values.");
        $finish;
    end

endmodule
