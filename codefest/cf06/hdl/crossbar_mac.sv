module crossbar_mac #(
    parameter int N = 4,
    parameter int IN_W = 8,
    parameter int OUT_W = 16
) (
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic signed [IN_W-1:0]            in [N],
    input  logic                              cfg_we,
    input  logic [$clog2(N)-1:0]              cfg_row,
    input  logic [$clog2(N)-1:0]              cfg_col,
    input  logic                              cfg_weight_pos,
    output logic signed [OUT_W-1:0]           out [N]
);

    // Weight storage: 1'b1 => +1, 1'b0 => -1.
    logic weight_pos [N][N];
    logic signed [OUT_W-1:0] dot_sum [N];
    integer i, j;

    // Synchronous weight update and output register update.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i++) begin
                out[i] <= '0;
                for (j = 0; j < N; j++) begin
                    weight_pos[i][j] <= 1'b1;
                end
            end
        end else begin
            if (cfg_we) begin
                weight_pos[cfg_row][cfg_col] <= cfg_weight_pos;
            end

            for (j = 0; j < N; j++) begin
                out[j] <= dot_sum[j];
            end
        end
    end

    // Combinational dot-product across rows for each output column.
    always_comb begin
        for (j = 0; j < N; j++) begin
            dot_sum[j] = '0;
            for (i = 0; i < N; i++) begin
                if (weight_pos[i][j]) begin
                    dot_sum[j] += $signed(in[i]);
                end else begin
                    dot_sum[j] -= $signed(in[i]);
                end
            end
        end
    end

endmodule
