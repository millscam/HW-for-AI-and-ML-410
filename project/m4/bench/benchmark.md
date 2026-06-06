# M4 Benchmark Comparison — Software vs Hardware

**Frame geometry:** 1080×1920 (\(P = 2{,}073{,}600\) pixels)  
**Kernel (RTL):** Fused BT.601 BGR→grayscale + one in-range mask (`synth_top`, 2 lanes)  
**Software baseline:** M1 Phase-1 preprocess (archival wall time)

---

## Summary

| | Software (M1) | Hardware (M4 primary) | Ratio |
|--|---------------|-------------------------|------:|
| **Label** | M1 archival (not median-of-10) | projected (post-synthesis; not FPGA) | — |
| **Throughput** | **39.94 frames/s** | **74.17 frames/s** | **1.86×** |
| **Time per frame** | 25.04 ms | 13.48 ms | — |
| **GOPS (reported op model)** | 1.74 (21 ops/px) | 0.769 (5 FLOP/px) | 0.44× |
| **GOPS (fused 5 FLOP/px only)** | 0.414 | 0.769 | **1.86×** |

The accelerator is **faster in frames per second** for the fused preprocess slice it implements, but **lower in “full-preprocess” GOPS** because the CPU baseline still runs HSV/`handsegment` work that is not in today’s RTL.

---

## Measurement methods

### Software baseline (M1 archival — not median-of-10)

- **Source:** `codefest/cf02/profiling/project_profile.txt` — **22.035 s** total wall time for **one** `cProfile` session over **10 sequential passes** (**880** decoded 1080p frames). This is **not** a median of ten independent timed runs; see `project/m1/sw_baseline.md` for the course median-of-10 requirement.
- **Metric:** frames/s = \(880 / 22.035 \approx 39.94\) fps; ms/frame = **25.04**.
- **Full-path GOPS:** \(43.5456 \times 10^6\) integer ops/frame × fps / \(10^9\) = **1.74 GOPS** (21 ops/px byte model from M1 profiling).
- **Fused-kernel GOPS (apples-to-apples with RTL):** \(5 \times P \times\) fps / \(10^9\) = **0.414 GOPS** at the same wall-clock fps.
- **Arithmetic intensity (full preprocess):** \(AI \approx 21/22 = 0.955\) FLOP/byte.
- **Note:** OpenCV was **not** re-run in M4 (no live `cv2` environment). Numbers trace to the archived profile; see `bench/sw_results.json` and `bench/benchmark_data.csv`. Label in CSV: **M1 archival (not median-of-10)**.

### Hardware accelerator (primary: post-synthesis)

- **DUT:** `project/m4/rtl/synth_top.sv` (2-lane), signoff run `RUN_2026-05-22_05-04-01`.
- **Clock:** **13 ns** period → **76.9 MHz**, worst setup slack **+3.37 ns** (see `project/m4/synth/timing_report.txt`).
- **Throughput model:** 2 pixels per clock when `valid_in` is asserted →  
  \(\text{fps} = f_{\mathrm{clk}} \times 2 / P = 76.9 \times 10^6 \times 2 / 2{,}073{,}600 \approx\) **74.17 fps**.
- **GOPS:** \(5\ \text{FLOP/px} \times 2\ \text{lanes} \times 76.9\ \text{MHz} / 1000 =\) **0.769 GOPS**.
- **Stream bandwidth (fused I/O model):** 10 B/cycle × 76.9 MHz ≈ **0.769 GB/s**.
- **Label:** **projected** — no FPGA bitstream; frequency comes from STA closure, not silicon measurement.

### Hardware cross-check (cycle simulation)

- **Source:** `bench/tb_bench_synth_top.sv` + Icarus, **512** pixel-pairs, **519** cycles @ **13 ns**.
- **Extrapolation:** \(\text{cycles/frame} = (519/512)\times(P/2)+2 = 1{,}050{,}977\) → **73.19 fps**, **0.759 GOPS** (within **~1.3%** of synthesis projection).
- **Artifacts:** `bench/hw_results.json` → `sim_extrapolation`; rows `hardware_sim` in `benchmark_data.csv`.

---

## Speedup vs M1 software baseline

\[
\text{Speedup} = \frac{t_{\mathrm{SW}}}{t_{\mathrm{HW}}}
= \frac{25.04\ \mathrm{ms}}{13.48\ \mathrm{ms}}
= \frac{39.94\ \mathrm{fps}}{74.17\ \mathrm{fps}}
\approx \mathbf{1.86\times}
\]

Using the **fused 5 FLOP/px** op count on both sides: \(0.769 / 0.414 \approx\) **1.86×** as well.

If the denominator uses **full-preprocess** GOPS (1.74), the ratio is **0.44×** — expected until HSV/`handsegment` is implemented in RTL.

---

## Energy (optional, synthesis-based)

| Quantity | Value | Source |
|----------|------:|--------|
| Total power (nom_tt) | **2.02 mW** | `project/m4/synth/power_report.txt` |
| Energy per frame | **27.3 µJ** | \(2.02\ \mathrm{mW} / 74.17\ \mathrm{fps}\) |
| Software energy | *not measured* | M1 has no package-power log |

A fair SW energy comparison would need RAPL or a wall power meter on the same workload; not available in the archival M1 package.

---

## Roofline (`bench/roofline_final.png`)

- **Roof:** Sky130 `synth_top` signoff — **0.769 GOPS** peak, **0.769 GB/s** stream cap → ridge at \(AI = 1.0\).
- **M4 accelerator point:** **0.769 GOPS** at **AI = 1.0** (projected; **not** the M1 hypothetical ASIC target).
- **M1 software points:**
  - Full preprocess: **1.74 GOPS** @ **AI ≈ 0.95** (measured wall clock).
  - Fused-kernel equivalent: **0.414 GOPS** @ **AI = 1.0** (same 5 FLOP/px model as RTL).

The vertical gap between **1.74 GOPS (SW)** and **0.769 GOPS (HW)** on the plot is mostly **different op definitions**, not a synthesis failure. Frame-rate speedup (**1.86×**) is the fair throughput comparison for the overlapping kernel.

---

## Raw data and regeneration

| File | Role |
|------|------|
| `benchmark_data.csv` | All reported numbers (grader-traceable) |
| `sw_results.json` | Parsed M1 metrics |
| `hw_results.json` | Synthesis projection + sim extrapolation |
| `run_m4_benchmarks.py` | Regenerate CSV/JSON |
| `plot_roofline_final.py` | Regenerate `roofline_final.png` |

From repository root:

```bash
python project/m4/bench/run_m4_benchmarks.py
python project/m4/bench/plot_roofline_final.py
```

Requires `iverilog`/`vvp` for the sim cross-check row.

---

## Scope alignment (RTL vs baseline)

| | Software | Hardware |
|--|----------|----------|
| **Includes** | `read` + `handsegment` (HSV, 2× `inRange`, `bitwise_*`) + `cvtColor` | Fused gray + **one** in-range mask only |
| **Cosim path** | — | `top.sv` (1-lane AXI) verified in `sim/final_run.log` |
| **Benchmark path** | — | `synth_top` (2-lane), matches `project/m4/synth/` signoff |

End-to-end host streaming (`top.sv`) runs at half the peak pixel rate of `synth_top`; reported throughput uses the **synthesized** 2-lane engine that defines area/timing/power in M4.

**DUT alignment:** Checklist RTL (`top`, `compute_core`, `interface`) is what cosim verifies. **74.17 fps** and synthesis reports apply to **`synth_top` only** (2-lane). Do not claim integrated `top` achieves that rate without stating the lane difference.
