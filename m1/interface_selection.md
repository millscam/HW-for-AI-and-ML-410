# 7. Interface selection (M1)

**Course path:** `project/m1/interface_selection.md`  
**Chosen interface:** **PCIe** (peripheral component interconnect express)

**SPI** and **I²C** are familiar and easy to bring up on an MCU, but **they are not efficient for this workload** at the target operating point. The numbers below show why; the selected interface must deliver **on the order of gigabytes per second**, not kilobits.

---

## 1. Interface choice

| Candidate | Verdict for this project |
| --- | --- |
| **SPI** | Typical MCU SPI at tens of MHz is **~MB/s** effective—orders of magnitude below preprocess **~GB/s** streams. Fine for sensors and control, not for 1080p-class frame tensors. |
| **I²C** | Even slower (100 kHz–1 MHz class); **not** suitable for bulk vision data. |
| **AXI4-Lite** | Control/status registers only; **not** a bulk-data plane for frames or feature maps. |
| **AXI4-Stream** | Excellent **inside** an FPGA fabric (DMA ↔ accelerator PEs). This project still needs a **host-facing** link unless the entire pipeline lives on one FPGA SoC with no PC offload—in that case AXI4-Stream is the right *internal* streaming choice, paired with PS DDR ports. |
| **PCIe** | **Selected.** Standard **GB/s** link between a host (PC or embedded SoC with root complex) and an accelerator card or module—matches the software baseline (Ryzen laptop) and tensor/frame bandwidth. |
| **UCIe** | Die-to-die chiplet link (very high BW); appropriate for **multi-die packages**, not the first stop for a class accelerator tied to a notebook host. |

**Decision:** **PCIe** is the primary **host ↔ accelerator** interface for this project narrative: the host runs decode/orchestration and feeds tiles or frames; the accelerator runs the fused preprocess and/or CNN/RNN math. Internal RTL can still use **AXI4-Stream** between PCIe DMA engines and compute arrays (standard Xilinx/Intel patterns).

---

## 2. Bandwidth requirement at the target operating point

Use the assignment form:

\[
\text{throughput} \times \text{data width per item} = \text{required bandwidth}
\]

Equivalently for streaming bytes:

\[
(\text{samples/s}) \times (\text{bytes/sample}) = \text{B/s} \rightarrow \text{GB/s}.
\]

### 2.1 Preprocess kernel (Phase 1, analytic model)

From `ai_calculation.md` / `project_profile.csv`:

- Modeled traffic **~45.6 MiB** per 1080×1920 frame for the no–cache-reuse byte accounting (handsegment + BGR2GRAY).
- Software baseline order-of-magnitude **~40 frames/s** for the profiled preprocess region (`sw_baseline.md`).

Required sustained byte delivery (if every modeled byte crosses the interface once per frame):

| Quantity | Value |
| --- | ---: |
| Throughput | **40** frames/s |
| Bytes / frame | **45,619,200** B (≈ 45.6×10⁶ B) |
| **Required bandwidth** | 40 × 45,619,200 B/s ≈ **1.82×10⁹ B/s** ≈ **1.82 GB/s** |

So the **kernel at this operating point** needs on the order of **2 GB/s** sustained **for raw preprocess traffic alone** under the conservative byte model—not counting CNN/RNN activations/weights, which add more.

### 2.2 Aggressive accelerator target (roofline / partition note)

`partition_rationale.md` uses a **notional 512 GFLOP/s** PE array with arithmetic intensity **~0.955** FLOP-equivalent/byte at the preprocess roofline point, implying **~536 GB/s** effective operand delivery **to keep the array busy** if operands were supplied entirely from off-chip at that AI. That number is a **design stress** for **on-chip memory hierarchy** (wide SRAM / fusion), **not** something SPI/I²C or even a single **PCIe Gen3 ×1** link can supply.

**Takeaway:** **PCIe** addresses the **host ↔ accelerator** “feed the card” requirement at **GB/s** scale; meeting **hundreds of GB/s** inside the accelerator is a **local memory and on-chip streaming (e.g. AXI4-Stream)** problem, not SPI/I²C.

---

## 3. Rated bandwidth vs required (PCIe) and bottleneck

Representative **PCIe** effective payload throughput (per direction, order-of-magnitude, 8b/10b or 128b/130b ignored for class-level comparison):

