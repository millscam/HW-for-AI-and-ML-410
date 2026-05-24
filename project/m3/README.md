# M3 — Integration and Synthesis

Sign-Language Gesture Recognition Accelerator — Milestone 3

---

## 1. File catalog

| Path | Description |
|------|-------------|
| `README.md` | This file — M3 submission index and reproduction guide |
| `rtl/top.sv` | Integrated top module: instantiates `interface.sv` and `compute_core`, wires all inter-module signals |
| `rtl/interface.sv` | AXI4-Stream wrapper with core-facing ports (no internal `compute_core` instance) |
| `tb/tb_top.sv` | End-to-end co-simulation testbench; drives the design only through the AXI4-Stream host interface |
| `sim/cosim_run.log` | Full co-simulation transcript including the PASS/FAIL verdict |
| `sim/cosim_waveform.png` | Annotated end-to-end waveform: host write, internal compute, host read |
| `sim/plot_cosim_waveform.py` | Script that generates `cosim_waveform.png` from `tb_top.vcd` |
| `synth/config.json` | OpenLane 2 configuration (clock period, design name, source files, constraints) |
| `synth/openlane_run.log` | Full OpenLane 2 stdout/stderr from the synthesis run |
| `synth/timing_report.txt` | Post-PNR STA report: worst setup/hold slack per corner |
| `synth/area_report.txt` | Cell area and count by type (Yosys stat + OpenROAD final) |
| `synth/power_report.txt` | Power estimate from OpenROAD (internal, switching, leakage, total) |
| `synth/critical_path.md` | Critical path: start/end points, logic stages, and analysis |
| `synthesis_notes.md` | Narrative (≥500 words): what synthesized, what did not, scope status |

**Shared M2 RTL:** `project/m2/rtl/compute_core.sv` (referenced by `top.sv` and the co-simulation compile line).

---

## 2. Co-simulation reproduction

Run all commands from the **repository root** (the folder that contains both `project/` and `codefest/`).

| Tool | Version used |
|------|----------------|
| **Icarus Verilog** (`iverilog` / `vvp`) | 12.0 (devel) s20150603-1110-g18392a46 |
| **Python** + **matplotlib** | Same as M2 — see `project/m2/README.md` §1 |

### Compile and simulate

```bash
iverilog -g2012 -DDUMP_VCD \
    -o project/m3/sim/sim_top.out \
    project/m3/tb/tb_top.sv \
    project/m3/rtl/top.sv \
    project/m3/rtl/interface.sv \
    project/m2/rtl/compute_core.sv

cd project/m3/sim
vvp sim_top.out | tee cosim_run.log
```

### Optional waveform plot

```bash
cd project/m3/sim
python plot_cosim_waveform.py
```

Writes `tb_top.vcd` during simulation and `cosim_waveform.png` after plotting.

**Expected final line in `cosim_run.log`:**

```
PASS -- all end-to-end checks passed
```

---

## 3. Synthesis reproduction

| Item | Value |
|------|--------|
| **Tool** | OpenLane 2 v2.3.10 |
| **PDK** | `sky130A` (sky130_fd_sc_hd) |
| **Configuration** | `project/m3/synth/config.json` |
| **RTL synthesized** | `codefest/cf07/hdl/synth_top.sv` (2-lane compute core; see `synthesis_notes.md` for scope) |

Run on a Linux host (or WSL2) with OpenLane 2 and Sky130 installed. Set `PDK_ROOT` to your Sky130 PDK tree.

```bash
cd project/m3
python3 -m openlane synth/config.json
```

The submitted `openlane_run.log` is the full flow log from OpenLane Run 3 (2-lane `synth_top`, 13 ns clock, `MAX_FANOUT_CONSTRAINT=8`). Reports in `synth/` were derived from that run’s artifacts under `codefest/cf07/synth/`.

---

## 4. Related documents

| Document | Location |
|----------|----------|
| M1 software baseline | `project/m1/sw_baseline.md` |
| M2 simulation guide | `project/m2/README.md` |
| Synthesis narrative | `project/m3/synthesis_notes.md` |
