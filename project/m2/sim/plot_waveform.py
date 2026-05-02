"""
Generate waveform.png from tb_compute_core.vcd.
Plots the key signals of the compute_core BGR->Gray pipeline:
  clk, rst, valid_in, b_in, g_in, r_in, valid_out, gray_out, mask_out
"""

import re
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch

VCD_FILE  = os.path.join(os.path.dirname(__file__), "tb_compute_core.vcd")
OUT_FILE  = os.path.join(os.path.dirname(__file__), "waveform.png")

# ---------------------------------------------------------------------------
# Minimal VCD parser
# ---------------------------------------------------------------------------
def parse_vcd(path):
    signals = {}   # symbol -> name
    widths  = {}   # symbol -> bit-width
    changes = {}   # name   -> [(time, value), ...]

    with open(path) as f:
        lines = f.read().splitlines()

    in_vars = False
    time    = 0

    for line in lines:
        line = line.strip()
        if line.startswith("$var"):
            parts = line.split()
            # $var wire WIDTH SYMBOL NAME ...
            width  = int(parts[2])
            symbol = parts[3]
            name   = parts[4]
            signals[symbol] = name
            widths[symbol]  = width
            changes[name]   = []
        elif line.startswith("#"):
            time = int(line[1:])
        elif line and line[0] in "01xXzZ" and len(line) <= 2:
            val    = line[0]
            symbol = line[1:]
            if symbol in signals:
                name = signals[symbol]
                ival = 0 if val in ("0", "x", "X", "z", "Z") else 1
                changes[name].append((time, ival))
        elif line.startswith("b"):
            parts  = line.split()
            bval   = parts[0][1:]          # strip leading 'b'
            symbol = parts[1]
            if symbol in signals:
                name = signals[symbol]
                if "x" in bval or "z" in bval:
                    ival = 0
                else:
                    ival = int(bval, 2)
                changes[name].append((time, ival))

    return changes

# ---------------------------------------------------------------------------
# Build step-function arrays (time, value) suitable for plt.step
# ---------------------------------------------------------------------------
def to_steps(events, t_max):
    if not events:
        return [0, t_max], [0, 0]
    times  = [0]
    values = [events[0][1]]
    for t, v in events:
        times.append(t)
        values.append(v)
    times.append(t_max)
    values.append(values[-1])
    return times, values

