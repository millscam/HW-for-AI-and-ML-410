`timescale 1ns/1ps
module mac_tb;

    reg              clk;
    reg              rst;
    reg  signed [7:0] a;
    reg  signed [7:0] b;
    wire signed [31:0] out;

    mac dut (
        .clk (clk),
        .rst (rst),
        .a   (a),
        .b   (b),
        .out (out)
    );

    // 10 ns period clock
    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_n;

    initial begin
`ifdef DUMP_VCD
        $dumpfile("mac_tb.vcd");
        $dumpvars(0, mac_tb);
`endif
        $display("cycle | rst |  a  |  b  |   out");
        $display("------|-----|-----|-----|----------");

        // ------ cycle 0: initial synchronous reset ------
        cycle_n = 0;
        rst = 1; a = 0; b = 0;
        @(posedge clk); #1;
        $display("%5d |  %0b  | %3d | %3d | %0d",
                 cycle_n, rst, $signed(a), $signed(b), $signed(out));

        // ------ cycles 1-3: a=3, b=4 ------
        rst = 0; a = 3; b = 4;
        repeat (3) begin
            cycle_n = cycle_n + 1;
            @(posedge clk); #1;
            $display("%5d |  %0b  | %3d | %3d | %0d",
                     cycle_n, rst, $signed(a), $signed(b), $signed(out));
        end

        // ------ cycle 4: assert rst ------
        rst = 1;
        cycle_n = cycle_n + 1;
        @(posedge clk); #1;
        $display("%5d |  %0b  | %3d | %3d | %0d",
                 cycle_n, rst, $signed(a), $signed(b), $signed(out));

        // ------ cycles 5-6: a=-5, b=2 ------
        rst = 0; a = -5; b = 2;
        repeat (2) begin
            cycle_n = cycle_n + 1;
            @(posedge clk); #1;
            $display("%5d |  %0b  | %3d | %3d | %0d",
                     cycle_n, rst, $signed(a), $signed(b), $signed(out));
        end

        $display("--- simulation complete ---");
        $finish;
    end

endmodule
