// =============================================================================
// Module      : top  (M3 integrated top)
// File        : project/m3/rtl/top.sv
// Project     : Sign-Language Gesture Recognition Accelerator (M3)
//
// Description :
//   Integration wrapper that connects the AXI4-Stream interface module to the
//   BGR-to-grayscale compute core, forming the complete accelerator datapath.
//   This module satisfies the M3 requirement that the interface and compute
//   core are instantiated as peer sub-modules with explicitly named
//   inter-module connections.
//
//   Sub-module hierarchy:
//     top
//     ├── u_if   : \interface  (project/m3/rtl/interface.sv)
//     │              AXI4-Stream slave/master wrapper + backpressure control
//     └── u_core : compute_core (project/m2/rtl/compute_core.sv)
//                    2-stage BGR→grayscale + in-range threshold pipeline
//
//   Data flow:
//     Host (PCIe DMA) ──[AXI4-Stream slave]──► u_if ──[core_*]──► u_core
//                                                                       │
//     Host (PCIe DMA) ◄─[AXI4-Stream master]── u_if ◄─[core_*]────────┘
//
//   Glue logic between interface and compute core:
//     None required.  The interface module drives core_valid_in as the
//     combinational AND of s_tvalid && s_tready (the AXI4-Stream acceptance
//     condition).  The compute core's 2-cycle output latency is accounted for
//     inside the interface by the 2-register TLAST delay pipeline and the
//     output holding register.  Clock and reset are shared across both modules
//     (single clock domain, synchronous active-high reset).
//
// Clock domain : single clock (clk), rising-edge triggered
// Reset        : synchronous, active-high (rst)
//
// Port table:
//   Name         Dir   Width  Description
//   -----------  ----  -----  --------------------------------------------------
//   clk           in     1    System clock (all FFs on this single domain)
//   rst           in     1    Synchronous active-high reset
//   s_tvalid      in     1    Slave AXI4-Stream valid strobe
//   s_tready      out    1    Slave AXI4-Stream ready / backpressure
//   s_tdata       in    24    BGR pixel: bits[23:16]=B [15:8]=G [7:0]=R
//   s_tuser       in    16    Thresholds: bits[15:8]=hi_thresh [7:0]=lo_thresh
//   s_tlast       in     1    End-of-frame marker from host
//   m_tvalid      out    1    Master AXI4-Stream valid (held until m_tready)
//   m_tready      in     1    Master AXI4-Stream ready (from downstream consumer)
//   m_tdata       out    9    Result pixel: bit[8]=mask_out bits[7:0]=gray_out
//   m_tlast       out    1    End-of-frame (2-cycle delayed from s_tlast)
// =============================================================================

`default_nettype none

module top (
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
    // Inter-module signals: \interface  <──────────────────►  compute_core
    // These nets are the only path between the AXI4-Stream wrapper and the
    // compute engine.  Named here at the top level so the integration boundary
    // is explicit and traceable in waveforms.
    // =========================================================================
    wire        core_valid_in;    // interface → core: pixel accepted this cycle
    wire [7:0]  core_b_in;        // interface → core: blue  channel (bits[23:16])
    wire [7:0]  core_g_in;        // interface → core: green channel (bits[15:8])
    wire [7:0]  core_r_in;        // interface → core: red   channel (bits[7:0])
    wire [7:0]  core_lo_thresh;   // interface → core: lower threshold (TUSER[7:0])
    wire [7:0]  core_hi_thresh;   // interface → core: upper threshold (TUSER[15:8])
    wire        core_valid_out;   // core → interface: result is valid this cycle
    wire [7:0]  core_gray_out;    // core → interface: grayscale luminance
    wire        core_mask_out;    // core → interface: in-range mask bit

    // =========================================================================
    // u_if — AXI4-Stream protocol wrapper and backpressure controller
    // Accepts BGR pixels from the host via the slave AXI4-Stream port, drives
    // the compute core on each accepted transfer, and returns results to the
    // host via the master AXI4-Stream port.
    // =========================================================================
    \interface  u_if (
        .clk            (clk),
        .rst            (rst),

        .s_tvalid       (s_tvalid),
        .s_tready       (s_tready),
        .s_tdata        (s_tdata),
        .s_tuser        (s_tuser),
        .s_tlast        (s_tlast),

        .m_tvalid       (m_tvalid),
        .m_tready       (m_tready),
        .m_tdata        (m_tdata),
        .m_tlast        (m_tlast),

        .core_valid_in  (core_valid_in),
        .core_b_in      (core_b_in),
        .core_g_in      (core_g_in),
        .core_r_in      (core_r_in),
        .core_lo_thresh (core_lo_thresh),
        .core_hi_thresh (core_hi_thresh),
        .core_valid_out (core_valid_out),
        .core_gray_out  (core_gray_out),
        .core_mask_out  (core_mask_out)
    );

    // =========================================================================
    // u_core — BGR-to-grayscale + in-range threshold compute engine (M2)
    // 2-stage pipeline: Stage 1 parallel multiplies R×77, G×150, B×29;
    // Stage 2 accumulates the partial products, shifts right by 8, and
    // compares against the threshold window.  One pixel output per clock cycle,
    // 2-cycle latency from valid_in to valid_out.
    // =========================================================================
    compute_core u_core (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (core_valid_in),
        .b_in      (core_b_in),
        .g_in      (core_g_in),
        .r_in      (core_r_in),
        .lo_thresh (core_lo_thresh),
        .hi_thresh (core_hi_thresh),
        .valid_out (core_valid_out),
        .gray_out  (core_gray_out),
        .mask_out  (core_mask_out)
    );

endmodule

`default_nettype wire
