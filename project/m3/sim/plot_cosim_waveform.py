"""
plot_cosim_waveform.py
Sign-Language Gesture Recognition Accelerator — M3

Reads tb_top.vcd produced by the co-simulation (iverilog + vvp) and
renders an annotated digital timing diagram showing:
  Region 1 — Host-side write  : s_tvalid, s_tready, s_tdata
  Region 2 — Internal compute : core pipeline valid signals
  Region 3 — Host-side read   : m_tvalid, m_tready, m_tdata, m_tlast

Usage (run from project/m3/sim/):
    python plot_cosim_waveform.py

Requires: matplotlib >= 3.8.0, numpy >= 1.26.0
Output  : cosim_waveform.png  (written to the same directory as this script)
"""

import os
import sys
import re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# ---------------------------------------------------------------------------
# VCD parser
# ---------------------------------------------------------------------------

def parse_vcd(path):
    """
    Minimal VCD parser for iverilog output.
    Returns:
        vars_by_id  : {id_str: {'name': str, 'full_name': str, 'width': int}}
        changes     : {id_str: [(time_ps: int, value: int), ...]}
        timescale_ps: int  (time unit in picoseconds)
    """
    vars_by_id   = {}
    changes      = {}
    scope_stack  = []
    timescale_ps = 1  # default 1 ps
    current_time = 0

    with open(path, "r") as f:
        content = f.read()

    tokens = content.split()
    n      = len(tokens)
    i      = 0

    while i < n:
        t = tokens[i]

        # ── $timescale ──────────────────────────────────────────────────────
        if t == "$timescale":
            i += 1
            ts_str = ""
            while i < n and tokens[i] != "$end":
                ts_str += tokens[i]
                i += 1
            i += 1  # skip $end
            # Parse e.g. "1ns/1ps" or "1ns"
            m = re.search(r"(\d+)\s*(ps|ns|us|ms|s)", ts_str)
            if m:
                val  = int(m.group(1))
                unit = m.group(2)
                mult = {"ps": 1, "ns": 1000, "us": 1_000_000,
                        "ms": 1_000_000_000, "s": 1_000_000_000_000}
                timescale_ps = val * mult.get(unit, 1)

        # ── $scope ──────────────────────────────────────────────────────────
        elif t == "$scope":
            scope_name = tokens[i + 2] if i + 2 < n else ""
            scope_stack.append(scope_name)
            i += 4  # $scope module name $end

        # ── $upscope ────────────────────────────────────────────────────────
        elif t == "$upscope":
            if scope_stack:
                scope_stack.pop()
            i += 2  # $upscope $end

        # ── $var ────────────────────────────────────────────────────────────
        elif t == "$var":
            # $var type width id name [$end | [n:m] $end]
            if i + 4 < n:
                width  = int(tokens[i + 2])
                vid    = tokens[i + 3]
                vname  = tokens[i + 4]
                scope  = ".".join(scope_stack)
                full   = (scope + "." + vname) if scope else vname
                vars_by_id[vid]  = {"name": vname, "full_name": full, "width": width}
                changes[vid]     = []
            i += 5
            while i < n and tokens[i] != "$end":
                i += 1
            i += 1  # skip $end

        # ── $enddefinitions / other $-commands ──────────────────────────────
        elif t.startswith("$"):
            i += 1
            while i < n and tokens[i] != "$end":
                i += 1
            if i < n:
                i += 1  # skip $end

        # ── timestamp ───────────────────────────────────────────────────────
        elif t.startswith("#") and len(t) > 1:
            current_time = int(t[1:])
            i += 1

        # ── bus value: b<binary> <id> ────────────────────────────────────────
        elif (t.startswith("b") or t.startswith("B")) and len(t) > 1:
            val_str = t[1:].lower().replace("x", "0").replace("z", "0")
            vid     = tokens[i + 1] if i + 1 < n else None
            if vid and vid in changes:
                val = int(val_str, 2) if val_str else 0
                changes[vid].append((current_time, val))
            i += 2

        # ── scalar value: <0|1|x|z><id> ─────────────────────────────────────
        elif t[0] in "01xzXZ" and len(t) >= 2:
            val = 1 if t[0] == "1" else 0
            vid = t[1:]
            if vid in changes:
                changes[vid].append((current_time, val))
            i += 1

        else:
            i += 1

    return vars_by_id, changes, timescale_ps


