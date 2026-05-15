// =============================================================================
// Module      : synth_top (synthesis top; RTL copied from project/m2 compute_core)
// Project     : Sign-Language Gesture Recognition Accelerator — CF07 OpenLane 2
// Source      : project/m2/rtl/compute_core.sv
//
// Description : Same fused BGR→gray + in-range threshold pixel engine as M2
//               compute_core; module renamed to match OpenLane DESIGN_NAME.
// =============================================================================

`default_nettype none

module synth_top (
    input  wire        clk,
    input  wire        rst,

    input  wire        valid_in,
    input  wire [7:0]  b_in,
    input  wire [7:0]  g_in,
    input  wire [7:0]  r_in,

    input  wire [7:0]  lo_thresh,
    input  wire [7:0]  hi_thresh,

    output logic       valid_out,
    output logic [7:0] gray_out,
    output logic       mask_out
);

    logic        s1_valid;
    logic [14:0] s1_r77;
    logic [15:0] s1_g150;
    logic [12:0] s1_b29;
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
            s1_r77   <= r_in * 8'd77;
            s1_g150  <= g_in * 8'd150;
            s1_b29   <= b_in * 8'd29;
            s1_lo    <= lo_thresh;
            s1_hi    <= hi_thresh;
        end
    end

    logic [15:0] s2_sum;
    assign s2_sum = ({1'b0, s1_r77} + s1_g150) + {3'b000, s1_b29};

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
