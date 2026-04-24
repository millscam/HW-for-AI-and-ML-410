`timescale 1ns/1ps
`default_nettype none

module mac (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg  signed [31:0] out
);

    wire signed [15:0] product;
    assign product = a * b;

    always @(posedge clk) begin
        if (rst)
            out <= 32'sd0;
        else
            out <= out + {{16{product[15]}}, product};
    end

endmodule

`default_nettype wire