def find_id(vars_by_id, target_name):
    """Return VCD id for the first variable whose full_name ends with target_name."""
    for vid, info in vars_by_id.items():
        if info["full_name"].endswith(target_name):
            return vid
    return None


def to_step(changes_list, end_time):
    """Convert a list of (time, value) to step-plot arrays (times, values)."""
    if not changes_list:
        return np.array([0, end_time]), np.array([0, 0])
    times  = [c[0] for c in changes_list]
    values = [c[1] for c in changes_list]
    # Extend to end_time
    times.append(end_time)
    values.append(values[-1])
    return np.array(times, dtype=float), np.array(values, dtype=float)


def draw_bus(ax, changes_list, end_time, label, color, text_fmt=None, y_base=0, height=0.6):
    """Draw a bus signal as a filled step with hex value labels."""
    if not changes_list:
        return
    prev_t, prev_v = changes_list[0]
    for k in range(1, len(changes_list) + 1):
        t_end = changes_list[k][0] if k < len(changes_list) else end_time
        mid   = (prev_t + t_end) / 2
        ax.fill_between([prev_t, t_end], y_base, y_base + height,
                        color=color, alpha=0.35, step="pre")
        ax.hlines([y_base, y_base + height], prev_t, t_end, colors=color, linewidths=1)
        if text_fmt and (t_end - prev_t) > 2:
            ax.text(mid, y_base + height / 2, text_fmt(prev_v),
                    ha="center", va="center", fontsize=6.5, color="black")
        if k < len(changes_list):
            prev_t, prev_v = changes_list[k]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VCD_PATH   = os.path.join(SCRIPT_DIR, "tb_top.vcd")
OUT_PATH   = os.path.join(SCRIPT_DIR, "cosim_waveform.png")

if not os.path.exists(VCD_PATH):
    print(f"ERROR: {VCD_PATH} not found.")
    print("Run the co-simulation first:")
    print("  iverilog -g2012 -DDUMP_VCD -o sim/sim_top.out "
          "tb/tb_top.sv rtl/top.sv rtl/interface.sv ../m2/rtl/compute_core.sv")
    print("  cd sim && vvp sim_top.out | tee cosim_run.log")
    sys.exit(1)

print(f"Parsing {VCD_PATH} ...")
vars_by_id, changes, timescale_ps = parse_vcd(VCD_PATH)
ns_per_unit = timescale_ps / 1000  # convert to ns

# Locate signals we want to plot
want = {
    "clk":           "tb_top.clk",
    "rst":           "tb_top.rst",
    "s_tvalid":      "tb_top.s_tvalid",
    "s_tready":      "tb_top.s_tready",
    "s_tdata":       "tb_top.s_tdata",
    "s_tuser":       "tb_top.s_tuser",
    "s_tlast":       "tb_top.s_tlast",
    "m_tvalid":      "tb_top.m_tvalid",
    "m_tready":      "tb_top.m_tready",
    "m_tdata":       "tb_top.m_tdata",
    "m_tlast":       "tb_top.m_tlast",
    # Internal: pipeline valids (inside dut hierarchy)
    "core_valid_in": "core_valid_in",
    "core_valid_out":"valid_out",
}

sig = {}
for key, suffix in want.items():
    vid = find_id(vars_by_id, suffix)
    if vid:
        sig[key] = [(t * ns_per_unit, v) for t, v in changes[vid]]
    else:
        sig[key] = []

# Determine plot time range (ns)
all_times = [t for lst in sig.values() for t, _ in lst]
t_max_ns  = max(all_times) if all_times else 200.0

