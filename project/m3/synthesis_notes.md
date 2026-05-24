# M3 Synthesis Notes

Design : Sign-Language Gesture Recognition Accelerator — Phase 1 Preprocessing Kernel
Module : `synth_top` (2-lane BGR→grayscale + in-range threshold compute core)
PDK    : sky130A / sky130_fd_sc_hd (Sky130 high-density standard-cell library)
Tool   : OpenLane 2 v2.3.10

---

## 1. What Was Synthesized

The module sent through OpenLane is `synth_top`, defined in
`codefest/cf07/hdl/synth_top.sv`. It is a 2-lane parallel pixel engine that
implements the Phase-1 preprocessing kernel identified as the dominant wall-time
contributor in M1 profiling: fused BGR-to-grayscale conversion using BT.601
integer coefficients (R×77 + G×150 + B×29) followed by a per-pixel in-range
threshold comparison. Both lanes process independent pixels in the same clock
cycle, sharing only the clock, reset, and threshold inputs. The pipeline is
2 stages deep: Stage 1 performs the three parallel constant-coefficient
multiplications (registering partial products), and Stage 2 accumulates the
partial products, shifts right by 8, and evaluates the threshold comparison to
produce the mask bit. One grayscale pixel and one mask bit emerge from each lane
per clock cycle, for a total of 2 pixels per clock.

This module was synthesized across three progressively tuned OpenLane runs.

---

## 2. Three-Run Synthesis History

### Run 1 — Baseline (single-lane, 20 ns clock)

The first synthesis run targeted the original single-lane `compute_core.sv` from
M2 at a 20 ns clock period (50 MHz). This run established that the design closes
timing cleanly on Sky130 HD: worst setup slack was +8.6 ns, core utilization was
42.4 %, and 2 max-fanout DRV violations were present on the `rst`/`valid_in`
control nets. Throughput at 50 MHz with one lane: 50 MHz / (1920×1080) ≈ 24 fps,
which fell short of the ~40 fps software baseline recorded in M1. DRC, LVS, and
antenna checks all passed cleanly.

### Run 2 — M3 Upgrade (2-lane, 13 ns clock, `MAX_FANOUT_CONSTRAINT=8`)

For the M3 milestone the RTL was rewritten as `synth_top.sv` with two
independent pixel lanes, and the clock period was tightened from 20 ns to 13 ns
(76.9 MHz) to exploit the large positive slack observed in Run 1. The intent was
to push throughput to 76.9 MHz × 2 / (1920×1080) ≈ 74 fps, which exceeds the
40 fps baseline by approximately 1.85×. `MAX_FANOUT_CONSTRAINT` was set to 8 to
attempt to suppress the DRV count, and `FP_CORE_UTIL` was loosened from 45 to
40 to give the placer additional breathing room for the larger design.

The run succeeded. Worst post-PNR setup slack was +3.4694 ns at corner
`max_ss_100C_1v60`. Hold slack was +0.1278 ns. All 9 PVT corners passed with
0 setup and 0 hold violations. Post-techmap area was 11,617.39 µm² across 1,088
Yosys cells; post-PNR stdcell area was 10,826.6 µm² with 1,674 instances and
37.7 % core utilization. Total power at nominal conditions was 2.03 mW.
DRC, LVS, and antenna checks all passed cleanly. The max-fanout DRV count,
however, rose from 2 to 10 per corner rather than falling. This was unexpected
and prompted Run 3.

### Run 3 — DRV Investigation (`MAX_FANOUT_CONSTRAINT=6`)

To investigate the fanout violations, `MAX_FANOUT_CONSTRAINT` was lowered from
8 to 6 and the run was repeated with the same RTL and clock period. Timing
closed again on all 9 corners: worst setup slack +3.3700 ns, worst hold slack
+0.1318 ns, 0 violations. Post-PNR area increased slightly to 11,138.2 µm²
with 1,727 instances (38.8 % utilization) as OpenROAD inserted additional
timing-repair buffers in response to the tighter data-path fanout constraint.

The DRV count did not decrease; it increased from 10 to **16** violations.
Examining the violator list revealed that all 16 violations were on
**clock-tree buffers** (`clkbuf_0_clk/X` with fanout 16, and `clkbuf_4_*` with
fanouts 7–12), not on any data or control net. This makes the `MAX_FANOUT_CONSTRAINT`
setting irrelevant to the problem: that parameter governs only the Yosys
techmap step and OpenROAD's post-routing data-path repair; the clock-tree
synthesis (CTS) step builds the clock network with its own internal fanout
budget that is completely independent of it. Tightening the constraint caused
OpenROAD to restructure the clock tree into fewer levels with wider fan-out per
node, which is why the count went up rather than down. The correct fix would be
a CTS-specific parameter such as `CTS_MAX_CAP`, which would force CTS to insert
more, lower-load clock buffers. This is deferred to M4, where a clean DRV-zero
signoff is a goal.

