# M2 Simulation Reproducibility Guide

Sign-Language Gesture Recognition Accelerator — Milestone 2

---

## 1. Tool requirements

| Tool | Version used | Install |
|---|---|---|
| **Icarus Verilog** (`iverilog` / `vvp`) | 12.0 (devel) s20150603-1110-g18392a46 | https://bleyer.org/icarus/ (Windows installer) or `brew install icarus-verilog` / `apt install iverilog` |
| **Python** | 3.9.13 | https://www.python.org/downloads/ |
| **matplotlib** | 3.8.0 | `pip install matplotlib==3.8.0` |
| **numpy** | 1.26.0 | `pip install numpy==1.26.0` |

No other simulators (ModelSim, Vivado XSIM, VCS) are required. All commands below use the free Icarus Verilog + vvp flow.

---

## 2. Repository layout (M2 additions)

```
project/m2/
├── rtl/
│   ├── compute_core.sv      ← BGR-to-gray + threshold compute engine
│   └── interface.sv         ← AXI4-Stream wrapper (PCIe DMA ↔ compute_core)
├── tb/
│   ├── tb_compute_core.sv   ← compute core testbench (8 representative vectors)
│   └── tb_interface.sv      ← interface testbench (AXI4-Stream protocol check)
├── sim/
│   ├── compute_core_run.log ← simulation transcript (PASS line inside)
│   ├── interface_run.log    ← simulation transcript (PASS line inside)
│   ├── waveform.png         ← annotated pipeline waveform (compute_core)
│   └── plot_waveform.py     ← Python script that generated waveform.png
├── precision.md             ← numerical format choice + error analysis
└── README.md                ← this file
```

---

## 3. How to reproduce — compute core simulation

Run all commands from the **repository root** (the folder that contains `project/`).

### Step 1 — compile

```bash
iverilog -g2012 -DDUMP_VCD \
    -o project/m2/sim/sim_compute_core.out \
    project/m2/tb/tb_compute_core.sv \
    project/m2/rtl/compute_core.sv
```

On Windows PowerShell (no line continuation):

```powershell
iverilog -g2012 -DDUMP_VCD -o "project/m2/sim/sim_compute_core.out" "project/m2/tb/tb_compute_core.sv" "project/m2/rtl/compute_core.sv"
```

Expected: no output, exit code 0.

### Step 2 — simulate

```bash
cd project/m2/sim
vvp sim_compute_core.out | tee compute_core_run.log
```

Expected final lines in `compute_core_run.log`:

```
PASS -- all 8 vectors matched expected output
```

### Step 3 — regenerate waveform (optional)

The waveform PNG is already committed. To regenerate it from the VCD produced in Step 2:

```bash
cd project/m2/sim
python plot_waveform.py
```

Requires matplotlib 3.8.0 and numpy 1.26.0 (see §1). Writes `sim/waveform.png`.

---

## 4. How to reproduce — interface simulation

### Step 1 — compile

```bash
iverilog -g2012 -DDUMP_VCD \
    -o project/m2/sim/sim_interface.out \
    project/m2/tb/tb_interface.sv \
    project/m2/rtl/interface.sv \
    project/m2/rtl/compute_core.sv
```

PowerShell one-liner:

```powershell
iverilog -g2012 -DDUMP_VCD -o "project/m2/sim/sim_interface.out" "project/m2/tb/tb_interface.sv" "project/m2/rtl/interface.sv" "project/m2/rtl/compute_core.sv"
```

### Step 2 — simulate

```bash
cd project/m2/sim
vvp sim_interface.out | tee interface_run.log
```

Expected final line in `interface_run.log`:

```
PASS -- all interface checks passed
```

---

## 5. Deviations from the M1 plan

### 5a. Interface: PCIe → AXI4-Stream RTL implementation

**M1 selection:** PCIe (host ↔ accelerator link, `project/m1/interface_selection.md`).

**M2 RTL:** `interface.sv` implements **AXI4-Stream** (ARM IHI0051B), not a raw PCIe endpoint.

**Reason — no change in intent, only in abstraction level:**
M1 interface_selection.md §1 explicitly states: *"Internal RTL can still use AXI4-Stream between PCIe DMA engines and compute arrays (standard Xilinx/Intel patterns)."* Implementing a full PCIe endpoint (PHY + link layer + transaction layer) in synthesizable RTL is out of scope for M2; real PCIe endpoint IP is always a hard macro or licensed soft-IP. The `interface.sv` module is the **DMA-to-compute-core bus** — the layer that a PCIe DMA engine (e.g., Xilinx XDMA) presents to the accelerator fabric. The host-facing PCIe link remains the system-level interface; AXI4-Stream is its on-chip projection.

**No update needed to `project/m1/interface_selection.md`** — the M1 document already anticipated this.

### 5b. Module name: `\interface` (escaped identifier)

`interface` is a reserved keyword in SystemVerilog (IEEE 1800). To keep the top-level module name matching the filename (`interface.sv`) while remaining standards-compliant, the module uses the SV escaped identifier syntax: `module \interface (...)`. Instantiate it the same way in testbenches: `\interface  dut (...)`. This compiles cleanly under `iverilog -g2012`.

### 5c. Kernel scope — no change

The compute core targets the Phase-1 preprocessing kernel (BGR→Grayscale + in-range threshold), consistent with the M1 profiling conclusion that `cvtColor`, `inRange`, and `bitwise_and` dominate the ~22 s / 10-pass wall time. No scope change.

### 5d. Precision — see `precision.md`

Numerical format is INT8 fixed-point with BT.601 coefficients scaled to ×256. Full error analysis is in `project/m2/precision.md`.
