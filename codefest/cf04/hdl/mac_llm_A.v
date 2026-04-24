module mac (
    input  logic        clk,
    input  logic        rst,
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    output logic signed [31:0] out
);
    // Explicit 16-bit product captures full range of 8×8 signed multiply
    // without relying on context-determined sign extension.
    logic signed [15:0] product;
    assign product = a * b;

    always_ff @(posedge clk) begin
        if (rst)
            out <= 32'sd0;
        else
            out <= out + {{16{product[15]}}, product};
    end

endmodule