# Trim to the interesting window: reset release through ~5 cycles after last output
# Reset releases around t=20 ns (2 cycles × 10 ns).
# Last output appears around t = (2 reset + 7 input + 2 pipe) × 10 = 110 ns.
# We plot from t=0 to t_max.

# ---------------------------------------------------------------------------
# Figure layout: 9 rows
# ---------------------------------------------------------------------------
ROW_LABELS  = ["clk", "rst", "s_tvalid\ns_tready", "s_tdata\n[23:0]",
               "s_tlast", "core\nvalid_in", "core\nvalid_out",
               "m_tvalid\nm_tready", "m_tdata\n[8:0]  m_tlast"]
N_ROWS      = len(ROW_LABELS)
ROW_HEIGHT  = 0.7   # normalized units per row
GAP         = 0.35

fig_h = N_ROWS * (ROW_HEIGHT + GAP) + 1.5
fig, axes = plt.subplots(N_ROWS, 1, figsize=(14, fig_h),
                         gridspec_kw={"hspace": 0.05})
fig.patch.set_facecolor("#f8f8f8")

for ax in axes:
    ax.set_xlim(0, t_max_ns)
    ax.set_ylim(-0.1, 1.1)
    ax.set_yticks([])
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.tick_params(left=False, bottom=False)

def label_ax(ax, txt):
    ax.set_ylabel(txt, fontsize=7, rotation=0, ha="right", va="center",
                  labelpad=4, fontfamily="monospace")

# helper: draw a 1-bit signal
def draw_1bit(ax, sig_list, color="#2266cc"):
    t, v = to_step(sig_list, t_max_ns)
    t_ns = t  # already in ns
    ax.step(t_ns, v, where="post", color=color, linewidth=1.5)
    ax.fill_between(t_ns, 0, v, step="post", color=color, alpha=0.18)

# Row 0 — clk
ax = axes[0]
label_ax(ax, ROW_LABELS[0])
draw_1bit(ax, sig.get("clk", []), color="#555555")

# Row 1 — rst
ax = axes[1]
label_ax(ax, ROW_LABELS[1])
draw_1bit(ax, sig.get("rst", []), color="#cc2222")

# Row 2 — s_tvalid / s_tready (overlay)
ax = axes[2]
label_ax(ax, ROW_LABELS[2])
draw_1bit(ax, sig.get("s_tvalid", []), color="#2266cc")
draw_1bit(ax, sig.get("s_tready", []), color="#22aa44")
ax.plot([], [], color="#2266cc", label="s_tvalid", linewidth=1.5)
ax.plot([], [], color="#22aa44", label="s_tready", linewidth=1.5)
ax.legend(fontsize=6, loc="upper right", framealpha=0.6)

# Row 3 — s_tdata bus
ax = axes[3]
label_ax(ax, ROW_LABELS[3])
draw_bus(ax, sig.get("s_tdata", []), t_max_ns,
         label="s_tdata", color="#2266cc",
         text_fmt=lambda v: f"#{v:06X}")

# Row 4 — s_tlast
ax = axes[4]
label_ax(ax, ROW_LABELS[4])
draw_1bit(ax, sig.get("s_tlast", []), color="#aa6600")

# Row 5 — core_valid_in (internal pipeline signal)
ax = axes[5]
label_ax(ax, ROW_LABELS[5])
draw_1bit(ax, sig.get("core_valid_in", []), color="#884499")

# Row 6 — core_valid_out (from compute_core, internal)
ax = axes[6]
label_ax(ax, ROW_LABELS[6])
draw_1bit(ax, sig.get("core_valid_out", []), color="#448844")

# Row 7 — m_tvalid / m_tready
ax = axes[7]
label_ax(ax, ROW_LABELS[7])
draw_1bit(ax, sig.get("m_tvalid", []), color="#cc6600")
draw_1bit(ax, sig.get("m_tready", []), color="#22aa44")
ax.plot([], [], color="#cc6600", label="m_tvalid", linewidth=1.5)
ax.plot([], [], color="#22aa44", label="m_tready", linewidth=1.5)
ax.legend(fontsize=6, loc="upper right", framealpha=0.6)

