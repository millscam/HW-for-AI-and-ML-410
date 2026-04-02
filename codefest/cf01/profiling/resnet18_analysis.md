# ResNet-18: top layers by MAC count

Source: `resnet18_profile.txt` (torchinfo, batch=1, 3×224×224, FP32). Per-layer **Mult-Adds** from torchinfo are treated as MACs.

The stem convolution is the single largest layer. The next-largest MAC total (**115,605,504**) is shared by **13** `3×3` `Conv2d` layers (all spatial sizes where that block geometry matches). The table below lists the **five highest** per-layer MAC counts; ranks 2–5 are tied—here they are broken by order of appearance in the profile.

| Rank | Layer (torchinfo name) | MACs | Params |
| ---: | --- | ---: | ---: |
| 1 | Conv2d: 1-1 | 118,013,952 | 9,408 |
| 2 | Conv2d: 3-1 | 115,605,504 | 36,864 |
| 3 | Conv2d: 3-4 | 115,605,504 | 36,864 |
| 4 | Conv2d: 3-7 | 115,605,504 | 36,864 |
| 5 | Conv2d: 3-10 | 115,605,504 | 36,864 |

**Other layers tied at 115,605,504 MACs** (same count as ranks 2–5): Conv2d: 3-16, 3-20, 3-23, 3-29, 3-33, 3-36, 3-42, 3-46, 3-49—with param counts 147,456 (128-channel blocks), 589,824 (256-channel), or 2,359,296 (512-channel) depending on the block.

## Arithmetic intensity: Conv2d: 1-1 (highest MAC layer)

**Definition used:** arithmetic intensity = MACs performed ÷ total bytes moved to/from DRAM for this layer, under the stated assumption.

**Assumption:** Every input activation, every weight, and every output activation is moved across the memory interface **once** with **no reuse** (no cache hits, no data touched again from “fast” storage). FP32 ⇒ 4 bytes per scalar.

Shapes from `resnet18_profile.txt`: input `[1, 3, 224, 224]`, output `[1, 64, 112, 112]`, **9,408** weights (7×7, 3→64, no bias in torchvision’s ResNet stem).

### 1. Element counts

| Tensor | Shape | Elements |
| --- | --- | ---: |
| Input activations | 1 × 3 × 224 × 224 | 150,528 |
| Weights | 7 × 7 × 3 × 64 | 9,408 |
| Output activations | 1 × 64 × 112 × 112 | 802,816 |

### 2. DRAM traffic (bytes)

- Read input: \(150{,}528 \times 4 = 602{,}112\) B  
- Read weights: \(9{,}408 \times 4 = 37{,}632\) B  
- Write output: \(802{,}816 \times 4 = 3{,}211{,}264\) B  

\[
\text{Total bytes} = 602{,}112 + 37{,}632 + 3{,}211{,}264 = 3{,}851{,}008\ \text{B} \approx 3.67\ \text{MiB}
\]

### 3. MACs and intensity

From the profile, this layer has **118,013,952** MACs (torchinfo “Mult-Adds”).

\[
\text{Arithmetic intensity} = \frac{118{,}013{,}952\ \text{MACs}}{3{,}851{,}008\ \text{B}} \approx 30.6\ \text{MAC/B}
\]

Equivalently, if each MAC is counted as 2 FLOPs: \(\approx 61.3\) FLOP/B for the same traffic model.

So under a strict “no reuse, full FP32 DRAM traffic” model, the stem conv’s intensity is modest: each byte moved supports on the order of **31 multiply–accumulates**.