| Link | ~Rated BW (per direction) |
| --- | ---: |
| **PCIe 3.0 ×4** | **~3.9 GB/s** |
| **PCIe 3.0 ×8** | **~7.9 GB/s** |
| **PCIe 4.0 ×4** | **~7.9 GB/s** |

**Comparison**

- **Required (preprocess-only, §2.1):** **~1.82 GB/s**
- **PCIe 3.0 ×4 rated:** **~3.9 GB/s**

So at the **preprocess** target, **PCIe Gen3 ×4** has **roughly 2× headroom** versus the **1.82 GB/s** estimate—**not** interface-limited for that slice alone, assuming the endpoint can sustain near-line-rate DMA.

**Is the design interface-bound on the roofline?**

- **At the host link (PCIe):** For **~2 GB/s** preprocess streaming, **no**—PCIe Gen3 ×4 is **not** the bottleneck versus that requirement.
- **On the original CPU roofline** (Ryzen, **~51.2 GB/s** DRAM spec in your plot): the preprocess kernel was **memory-bound in principle** (low AI vs CPU ridge) but **far below** the memory-ridge performance in practice—**implementation / fusion / reuse**, not PCIe, was the issue there because the workload ran on **CPU**, not on an accelerator behind PCIe.
- **If the accelerator target stays 512 GFLOP/s with operands at ~0.955 AI from DRAM:** the **bottleneck moves to on-chip memory / width (~536 GB/s)** per `partition_rationale.md`; **PCIe (~4–8 GB/s)** cannot feed that rate **from host memory** without **large on-accelerator SRAM or HBM**. **Impact:** you must **stage weights and tiles** on-card and accept **PCIe bursts** + **long reuse** in local memory—otherwise the design becomes **PCIe-bound** (effective throughput capped at **~4–8 GB/s** per Gen3 ×4/×8), and realized **GFLOP/s** drops to roughly **(4–8 GB/s) × 0.955 ≈ 4–8 GFLOP/s** from host streaming alone—a **large gap** vs 512 GFLOP/s unless data is reused on-chip.

**Quantify interface-bound case (order of magnitude):**

- If **only** PCIe Gen3 ×4 (**~3.9 GB/s**) supplied fresh operands at **AI = 0.955**, the **ceiling** from the link is **~3.9 × 0.955 ≈ 3.7** effective GFLOP/s of “useful” work at that AI—versus **512 GFLOP/s** target, ratio **~140×** short. Hence **on-chip buffering and reuse** (or **wider/faster** attach) are mandatory; **SPI/I²C** would be short by **four to six orders of magnitude**, not tens of percent.

---

## 4. Host platform assumption

**Assumed host:** **PC-class client** (e.g. **AMD Ryzen** notebook matching the M1 software baseline), i.e. an **x64 host with a PCIe root complex**—the same class of machine that runs OpenCV + TensorFlow today.

**Not assumed as the primary host for this interface choice:** bare **MCU** (SPI/I²C-only)—incompatible with **GB/s** offload without a different link.

**Optional variant:** **FPGA SoC** (e.g. Zynq MPSoC) as **both** host PS and PL accelerator: bulk data then moves over **AXI HP + AXI4-Stream** inside the chip; **PCIe** still applies if the card talks to an **external** PC. Document which variant you implement in RTL.

---

## 5. Summary

| Item | Content |
| --- | --- |
| **Selected interface** | **PCIe** (host ↔ accelerator) |
| **Why not SPI / I²C** | Throughput × frame size needs **~GB/s**; SPI/I²C are **~MB/s or less**—unsuitable. |
| **Required BW (example)** | **~1.82 GB/s** (40 fps × ~45.6 MiB/frame preprocess model). |
| **Rated BW (example)** | **~3.9 GB/s** (PCIe 3.0 ×4)—sufficient headroom for that slice. |
| **Roofline / bottleneck** | PCIe **OK** for **~2 GB/s** streaming; **512 GFLOP/s** at **~0.955 AI** needs **~536 GB/s** on-chip operand delivery—**local memory + AXI4-Stream internally**, else **PCIe-bound** at **~few GFLOP/s** from host streaming alone. |
| **Host** | **PC with PCIe** (Ryzen-class baseline); **FPGA SoC** optional for integrated PL. |

---

*SPI/I²C remain valuable for **sensor/control** paths in a larger system; the **datapath** for this gesture pipeline should use **PCIe** (or **AXI4-Stream** entirely on-chip) for efficiency.*
