// =============================================================================
// Module      : \interface  (M3 — compute-core ports exposed)
// File        : project/m3/rtl/interface.sv
// Project     : Sign-Language Gesture Recognition Accelerator (M3)
//
// This is a refactored version of project/m2/rtl/interface.sv.
// The only structural change: the internal compute_core instantiation has been
// removed and the core-facing signals are now explicit ports.  This allows
// top.sv to instantiate \interface and compute_core as peer sub-modules with
// named inter-module connections, satisfying the M3 integration requirement.
// All AXI4-Stream backpressure, handshake, and output-register logic is
// identical to the M2 version.
//
// Protocol    : AXI4-Stream (ARM IHI0051B, revision B)
//
// Clock domain : single clock (clk), rising-edge triggered
// Reset        : synchronous, active-high (rst)
//
// ─── Port table ──────────────────────────────────────────────────────────────
//   Name            Dir   Width  Description
//   --------------  ----  -----  -----------------------------------------------
//   clk              in     1    System clock
//   rst              in     1    Synchronous active-high reset
//   — AXI4-Stream slave (from PCIe DMA write channel) —
//   s_tvalid         in     1    Slave valid strobe
//   s_tready         out    1    Slave ready / backpressure
//   s_tdata          in    24    BGR pixel: [23:16]=B [15:8]=G [7:0]=R
//   s_tuser          in    16    Thresholds: [15:8]=hi [7:0]=lo
//   s_tlast          in     1    End-of-frame marker from host
//   — AXI4-Stream master (to PCIe DMA read channel) —
//   m_tvalid         out    1    Master valid (held until m_tready)
//   m_tready         in     1    Master ready (from downstream consumer)
//   m_tdata          out    9    Result: [8]=mask [7:0]=gray
//   m_tlast          out    1    End-of-frame (2-cycle delayed from s_tlast)
//   — Compute-core facing (wired by top.sv to compute_core) —
//   core_valid_in    out    1    Pixel valid strobe → compute_core.valid_in
//   core_b_in        out    8    Blue  channel      → compute_core.b_in
//   core_g_in        out    8    Green channel      → compute_core.g_in
//   core_r_in        out    8    Red   channel      → compute_core.r_in
//   core_lo_thresh   out    8    Lower threshold    → compute_core.lo_thresh
//   core_hi_thresh   out    8    Upper threshold    → compute_core.hi_thresh
//   core_valid_out   in     1    Result valid       ← compute_core.valid_out
//   core_gray_out    in     8    Grayscale result   ← compute_core.gray_out
//   core_mask_out    in     1    Mask result        ← compute_core.mask_out
// =============================================================================

`default_nettype none

module \interface (
    input  wire        clk,
    input  wire        rst,

    // ── Slave AXI4-Stream (from PCIe DMA write channel) ──
    input  wire        s_tvalid,
    output wire        s_tready,
    input  wire [23:0] s_tdata,
    input  wire [15:0] s_tuser,
    input  wire        s_tlast,

    // ── Master AXI4-Stream (to PCIe DMA read channel) ──
    output logic       m_tvalid,
    input  wire        m_tready,
    output logic [8:0] m_tdata,
    output logic       m_tlast,

    // ── Compute-core facing ports (peer-connected in top.sv) ──
    output wire        core_valid_in,
    output wire [7:0]  core_b_in,
    output wire [7:0]  core_g_in,
    output wire [7:0]  core_r_in,
    output wire [7:0]  core_lo_thresh,
    output wire [7:0]  core_hi_thresh,
    input  wire        core_valid_out,
    input  wire [7:0]  core_gray_out,
    input  wire        core_mask_out
);

    // =========================================================================
    // Backpressure: accept slave input only when the output register can
    // receive the result that will emerge 2 cycles later.
    // s_tready = 1 when output register is empty OR downstream is consuming.
    // =========================================================================
    assign s_tready = !m_tvalid || m_tready;

    // =========================================================================
    // Compute-core control signals — driven combinationally from slave port.
    // A transfer into the core happens whenever slave valid and ready are both
    // asserted simultaneously.
    // =========================================================================
    assign core_valid_in  = s_tvalid && s_tready;
    assign core_b_in      = s_tdata[23:16];
    assign core_g_in      = s_tdata[15:8];
    assign core_r_in      = s_tdata[7:0];
    assign core_lo_thresh = s_tuser[7:0];
    assign core_hi_thresh = s_tuser[15:8];

    // =========================================================================
    // TLAST delay pipeline — 2 registers to match compute_core 2-cycle latency.
    // Propagated only for cycles where a valid pixel was accepted.
    // =========================================================================
    logic [1:0] tlast_pipe;

    always_ff @(posedge clk) begin
        if (rst) begin
            tlast_pipe <= 2'b00;
        end else begin
            tlast_pipe[0] <= s_tlast && core_valid_in;
            tlast_pipe[1] <= tlast_pipe[0];
        end
    end

    // =========================================================================
    // Output register — holds result stable until downstream accepts.
    // Loaded when core produces a valid output AND register is free (or being
    // drained). Cleared when downstream accepts without a simultaneous new
    // result from the core.
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            m_tvalid <= 1'b0;
            m_tdata  <= 9'd0;
            m_tlast  <= 1'b0;
        end else if (core_valid_out && (!m_tvalid || m_tready)) begin
            m_tvalid <= 1'b1;
            m_tdata  <= {core_mask_out, core_gray_out};
            m_tlast  <= tlast_pipe[1];
        end else if (m_tready) begin
            m_tvalid <= 1'b0;
        end
    end

endmodule

`default_nettype wire