# Row 8 — m_tdata bus + m_tlast overlay
ax = axes[8]
label_ax(ax, ROW_LABELS[8])
draw_bus(ax, sig.get("m_tdata", []), t_max_ns,
         label="m_tdata", color="#cc6600",
         text_fmt=lambda v: f"g={v & 0xFF:3d} m={v >> 8:d}")
draw_1bit(ax, sig.get("m_tlast", []), color="#aa0066")
ax.plot([], [], color="#aa0066", label="m_tlast", linewidth=1.5)
ax.legend(fontsize=6, loc="upper right", framealpha=0.6)

# X-axis ticks on last row only
axes[-1].tick_params(bottom=True)
axes[-1].set_xlabel("Time (ns)", fontsize=8)
axes[-1].spines["bottom"].set_visible(True)
axes[-1].xaxis.set_major_locator(plt.MultipleLocator(10))
axes[-1].xaxis.set_minor_locator(plt.MultipleLocator(5))
axes[-1].tick_params(axis="x", labelsize=7)

# ---------------------------------------------------------------------------
# Annotate 3 regions  (approximate time windows based on 10 ns clock)
# ---------------------------------------------------------------------------
# Region boundaries (ns): reset=0-20, write=20-90, compute=90-110, read=110-end
# (These are detected dynamically from the signal data if possible.)

def first_high(sig_list):
    for t, v in sig_list:
        if v == 1:
            return t
    return None

def last_high(sig_list):
    last = None
    for t, v in sig_list:
        if v == 1:
            last = t
    return last

t_write_start  = first_high(sig.get("s_tvalid", [])) or 20
t_write_end    = last_high(sig.get("s_tvalid", []))  or 100
# write_end: find when s_tvalid first goes low after the burst
for t, v in sig.get("s_tvalid", []):
    if t > t_write_start and v == 0:
        t_write_end = t
        break

t_read_start   = first_high(sig.get("m_tvalid", [])) or t_write_end
t_read_end     = last_high(sig.get("m_tvalid", []))   or t_max_ns
for t, v in sig.get("m_tvalid", []):
    if t > t_read_start and v == 0:
        t_read_end = t
        break

t_compute_start = t_write_end
t_compute_end   = t_read_start

region_alpha = 0.06
for ax in axes:
    # Region 1 — Host write (blue)
    ax.axvspan(t_write_start, t_write_end,   color="#2266cc", alpha=region_alpha)
    # Region 2 — Internal compute (purple)
    ax.axvspan(t_compute_start, t_compute_end, color="#884499", alpha=region_alpha)
    # Region 3 — Host read (orange)
    ax.axvspan(t_read_start,  t_read_end,    color="#cc6600", alpha=region_alpha)

# Annotation labels on the top axis
axes[0].text((t_write_start + t_write_end) / 2,   1.05, "① Host write",
             ha="center", va="bottom", fontsize=8, color="#2266cc",
             fontweight="bold", transform=axes[0].transData)
axes[0].text((t_compute_start + t_compute_end) / 2, 1.05, "② Compute",
             ha="center", va="bottom", fontsize=8, color="#884499",
             fontweight="bold", transform=axes[0].transData)
axes[0].text((t_read_start + t_read_end) / 2,     1.05, "③ Host read",
             ha="center", va="bottom", fontsize=8, color="#cc6600",
             fontweight="bold", transform=axes[0].transData)

# ---------------------------------------------------------------------------
# Title and save
# ---------------------------------------------------------------------------
fig.suptitle(
    "M3 End-to-End Co-Simulation — Sign-Language Accelerator\n"
    "AXI4-Stream host write → compute_core pipeline → AXI4-Stream host read",
    fontsize=10, y=0.995
)

plt.savefig(OUT_PATH, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
print(f"Waveform written to {OUT_PATH}")