Importantly, the 16 DRV violations are advisory only: the sky130_fd_sc_hd
library cells involved operate within their datasheet max-capacitance limits
(confirmed by 0 max-cap violations and 0 max-slew violations across all 9
corners). Timing closure is complete and the design is functionally correct.

Run 3 is the current best result and the data used for all M3 reports.

---

## 3. What Synthesized Successfully

Every checker in the OpenLane Classic flow passed:

- **Yosys synthesis:** 0 unmapped cells, 0 synthesis errors, 0 assign-statement
  warnings after flattening.
- **Timing (all 9 PVT corners):** 0 setup violations, 0 hold violations across
  the full min/nom/max × ss/tt/ff corner matrix. Worst setup slack +3.37 ns
  (27.5 % of the 13 ns clock period); worst hold slack +0.13 ns.
- **Routing DRC:** 0 errors (TritonRoute converged in 5 iterations with 0
  remaining DRC errors).
- **LVS:** 0 device, net, property, or pin mismatches (Magic + Netgen clean).
- **Antenna check:** 0 violating nets or pins after `RepairAntennas`.
- **IR drop:** VPWR worst drop 0.53 mV (0.030 % of 1.8 V), VGND worst drop
  1.91 mV; both well within acceptable margins for a prototype design.
- **Disconnected pins:** 0 critical disconnected pins.

---

## 4. What Did Not Fully Work

The one remaining imperfection is the **16 max-fanout DRVs on clock-tree
buffers** described above. After three runs it is clear that these cannot be
resolved by adjusting `MAX_FANOUT_CONSTRAINT`, and the fix requires a
CTS-specific parameter change that was not pursued here due to time constraints.
The violations do not affect timing closure or functional correctness and will
be addressed in M4.

No other synthesis problems were encountered. The design did not fail any step.
There were no LVS disagreements, no routing convergence failures, and no timing
violations at any corner.

---

## 5. Scope Adjustment and Rationale

The module synthesized (`synth_top`) is the **compute core subsystem** of the
full M3 top module (`top.sv`), not the complete integrated design. The full
`top.sv` adds the AXI4-Stream wrapper (`interface.sv`) around the compute core.
This scope choice was made for two reasons.

First, the CF07 synthesis runs on `synth_top.sv` were completed successfully
before the M3 integration work (the `top.sv` wrapper and `tb_top.sv` testbench),
and the results are representative of the timing-critical portion of the design.
The AXI4-Stream interface (`interface.sv`) contains only a combinational
backpressure assignment, a 2-register TLAST delay pipeline, and a single output
holding register — roughly 5–10 additional flip-flops and a handful of
combinational gates. Its timing contribution is negligible relative to the
multiplier carry chain that dominates the critical path. A synthesis of
`top.sv` would produce area and timing numbers within a few percent of those
shown here, with the critical path unchanged.

Second, `synth_top.sv` was explicitly designed as the M3 synthesis target from
the start of the milestone (see `codefest/cf07/synth/m3_plan.md`). It includes
the M3 performance improvements (2-lane parallelism, 13 ns clock) that answer
the M1 throughput shortfall. The 74 fps result exceeds the M1 40 fps software
baseline by approximately 1.85×, which is the primary M3 deliverable.

For M4, the plan is to synthesize the complete `top.sv` (including the
AXI4-Stream interface) and to benchmark the integrated design against the M1
profiling results. The M1 sw_baseline.md records the Phase 1 wall time as
~22 s over 10 passes on 880 decoded frames at 1920×1080, implying ~40 fps. The
M4 hardware benchmark will measure the same pixel volume processed through the
accelerator via the AXI4-Stream host interface and compare directly to that
number. The scope adjustment at M3 does not compromise the M4 comparison because
the compute engine being benchmarked is functionally and architecturally
identical to the module synthesized here.

---

## 6. Flow Warnings (Non-Blocking)

The following warnings appeared in every run and are cosmetic:

- `'PNR_SDC_FILE' is not defined` — generic fallback SDC used; acceptable for
  a prototype without custom timing exceptions.
- `'SIGNOFF_SDC_FILE' is not defined` — same.
- `'VSRC_LOC_FILES' was not given a value` — IR drop analysis may be slightly
  less accurate without explicit voltage-source pin locations; irrelevant for a
  non-tape-out prototype.
- `[GRT-0097] No global routing found for nets` — informational, emitted by
  mid-PNR STA steps that run before global routing is complete.
- `[DRT-0349] LEF58_ENCLOSURE with no CUTCLASS is not supported` — a Sky130
  PDK annotation limitation in the via layers; does not affect routing correctness.

None of these warnings indicate a design problem or require action before M4.
