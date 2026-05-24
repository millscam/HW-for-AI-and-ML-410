# Critical Path Analysis — M3 Synthesis

Design  : `synth_top` (2-lane BGR→grayscale + in-range threshold)
Run     : `RUN_2026-05-22_05-04-01` (OpenLane 2 v2.3.10, Sky130 HD)
Corner  : `max_ss_100C_1v60` (slow silicon, 100°C, 1.60 V — worst-case setup)
Source  : `codefest/cf07/synth/sta/50-openroad-stapostpnr__max_ss_100C_1v60__checks.rpt`

---

## Identification

**Startpoint:** Input port `g_in_0[3]` — bit 3 of the lane 0 green-channel byte,
entering the design through a `clkbuf_1` input buffer, then fanned out through
a `clkbuf_2` and a `dlymetal6s2s_1` delay cell inserted by OpenROAD's
post-routing timing repair.

**Endpoint:** Flip-flop `_2008_` (`sky130_fd_sc_hd__dfxtp_1`) — a single-bit
register holding one bit of the `s1_g150_0` partial-product result for lane 0.
This is Stage 1 of the compute pipeline: the registered output of the
`g_in_0 × 150` multiply operation (BT.601 green-channel coefficient ×256,
rounded to 150).

**Slack:** +3.370 ns (MET). Data arrives at 9.980 ns; required time is 13.350 ns
(13 ns clock period minus 0.250 ns clock uncertainty minus 0.256 ns library
setup time, plus propagated clock-tree delay).

---

## Logic Stages on the Critical Path

The path from `g_in_0[3]` to `_2008_/D` traverses **14 combinational cells**
across approximately 9.98 ns of combinational delay, structured as follows:

| Stage | Cell type        | Polarity | Cumulative time | Role |
|-------|------------------|----------|----------------|------|
| 0 | Input buffer + `clkbuf_1` | + | 2.016 ns | Input pad → internal net |
| 1 | `clkbuf_2` fanout buffer | + | 2.484 ns | Fanout to 6 loads |
| 2 | `dlymetal6s2s_1` delay cell | + | 2.872 ns | Post-route timing insert |
| 3 | `nand2_1` | − | 3.090 ns | Partial-product bit |
| 4 | `mux2_1` | − | 3.861 ns | **Heaviest: 770 ps** — carry-select logic |
| 5 | `xnor2_1` | − | 4.165 ns | XOR sum bit in multiplier |
| 6 | `and3_1` | − | 4.561 ns | Carry propagate |
| 7 | `or2_1` | − | 5.060 ns | Carry generate |
| 8 | `or4_2` | − | 6.515 ns | **Heaviest: 1455 ps** — 4-input OR across 4 partial sums |
| 9 | `or2_1` | − | 7.095 ns | Final carry merge |
| 10 | `a31oi_1` | + | 7.408 ns | AND-OR-INVERT, sum accumulation |
| 11 | `o21ba_1` | − | 7.774 ns | OR-AND with inverted input |
| 12 | `and2b_1` | − | 8.118 ns | Masked AND |
| 13 | `or3_1` | − | 8.951 ns | **Heaviest: 833 ps** — 3-input OR |
| 14 | `a21oi_1` | + | 9.366 ns | AND-OR-INVERT |
| 15 | `o21ai_1` | − | 9.592 ns | OR-AND-INVERT |
| 16 | `and3_1` | − | 9.979 ns | Final bit select → `_2008_/D` |

The three heaviest cells — `mux2_1` (770 ps), `or4_2` (1455 ps), and `or3_1`
(833 ps) — account for **3.06 ns** of the 7.98 ns of combinational delay within
the logic itself (the remaining time comes from the input-side buffering chain).
All three are part of the Yosys-synthesized carry/sum chain for the integer
multiply `g_in_0 × 150`.

---

## Why This Is the Critical Path

The `g_in_0 × 150` multiply (the BT.601 green-channel coefficient is 150, the
largest of the three: R×77, G×150, B×29) produces the widest partial sums and
the longest carry-propagation chain. Yosys implements it as a
**ripple-carry adder tree** of AND/OR/XOR/XNOR cells rather than a
dedicated multiplier macro, because Sky130 HD has no hard multiplier cell.
Each bit of the 8×8 product requires a carry chain that adds delay from LSB to
MSB; bit 3 of the green input (`g_in_0[3]`) sits roughly in the middle of the
carry chain, where accumulated carry delay is highest.

The lane 0 and lane 1 multiply trees are structurally identical (the RTL is
symmetric); the synthesizer chose one bit of lane 0's green-channel multiply as
the worst case due to slightly longer wire routing after placement.

---

## What Would Shorten It

1. **Tighten the clock target further (e.g. 12 ns → 83 MHz):** At the current
   +3.37 ns slack there is headroom to push the clock period down by roughly
   3 ns. The synthesizer would respond by choosing lower-drive cells with more
   stages (trading stage count for faster individual cells) and by applying
   more aggressive buffering, shortening the carry chain. This was the
   approach taken from Run 1 (20 ns) to Run 3 (13 ns) and it succeeded cleanly.

2. **Restructure the multiplier as a shift-add tree:** Since the coefficients
   are constants (77 = 64+8+4+1, 150 = 128+16+4+2, 29 = 16+8+4+1), Yosys
   already decomposes them into shift-add form. Explicitly writing the
   constant-coefficient multipliers as adder trees in RTL (rather than letting
   Yosys infer them) can give the synthesizer more freedom to balance delay
   across stages, reducing the worst carry-chain depth.

3. **Use a `sky130_fd_sc_hd__fa_1` full-adder primitive:** The Sky130 HD
   library includes a single full-adder cell with matched timing across sum and
   carry outputs. Replacing the synthesized OR/AND carry logic with explicit
   `fa_1` instances along the critical carry chain would reduce the carry
   propagation delay by eliminating the polarity inversions introduced by
   NAND/NOR decomposition.

4. **Pipeline an additional stage:** Adding a third pipeline register between
   Stage 1 (multiplies) and Stage 2 (accumulate/shift) would cut the
   combinational depth in half. Latency would increase from 2 to 3 clock
   cycles, but the throughput (1 result per clock) and the clock frequency
   target (which could then be pushed higher) would both improve. This is the
   most aggressive option and would require updating the testbench expected
   latency and the interface TLAST delay pipeline.

---

## DRV Note: Max-Fanout Violations

Separately from timing, the design has 16 max-fanout DRV violations, all on
**clock-tree buffers** (`clkbuf_0_clk/X` fanout=16, `clkbuf_4_*` fanout=7–12).
These are **not on the critical data path** and do not affect functional
correctness or timing closure. They arise because `MAX_FANOUT_CONSTRAINT=8`
in the config applies to Yosys and OpenROAD data-path repair only; the CTS
step builds the clock tree with its own fanout budget that is independent of
this parameter. The clock buffers operate within their `.lib` max-capacitance
limits (confirmed by 0 max-cap violations). Addressing them would require a
CTS-specific parameter such as `CTS_MAX_CAP` rather than `MAX_FANOUT_CONSTRAINT`.