def bus_label(val):
    return f"{val}" if val is not None else "?"

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
def main():
    ch = parse_vcd(VCD_FILE)
    T_MAX = 110_000  # ps (just past $finish at 106 000 ps)

    # Signals to display (name as it appears in VCD, display label)
    SIGS = [
        ("clk",       "clk",       "bit"),
        ("rst",       "rst",       "bit"),
        ("valid_in",  "valid_in",  "bit"),
        ("b_in",      "b_in",      "bus"),
        ("g_in",      "g_in",      "bus"),
        ("r_in",      "r_in",      "bus"),
        ("valid_out", "valid_out", "bit"),
        ("gray_out",  "gray_out",  "bus"),
        ("mask_out",  "mask_out",  "bit"),
    ]

    n     = len(SIGS)
    ROW_H = 1.0          # height per signal row
    GAP   = 0.3          # gap between rows
    fig_h = n * (ROW_H + GAP) + 1.2
    fig, ax = plt.subplots(figsize=(16, fig_h))
    ax.set_xlim(0, T_MAX)
    ax.set_ylim(-0.5, n * (ROW_H + GAP) + 0.2)
    ax.axis("off")
    fig.patch.set_facecolor("#1e1e2e")
    ax.set_facecolor("#1e1e2e")

    # Colour palette
    CLK_COL   = "#a6e3a1"   # green
    RST_COL   = "#f38ba8"   # red
    SIG_COL   = "#89b4fa"   # blue
    BUS_COL   = "#cba6f7"   # lavender
    LABEL_COL = "#cdd6f4"   # light grey
    BG_COL    = "#313244"   # row background

    # X-axis tick marks at each clock edge (period = 10 000 ps)
    CLK_PERIOD = 10_000
    tick_times = list(range(0, T_MAX, CLK_PERIOD))

    for row, (vcd_name, label, kind) in enumerate(SIGS):
        y_base = (n - 1 - row) * (ROW_H + GAP)
        events = ch.get(vcd_name, [])
        times, values = to_steps(events, T_MAX)

        if kind == "bit":
            color = CLK_COL if label == "clk" else (RST_COL if label == "rst" else SIG_COL)
            # Draw background band
            ax.add_patch(FancyBboxPatch((0, y_base - 0.05), T_MAX, ROW_H + 0.1,
                                        boxstyle="round,pad=0", linewidth=0,
                                        facecolor=BG_COL, zorder=0, clip_on=False))
            # Scale 0/1 to y_base / y_base+ROW_H
            ys = [y_base + v * ROW_H * 0.85 for v in values]
            ax.step(times, ys, where="post", color=color, linewidth=1.8, zorder=2)

        else:  # bus — draw as shaded rectangle with value text
            ax.add_patch(FancyBboxPatch((0, y_base - 0.05), T_MAX, ROW_H + 0.1,
                                        boxstyle="round,pad=0", linewidth=0,
                                        facecolor=BG_COL, zorder=0, clip_on=False))
            # Draw bus transitions as filled rectangles
            for i in range(len(times) - 1):
                t0, t1 = times[i], times[i + 1]
                v      = values[i]
                ax.fill_between([t0, t1], [y_base + 0.05, y_base + 0.05],
                                [y_base + ROW_H * 0.85, y_base + ROW_H * 0.85],
                                color=BUS_COL, alpha=0.25, step="post", zorder=1)
                ax.step([t0, t1], [y_base + 0.05, y_base + 0.05],  where="post",
                        color=BUS_COL, linewidth=1.2, zorder=2)
                ax.step([t0, t1], [y_base + ROW_H * 0.85, y_base + ROW_H * 0.85],
                        where="post", color=BUS_COL, linewidth=1.2, zorder=2)
                # Value annotation in the middle of each stable segment
                mid = (t0 + t1) / 2
                if t1 - t0 > 8_000:  # only label wide-enough segments
                    ax.text(mid, y_base + ROW_H * 0.42, str(v),
                            ha="center", va="center", fontsize=7.5,
                            color=LABEL_COL, zorder=3, fontstyle="italic")

        # Signal name label
        ax.text(-2_000, y_base + ROW_H * 0.42, label,
                ha="right", va="center", fontsize=9,
                color=LABEL_COL, fontweight="bold")

    # Clock-edge tick lines
    for t in tick_times:
        ax.axvline(t, color="#45475a", linewidth=0.4, zorder=0, linestyle="--")

    # X-axis time labels
    for t in tick_times[::2]:
        ax.text(t, -0.45, f"{t//1000} ns",
                ha="center", va="top", fontsize=7, color="#7f849c")

    # Pipeline latency annotation arrow
    ax.annotate("",
        xy=(30_000, (n - 1 - 6) * (ROW_H + GAP) + ROW_H * 0.42),  # valid_out row
        xytext=(10_000, (n - 1 - 2) * (ROW_H + GAP) + ROW_H * 0.42),  # valid_in row
        arrowprops=dict(arrowstyle="->", color="#f9e2af", lw=1.5,
                        connectionstyle="arc3,rad=-0.3"))
    ax.text(22_000, (n - 1 - 4) * (ROW_H + GAP) + ROW_H * 0.42 + 0.3,
            "2-cycle latency", fontsize=8, color="#f9e2af", ha="center")

    # Title
    fig.text(0.5, 0.97,
             "compute_core — BGR→Gray + threshold  |  tb_compute_core.sv  |  100 MHz clock",
             ha="center", va="top", fontsize=11, color=LABEL_COL, fontweight="bold")
    fig.text(0.5, 0.93,
             "Representative pixel stream: black · pure R/G/B · white · skin-tone · dark background · mid-gray",
             ha="center", va="top", fontsize=8.5, color="#7f849c")

    plt.tight_layout(rect=[0.07, 0.03, 1.0, 0.92])
    plt.savefig(OUT_FILE, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
    print(f"Saved: {OUT_FILE}")

if __name__ == "__main__":
    main()
