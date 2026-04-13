# Software baseline benchmark (M1)

This document records the **software-only** performance baseline for the sign-language gesture recognition workload (OpenCV preprocess + optional TensorFlow spatial / RNN stages), so **M4 speedup comparisons** can be reproduced. Update values whenever hardware, OS, Python, or dependency versions change.

---

## 1. Platform and configuration

| Item | Value |
| --- | --- |
| **CPU** | AMD Ryzen 9 4900HS with Radeon Graphics |
| **GPU** | Integrated AMD Radeon Graphics (see notes) |
| **OS** | Microsoft Windows 11 Home (build 22631) |
| **Python** | 3.9.13 |
| **Primary benchmark script** | `codefest/cf02/profiling/profile_sign_language_m1.py` |
| **Upstream application repo** | [sign-language-gesture-recognition](https://github.com/hthuwal/sign-language-gesture-recognition) (local clone path fixed in the profiler via `SL_ROOT`) |

**Batch sizes (workload-specific)**

| Stage | Batch / parallelism | Notes |
| --- | --- | --- |
| Phase 1 — preprocess | Implicit batch size **1** (frame loop) | `VideoCapture.read` → `handsegment()` → `cvtColor`; `--max-frames` caps frames per pass (default 200; short clips decode fewer). |
| Phase 2 — spatial CNN-style | **4** | JPEG batch inference (`_phase2_spatial_profile.py`, `--batch-size` default). |
| Phase 3 — RNN-style training | **8** | Keras `model.fit(..., batch_size=8)` (`_phase3_rnn_profile.py`). |

**Reproducibility notes**

- **TensorFlow:** Phase 2 uses TensorFlow 1-style `Session.run`; Phase 3 uses `tf.keras`. On native Windows, TensorFlow ≥2.11 typically does **not** use NVIDIA GPU; expect **CPU** execution unless you use WSL2 / DirectML / a Linux box. Record the exact `tensorflow` and `opencv-python` package versions from `pip freeze` in your environment file for M4.
- **Video input:** Default profiler video: LSA64 clip under `train_videos/001/` (see `project_profile.txt`). Pin the file path for comparisons.

---

## 2. Execution time (wall clock)

**Requirement:** Report **wall-clock** time as the **median** over **at least 10 runs** (≥10).

**Current recorded measurement (Phase 1 preprocess)**

The bundled profiler enables **one** `cProfile` session over **10 sequential calls** to `work_once(...)` (after a warm-up). That yields **one** total elapsed time for all 10 passes combined, **not** ten independent wall times, so it does **not** by itself satisfy the median-of-10-runs rule.

| Quantity | Value | Source |
| --- | --- | --- |
| Phase 1 total time (10 passes, single profile) | **22.035 s** | `project_profile.txt` header (`function calls in … seconds`) |
| Implied mean time per pass | **~2.20 s** | 22.035 / 10 |
| Frames processed (this run) | **880** | 10 passes × 88 frames decoded from sample clip |

**To complete for M4 / course compliance**

1. Wrap each `work_once` (or full pipeline) in a timer **without** `cProfile`, or use `time.perf_counter()` around each of **≥10** cold or steady-state runs.
2. Record **10+ wall times** (seconds) and set **median wall time** = median of that list.
3. Paste the table here:

| Run index | Wall time (s) |
| --- | ---: |
| 1 | *(fill)* |
| … | … |
| **Median** | *(fill)* |

---

## 3. Throughput

**Requirement:** Report throughput in **samples/sec**, **tokens/sec**, or **FLOPs/sec** (or **Gop/s**), whichever fits the task.

For this vision pipeline, **frames/sec** (preprocess) and **batches/sec** (Phase 2) are the natural “sample” rates.

| Metric | Formula (Phase 1) | Value (using 22.035 s total for 880 frames) |
| --- | --- | --- |
| **Frames / s** (end-to-end preprocess in profiled region) | frames / total wall time | **880 / 22.035 ≈ 39.9** frames/s |
| **Mean frames / s per pass** | frames per pass / mean pass time | **88 / 2.20 ≈ 40.0** frames/s |

**Analytic work rate (model in `ai_calculation.md` / `project_profile.csv`)**

| Metric | Value | Notes |
| --- | --- | --- |
| Achieved **Gop/s** (int-op equivalent, preprocess) | **~4.26** | `project_profile.csv` (`achieved_gops_per_s`), uses modeled int-ops per frame and summed hotspot times. |
| Implied **GB/s** (if modeled bytes touch DRAM once) | **~4.46** | `implied_gbytes_per_s` in CSV. |

Replace the frame counts and times with **median** wall time from §2 when available.

---

## 4. Memory usage

**Requirement:** Report **peak RSS** (process resident set) or **GPU memory**, as appropriate.

| Metric | Value | How to capture |
| --- | --- | --- |
| Peak **RSS** (Phase 1 Python process) | *(TBD)* | e.g. Windows: run under **Resource Monitor**, **Process Explorer**, or `Get-Process python | Select-Object WS` after peak; Linux: `/usr/bin/time -v` **max resident set**. |
| **GPU memory** | N/A or *(TBD)* | Expect **0** or small on CPU-only TF on Windows; use **Task Manager → Performance → GPU** or `nvidia-smi` if you move to CUDA. |

---

## 5. One-line summary (for M4 tables)

| Field | Value |
| --- | --- |
| Platform | Ryzen 9 4900HS, Win11, Python 3.9.13 |
| Preprocess median wall (10+ runs) | *(TBD — see §2)* |
| Preprocess throughput | ~**40** frames/s (interim, from §3; revise with median time) |
| Peak RSS | *(TBD)* |

---

*Last updated from automated host introspection and `codefest/cf02/profiling/project_profile.*`. Fill TBD fields before submitting M4.*
