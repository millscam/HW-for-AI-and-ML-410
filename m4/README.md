# M4 — Final Submission Package

Sign-Language Gesture Recognition Accelerator — ECE 410/510 HW4AI, Milestone 4 (final, no revision).

This folder is the **graded M4 deliverable**. Earlier milestones remain under `project/m1/`, `project/m2/`, and `project/m3/`. The **design justification report** (PDF) is the primary narrative for the final exam:

**[project/m4/report/design_justification.pdf](report/design_justification.pdf)**

---

## What this submission contains


| Layer                 | Role                                                                               |
| --------------------- | ---------------------------------------------------------------------------------- |
| `**rtl/`**            | Final RTL: integrated `top` (1-lane cosim) + `synth_top` (2-lane OpenLane signoff) |
| `**tb/**`, `**sim/**` | End-to-end Icarus cosimulation (PASS log + waveform)                               |
| `**synth/**`          | OpenLane 2 config, flow log, timing/area/power reports                             |
| `**bench/**`          | Software vs hardware benchmark, CSV, roofline plot                                 |
| `**report/**`         | Nine-section design justification PDF + figures                                    |
| `**scripts/**`        | Reproduction helpers (sim + OpenLane)                                              |


**Scope note:** Cosimulation exercises `**top.sv`** (1-lane `compute_core` + AXI4-Stream). **Benchmarks and synthesis** use `**synth_top.sv`** (2-lane), which produced the signoff timing and the **1.86×** frame-rate speedup vs M1. See `bench/benchmark.md` and report §4–§8.

---

## File catalog

One line per file: **path**, **description**, **checklist item / report section**.


| Path                                       | Description                                                        | Supports                              |
| ------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------- |
| `README.md`                                | This catalog and reproduction index                                | Checklist §1 (M4 README)              |
| **RTL (`rtl/`) — Checklist §2**            |                                                                    |                                       |
| `rtl/top.sv`                               | Integrated top: `\interface` + 1-lane `compute_core`               | §2 source; report §4, §6              |
| `rtl/interface.sv`                         | AXI4-Stream slave/master wrapper (host ↔ core)                     | §2 source; report §5, §6              |
| `rtl/compute_core.sv`                      | Fused BT.601 gray + in-range mask (1-lane engine)                  | §2 source; report §3, §4              |
| `rtl/synth_top.sv`                         | 2-lane compute core (OpenLane + benchmark DUT)                     | §2 (companion RTL); report §4, §7, §8 |
| **Testbench & simulation — Checklist §2**  |                                                                    |                                       |
| `tb/tb_top.sv`                             | End-to-end AXI4-Stream testbench (self-contained compile)          | §2 testbench; report §6               |
| `sim/final_run.log`                        | Cosim transcript; ends with `PASS -- all end-to-end checks passed` | §2 simulation log; report §6          |
| `sim/final_waveform.png`                   | Annotated host write / compute / host read waveform                | §2 waveform; report Fig. 4, §6        |
| `sim/plot_final_waveform.py`               | Builds `final_waveform.png` from `tb_top.vcd`                      | Regenerate §2; report §6              |
| `sim/tb_top.vcd`                           | VCD dump from cosim (input to plot script)                         | Regenerate §2                         |
| `sim/sim_top.out`                          | Icarus compiled simulator binary                                   | Regenerate §2                         |
| **Synthesis — Checklist §3**               |                                                                    |                                       |
| `synth/config.json`                        | OpenLane 2 config (13 ns, `synth_top`, fanout/util)                | §3 configuration; report §7           |
| `synth/openlane_run.log`                   | Full OpenLane stdout/stderr (`RUN_2026-05-22_05-04-01`)            | §3 run log; report §7                 |
| `synth/timing_report.txt`                  | Post-PNR STA, slack, critical path excerpt                         | §3 timing; report §7                  |
| `synth/area_report.txt`                    | Yosys + post-PNR area and cell breakdown                           | §3 area; report §7                    |
| `synth/power_report.txt`                   | Vectorless power + IR drop summary                                 | §3 power; report §7, §8               |
| `synth/critical_path.md`                   | Expanded critical-path analysis (max_ss corner)                    | Report §7 (supplement)                |
| **Benchmark — Checklist §4**               |                                                                    |                                       |
| `bench/benchmark.md`                       | Throughput, speedup, methods, energy, roofline notes               | §4 benchmark; report §8               |
| `bench/benchmark_data.csv`                 | Raw numbers (SW, HW, speedup rows)                                 | §4 CSV; report §8                     |
| `bench/roofline_final.png`                 | Final roofline (M1 SW + M4 accelerator point)                      | §4 roofline; report Fig. 2, §2        |
| `bench/sw_results.json`                    | Parsed M1 archival software metrics                                | §4 traceability                       |
| `bench/hw_results.json`                    | Synthesis projection + Icarus cycle extrapolation                  | §4 traceability                       |
| `bench/run_m4_benchmarks.py`               | Regenerates JSON + CSV (+ optional sim bench)                      | §4 regeneration                       |
| `bench/plot_roofline_final.py`             | Regenerates `roofline_final.png`                                   | §4 regeneration                       |
| `bench/tb_bench_synth_top.sv`              | Cycle benchmark for `synth_top` (512 pixel-pairs)                  | §4 method; report §6, §8              |
| `bench/bench_synth_top.out`                | Compiled Icarus binary for cycle bench                             | Regenerate §4                         |
| **Report — Checklist §5**                  |                                                                    |                                       |
| `report/design_justification.pdf`          | Nine-section design justification (2k–5k words)                    | §5 report (all sections)              |
| `report/build_design_justification_pdf.py` | Rebuilds the PDF from embedded section text                        | Regenerate §5                         |
| `report/figures/fig1_block_diagram.png`    | Block diagram (host → AXI → core / synth_top)                      | Report Fig. 1, §4                     |
| `report/figures/fig2_roofline_final.png`   | Copy of bench roofline for report embedding                        | Report Fig. 2, §2                     |
| `report/figures/fig4_cosim_waveform.png`   | Copy of cosim waveform for report embedding                        | Report Fig. 4, §6                     |
| `report/figures/make_block_diagram.py`     | Regenerates Fig. 1                                                 | Regenerate §5 figures                 |
| **Scripts (reproduction)**                 |                                                                    |                                       |
| `scripts/run_final_sim.ps1`                | Compile + run cosim → `sim/final_run.log`                          | §2 reproduction                       |
| `scripts/run_openlane_m4.sh`               | OpenLane flow from `synth/config.json` (Linux/WSL)                 | §3 reproduction                       |


