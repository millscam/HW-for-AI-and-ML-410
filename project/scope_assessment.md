# Project Scope Assessment

**Status:** Scope **confirmed** with one M3 calibration (pixel throughput).

## Project recap

Sign-language gesture recognition accelerator (`heilmeier.md`). Three phases identified from M1 profiling:

1. **Preprocessing** — fused BGR→grayscale + in-range threshold; software baseline **~40 fps** at 1920×1080 (`project/m1/sw_baseline.md`, `interface_selection.md` §2.1).
2. **CNN** — per-frame inference (M1 software ~1.0 s / batch).
3. **RNN/LSTM** — sequence model (M1 software ~9.6 s for 10× one-epoch fit).

Plan from M1/M2: implement Phase 1 first as `compute_core` (M2) / `synth_top` (CF07), then evaluate Phase 2/3 area later. **No change to this ordering.**

## What CF07 synthesis confirms

From my Syntesis, we know that the preprocess kernel section of the accelorator can be improved and currently works well. with the core utilization size being 42% utilization, the current slack timing well below the 20ns clock and a clean signoff besides 1 DRV violation.

## Adjustment: throughput calibration for M3

Currently, my acceloratior for preprocessing is significantly slower than the baseline, the core delivers about 50Mpix/s = 24fps at 1920x1080, and the baseline was running at around 40fps. to fix this issue there are two things I plan to do: increase the clock speed to 12-13ns (83MHz), and add a second pixel lane so I can double the pix/cycle and with utilization at 42.4% there is enough room to make this change.


## CNN / RNN scope

Unchanged: My work has mostly covered the Grayscale conversion, so if I do get around to this at all, It will be in later milestones

## Summary

| Item | Decision |
|------|----------|
| Phase 1 in RTL/synthesis | **Confirmed** (CF07 results support it) |
| Phase 2/3 (CNN/RNN) | **Deferred to M4+** (unchanged) |
| Clock target / parallelism | **Will be re-tuned in M3** to clear the 40 fps baseline |
| Host interface (PCIe) | **Unchanged** |
