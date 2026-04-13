# Arithmetic intensity: dominant preprocessing kernel

This note supports the Codefest M1 roofline work for the **sign-language gesture recognition** pipeline. The **cProfile-dominant** work in the profiled loop is OpenCV inside `handsegment()` (especially `cv2.bitwise_and` with a mask) plus `cv2.cvtColor(..., BGR2GRAY)` right after, matching `video-to-frame.py` and `profile_sign_language_m1.py`.

**Dominant kernel (time):** masked segmentation and grayscale conversion on each full-color frame.

- **Code:** `sign-language-gesture-recognition-master/handsegment.py` (`handsegment`) and the caller’s `cv2.cvtColor(seg, cv2.COLOR_BGR2GRAY)`.
- **Geometry (from profiled LSA64 clip):** `H = 1080`, `W = 1920`, `P = H × W = 2,073,600` pixels per frame.

---

## Summary table

Values below use `P = 2,073,600` unless noted.

| Quantity | Formula or scope | Value |
| --- | --- | ---: |
| Frame size | H × W | 1080 × 1920 |
| Pixels per frame | P = H × W | 2,073,600 |
| Work ops, `handsegment` only | O_inRange + O_or + O_and = 16P | 33,177,600 |
| Work ops, BGR2GRAY | O_gray = 5P | 10,368,000 |
| Work ops, full preprocess loop | O_total = 21P | 43,545,600 |
| Bytes moved (no DRAM reuse) | B_total = 22P | 45,619,200 (~43.5 MiB) |
| Arithmetic intensity (full kernel) | 21P / 22P = 21/22 | **0.9545 ops/byte** |
| Work ops, `bitwise_and` only | 3P | 6,220,800 |
| Bytes, `bitwise_and` only (no reuse) | 7P | 14,515,200 |
| Arithmetic intensity (`bitwise_and` only) | 3P / 7P = 3/7 | **0.4286 ops/byte** |

Use the **full-kernel** row for the preprocess loop as a whole; use the **`bitwise_and`-only** rows when citing the single hottest cProfile bucket.

---

## 1. Operation model (analytic work ops)

We count **scalar arithmetic and logical work** the algorithm must do per pixel. Compares, bitwise ops, and fixed-point multiply-adds for gray each count as **one operation** (common for roofline when mapping to a CPU GFLOP/s ceiling). This is **not** IEEE-754 FLOPs; call the total **work ops** and use **1 op ≈ 1 FLOP-equivalent** on your chart if your course allows that.

### 1.1 `cv2.inRange` on one 3-channel `uint8` pixel

For each B, G, R channel, the code checks that the value lies between `lower_c` and `upper_c`. That is **two comparisons per channel** (e.g. `x >= lower_c` and `x <= upper_c`), or the same idea in SIMD.

**Per pixel, one `inRange` call:**

- ops per pixel = 3 channels × 2 compares → **6 ops/pixel**

**`handsegment` calls `inRange` twice** (two HSV bands):

- **O_inRange = 2 × 6 × P = 12P ops**

### 1.2 `cv2.bitwise_or(mask1, mask2)`

**One** bitwise OR per pixel:

- **O_or = P ops**

### 1.3 `cv2.bitwise_and(frame, frame, mask=mask)`

Each pixel updates **three** BGR channels with the mask, so treat that as **three bitwise ANDs per pixel**:

- **O_and = 3P ops**

### 1.4 Subtotal: `handsegment` only

```text
O_hs = O_inRange + O_or + O_and
     = 12P + P + 3P
     = 16P ops
```

### 1.5 `cv2.cvtColor(..., COLOR_BGR2GRAY)`

OpenCV uses a **fixed-point linear mix** of B, G, R (BT.601-style weights in integer form). Per output pixel:

- 3 multiplications (weights × channel)
- 2 additions (sum them)

So **5 ops/pixel** → **O_gray = 5P ops**.

### 1.6 Full per-frame kernel (what the profiler runs)

```text
O_total = O_hs + O_gray
        = 16P + 5P
        = 21P ops
```

**Numbers plugged in:**

- P = 1080 × 1920 = **2,073,600**
- **O_total = 21 × 2,073,600 = 43,545,600 ops per frame**

---

## 2. Bytes transferred (no reuse in DRAM)

**Assumption:** every operand is loaded from DRAM and every result written back; **no cache reuse** and passes are not fused. Full intermediate buffers are written, then read again in a later step. Tiny `lower`/`upper` arrays are ignored.

| Step | Reads | Writes | Notes |
| --- | --- | --- | --- |
| `inRange` → `mask1` | 3P (BGR) | P (mask) | First band |
| `inRange` → `mask2` | 3P (BGR) | P (mask) | BGR read again |
| `bitwise_or` | P + P (masks) | P (combined) | |
| `bitwise_and` | 3P (BGR) + P (mask) | 3P (BGR out) | |
| `cvtColor` | 3P (BGR) | P (gray) | Segmented BGR read again |

**Sum all reads:** 3P + 3P + 2P + 4P + 3P = **15P**

**Sum all writes:** P + P + P + 3P + P = **7P**

**Total bytes per frame:**

```text
B_total = 15P + 7P = 22P
```

**Plug in P:**

- **B_total = 22 × 2,073,600 = 45,619,200 bytes ≈ 43.5 MiB**

---

## 3. Arithmetic intensity

```text
AI = O_total / B_total
   = 21P / 22P
   = 21 / 22
   ≈ 0.9545 ops/byte
```

**Check with full numbers:** 43,545,600 ÷ 45,619,200 ≈ **0.9545 ops/byte**.

Under this **no-reuse** model the kernel is **memory-volume heavy**: ridge performance is roughly **AI × memory bandwidth** (e.g. at 50 GB/s DRAM, on the order of **48 Gop/s** on the memory ridge if you treat 1 op like 1 FLOP-equiv).

---

## 4. Slice: hottest `bitwise_and` only (cProfile)

cProfile **tottime** often peaks on `cv2.bitwise_and` (masked copy). **Only that piece:**

- **Ops:** 3P (three ANDs per pixel)
- **Bytes (no reuse):** read BGR 3P, read mask P, write BGR 3P → **7P**

```text
AI_and_only = 3P / 7P = 3/7 ≈ 0.429 ops/byte
```

With P = 2,073,600: **O = 6,220,800** ops, **B = 14,515,200** bytes.

Use **Section 4** if you must cite the **single hottest call**; use **Section 3** (and the summary table) for the **full per-frame** preprocess the pipeline actually runs.

---

## 5. Neural-network stages (brief)

The **spatial CNN** (`predict_spatial.py`) and **RNN** (`rnn_train.py`) live mostly inside TensorFlow / tflearn. Analytic AI there needs layer sizes (e.g. Inception bottleneck, LSTM width, 201 frames). **fvcore** / **torchinfo** help for PyTorch; **tf.profiler** or hand counts (e.g. MatMul **2×M×N×K** FLOPs for (M×K)·(K×N)) for TensorFlow. Phases 2–3 in `project_profile.txt` cover those; **this file** is for the **OpenCV preprocess** kernel that dominated Phase 1.