---

## Quick reproduction

Run from the **repository root** (folder containing `project/`).

### §2 — Cosimulation

```powershell
.\project\m4\scripts\run_final_sim.ps1
cd project\m4\sim
python plot_final_waveform.py
```

Expected last line in `sim/final_run.log`: `PASS -- all end-to-end checks passed`.

### §3 — Synthesis (Linux/WSL2 + OpenLane 2.3.10 + sky130A)

```bash
bash project/m4/scripts/run_openlane_m4.sh
```

Submitted reports correspond to signoff run `**RUN_2026-05-22_05-04-01**` (also captured in `synth/openlane_run.log`).

### §4 — Benchmarks

```bash
python project/m4/bench/run_m4_benchmarks.py
python project/m4/bench/plot_roofline_final.py 
```

---

## Headline results (traceable to `bench/benchmark_data.csv`)


| Metric         | Software (M1 archival)              | Hardware (`synth_top`, projected)           |
| -------------- | ----------------------------------- | ------------------------------------------- |
| Throughput     | **39.94 fps**                       | **74.17 fps**                               |
| Speedup        | —                                   | **1.86×**                                   |
| Clock / method | One cProfile run (not median-of-10) | 76.9 MHz STA signoff, 2 lanes; **not FPGA** |
| Power          | not measured                        | **2.02 mW** (nom_tt, vectorless)            |


---

## Related documents (outside `m4/`)


| Document                         | Path                                                    |
| -------------------------------- | ------------------------------------------------------- |
| Heilmeier / motivation           | `project/heilmeier.md`                                  |
| M1 software baseline             | `project/m1/sw_baseline.md`                             |
| M1 interface (PCIe)              | `project/m1/interface_selection.md`                     |
| M2 simulation guide              | `project/m2/README.md`                                  |
| M2/M4 precision (INT8, BT.601)   | `project/m2/precision.md`                               |
| M3 integration + synthesis notes | `project/m3/README.md`, `project/m3/synthesis_notes.md` |


---

## Submission tag

Create and push the grader tag when the repo is ready:

```bash
git tag m4-submission
git push origin m4-submission
```

(Checklist §1 — not a file in this folder.)