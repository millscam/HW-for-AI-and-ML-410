# CF09 Benchmark Results — Software vs Hardware

**Date:** 2026-05-29  
**Comparison:** M1 Phase-1 software baseline vs M3 `synth_top` accelerator (Sky130 HD, OpenLane signoff)  
**Frame geometry:** 1080×1920 (\(P = 2{,}073{,}600\) pixels)

---

## Scope and methodology

| Item | Software (Task 6) | Hardware (Task 7) |
|------|-------------------|-------------------|
| **What runs** | Full preprocess: `VideoCapture.read` → `handsegment()` → `cvtColor(BGR2GRAY)` | Fused **BT.601 gray + one in-range mask** (`synth_top`, 2 lanes) |
| **How measured** | **M1 archival** — `project_profile.txt` wall time (22.035 s / 880 frames). OpenCV was **not** re-run in CF09 (no `cv2` in this environment). | **Projected** from synthesis: \(f_{\mathrm{clk}} = 76.9\ \mathrm{MHz}\), 13 ns MET, 2 lanes × 5 FLOP/px. |
| **Cross-check** | `project_profile.csv` analytic rates | Icarus cycle extrapolation: 512 pixel-pairs → scale to full frame (**projected**, label in JSON). |
| **C1 arithmetic intensity** | Full preprocess: \(AI = 21/22 \approx 0.955\) op/B | Fused RTL upper bound: \(AI_{\mathrm{high}} = 1.0\) FLOP/B |

**Extrapolation (HW sim):** `tb_bench_synth_top.sv` streams 512 pixel-pairs at 12 ns period (bench clock); measured **519 cycles** for that burst. Full-frame cycles \(\approx (519/512)\times(P/2)+2 = 1{,}050{,}977\); frame time \(\approx 12.6\ \mathrm{ms}\) → **79.3 fps** (within ~7% of synthesis projection **74.2 fps**). Primary reported HW numbers use **synthesis clock (13 ns, 76.9 MHz)**.

---

## Results table (Tasks 6–8)

| Metric | M1 software baseline | HW accelerator (`synth_top`) | Notes |
|--------|----------------------|------------------------------|--------|
| **Label** | measured (M1 archival) | **projected** (synthesis) | See scope above |
| **Platform** | AMD Ryzen 9 4900HS, Win11, Python 3.9.13 | sky130A / `sky130_fd_sc_hd`, nom_tt 1.8 V | |
| **Execution time (per frame)** | **25.04 ms** | **13.48 ms** | SW: 22.035 s ÷ 880 frames |
| **Execution time (880 frames)** | **22,035 ms** | **11,864 ms** (projected) | HW: 880 × 13.48 ms |
| **Throughput (frames/s)** | **39.94** | **74.17** | |
| **Throughput (GOPS)** | **1.74** (21P ops, wall clock) | **0.769** (5 FLOP/px, projected) | SW also **4.26 GOPS** vs summed cProfile algo time (not wall) |
| **Throughput (GOPS, fused-kernel ops only)** | **0.414** (5P ops × wall fps) | **0.769** | Apples-to-apples op count |
| **Memory (RSS)** | *not recorded in M1* | N/A (streaming RTL) | Re-run SW with `psutil` for RSS |
| **Implied / stream bandwidth** | **~1.82 GB/s** (22P byte model) | **0.769 GB/s** (10 B/cycle × 76.9 MHz) | |
| **Power** | *not measured* | **2.02 mW** (OpenROAD, vectorless) | nom_tt_025C_1v80 |
| **Energy per frame** | *not measured* | **27.3 µJ** (projected: 2.02 mW ÷ 74.17 fps) | |
| **Compute efficiency** | — | **~380 GFLOP/s/W** (0.769 GOPS ÷ 2.02 mW) | SW Joules/frame not available |

### Speedup (throughput ratio)

| Comparison | Ratio |
|------------|------:|
| **Frame throughput (reported)** | \(74.17 / 39.94 =\) **1.86×** |
| **Fused-kernel GOPS (5P ops, wall-based SW)** | \(0.769 / 0.414 =\) **1.86×** |
| **Full-preprocess GOPS (21P, wall-based SW)** | \(0.769 / 1.74 =\) **0.44×** (ASIC does less work per frame today) |

The **1.86×** frame-rate speedup matches M3 synthesis notes (~40 fps → ~74 fps) for the **overlapping** fused slice. The full OpenCV path remains faster in **raw GOPS** on a desktop CPU because it still executes HSV/`bitwise_*` in highly optimized libraries not yet in RTL.

### Energy efficiency (synthesis only)

- **HW (projected):** \(27.3\ \mu\mathrm{J}\)/frame at 2.02 mW and 74.17 fps.  
- **SW:** No package power measurement in M1 → **energy improvement ratio not reported** (would need RAPL or wall power meter).  
- **Qualitative:** Sub-mW ASIC vs multi-watt CPU for the same fused outputs implies large efficiency headroom once the full preprocess path is integrated.

---

## Raw artifacts

| File | Contents |
|------|----------|
| `sw_results.json` | Parsed M1 archival metrics |
| `hw_results.json` | Synthesis projection + Icarus extrapolation |
| `run_cf09_benchmarks.py` | Regenerate JSON |
| `tb_bench_synth_top.sv` | Representative cycle benchmark |

**Regenerate:** `python codefest/cf09/benchmarks/run_cf09_benchmarks.py`
