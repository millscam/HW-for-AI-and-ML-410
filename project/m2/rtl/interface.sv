// =============================================================================
// Module      : \interface
// File        : project/m2/rtl/interface.sv
// Project     : Sign-Language Gesture Recognition Accelerator (M2)
//
// Protocol    : AXI4-Stream (ARM IHI0051B, revision B)
//               This module is the internal streaming interface that sits
//               between the PCIe DMA engine (M1 host-facing link) and the
//               compute_core processing element array.  The host pushes BGR
//               frame tiles over PCIe; the on-chip DMA engine presents them
//               as an AXI4-Stream to this module, which drives compute_core
//               and returns results as an AXI4-Stream to the DMA read path.
//               Reference: M1 interface_selection.md §1 (PCIe selected) and
//               §4/§5 (AXI4-Stream for internal DMA ↔ accelerator datapath).
//
// Clock domain : single clock (clk), rising-edge triggered
// Reset        : synchronous, active-high (rst)
//
// ─── Transaction format ──────────────────────────────────────────────────────
//  Slave  (input, from PCIe DMA write channel):
//    TDATA  [23:0]  Packed BGR pixel:  bits[23:16]=B  bits[15:8]=G  bits[7:0]=R
//    TUSER  [15:0]  Threshold params:  bits[15:8]=hi_thresh  bits[7:0]=lo_thresh
//    TVALID   [0]  1 = TDATA/TUSER are valid and stable
//    TREADY   [0]  1 = this module can accept the transfer (driven by this module)
//    TLAST    [0]  1 = last pixel of a frame (end-of-frame marker)
//
//  Master (output, to PCIe DMA read channel):
//    TDATA   [8:0]  Result pixel:  bit[8]=mask_out  bits[7:0]=gray_out
//    TVALID   [0]  1 = TDATA is valid and stable; held until TREADY asserted
//    TREADY   [0]  1 = downstream consumer can accept (driven by downstream)
//    TLAST    [0]  1 = last result of a frame (propagated from slave TLAST,
//                      delayed by 2 cycles to match pipeline latency)
//
// ─── AXI4-Stream contract honored ────────────────────────────────────────────
//  • Master TVALID is registered and held stable until TREADY is asserted.
//  • Slave TREADY is deasserted (backpressure) when the output register is
//    occupied and the downstream has not yet accepted the transfer, preventing
//    new pixels from entering compute_core when results cannot be drained.
//  • A transfer occurs on any clock edge where both TVALID and TREADY are high.
//  Note: the compute_core pipeline is 2 cycles deep and non-stallable.
//  At most 2 in-flight pixels may already be committed when backpressure first
//  asserts; the output register absorbs one; the other may be lost if the
//  consumer is absent for 3+ consecutive cycles (rare in a DMA-driven system).
//
// ─── Port table ──────────────────────────────────────────────────────────────
//   Name         Dir   Width  Description
//   -----------  ----  -----  -------------------------------------------------
//   clk           in     1    System clock
//   rst           in     1    Synchronous active-high reset
//   s_tvalid      in     1    Slave valid strobe
//   s_tready      out    1    Slave ready (backpressure output)
//   s_tdata       in    24    BGR pixel: [23:16]=B [15:8]=G [7:0]=R
//   s_tuser       in    16    Thresholds: [15:8]=hi [7:0]=lo
//   s_tlast       in     1    End-of-frame marker from host
//   m_tvalid      out    1    Master valid (held until m_tready)
//   m_tready      in     1    Master ready (from downstream consumer)
//   m_tdata       out    9    Result: [8]=mask [7:0]=gray
//   m_tlast       out    1    End-of-frame (2-cycle delayed from s_tlast)
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
    output logic       m_tlast
);

    // =========================================================================
    // Backpressure: accept slave input only when the output register can
    // receive the result that will emerge 2 cycles later.
    // s_tready = 1 when output register is empty OR downstream is consuming.
    // =========================================================================
    assign s_tready = !m_tvalid || m_tready;

    // =========================================================================
    // Compute core interface signals
    // =========================================================================
    wire valid_in_core;
    assign valid_in_core = s_tvalid && s_tready;

    wire        core_valid_out;
    wire [7:0]  core_gray_out;
    wire        core_mask_out;

    // =========================================================================
    // TLAST delay pipeline — 2 registers to match compute_core latency.
    // TLAST is only propagated for cycles where a valid pixel was accepted.
    // =========================================================================
    logic [1:0] tlast_pipe;

    always_ff @(posedge clk) begin
        if (rst) begin
            tlast_pipe <= 2'b00;
        end else begin
            tlast_pipe[0] <= s_tlast && valid_in_core;
            tlast_pipe[1] <= tlast_pipe[0];
        end
    end

    // =========================================================================
    // Compute core instantiation
    // =========================================================================
    compute_core u_core (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (valid_in_core),
        .b_in      (s_tdata[23:16]),
        .g_in      (s_tdata[15:8]),
        .r_in      (s_tdata[7:0]),
        .lo_thresh (s_tuser[7:0]),
        .hi_thresh (s_tuser[15:8]),
        .valid_out (core_valid_out),
        .gray_out  (core_gray_out),
        .mask_out  (core_mask_out)
    );

    // =========================================================================
    // Output register — holds result stable until downstream accepts.
    // Loaded when core produces a valid output AND register is free (or being
    // drained). Cleared when downstream accepts without a simultaneous new
    // result from core.
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
