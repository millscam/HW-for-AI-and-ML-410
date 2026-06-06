#!/usr/bin/env python3
"""M4 final roofline: M1 SW measured point + M4 accelerator (synthesis projection)."""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

BENCH = Path(__file__).resolve().parent
OUT = BENCH / "roofline_final.png"
HW_JSON = BENCH / "hw_results.json"
SW_JSON = BENCH / "sw_results.json"

AI_HIGH = 1.0
AI_SW = 21 / 22
PEAK_GOPS = 0.769
PEAK_BW = 0.769
RIDGE_AI = PEAK_GOPS / PEAK_BW


def main() -> None:
    hw = json.loads(HW_JSON.read_text(encoding="utf-8"))["primary"]
    sw = json.loads(SW_JSON.read_text(encoding="utf-8"))
    p_hw = hw["throughput_gops"]
    p_sw_full = sw["throughput_gops"]
    p_sw_fused = sw["throughput_gops_fused_5p"]

    ai = np.logspace(-1.2, 1.5, 300)
    roof = np.minimum(PEAK_GOPS, ai * PEAK_BW)

    fig, ax = plt.subplots(figsize=(9, 6), dpi=150)
    ax.loglog(ai, roof, color="#2166ac", lw=2.5, label=f"M4 roof ({PEAK_GOPS:.3f} GOPS peak)")
    ax.plot(RIDGE_AI, PEAK_GOPS, "s", color="#2166ac", ms=9)
    ax.axvline(AI_HIGH, color="#888", ls=":", lw=1.2)
    ax.text(
        AI_HIGH * 0.85,
        0.015,
        r"AI$_{\mathrm{high}}$=1.0 (fused kernel)",
        rotation=90,
        va="bottom",
        fontsize=9,
    )

    ax.plot(
        AI_HIGH,
        p_hw,
        "*",
        color="#c45c00",
        ms=18,
        markeredgecolor="black",
        markeredgewidth=0.6,
        zorder=7,
        label=f"M4 accelerator {p_hw:.3f} GOPS @ AI=1.0\n(projected, synthesis signoff)",
    )
    ax.plot(
        AI_SW,
        p_sw_full,
        "o",
        color="#d62728",
        ms=10,
        label=f"M1 SW baseline {p_sw_full:.2f} GOPS @ AI≈0.95\n(archival profile, full preprocess)",
    )
    ax.plot(
        1.0,
        p_sw_fused,
        "D",
        color="#9467bd",
        ms=8,
        label=f"M1 fused-kernel equiv. {p_sw_fused:.3f} GOPS\n(5 FLOP/px, wall fps)",
    )

    ax.annotate(
        "projected\n(post-synth)",
        xy=(AI_HIGH, p_hw),
        xytext=(AI_HIGH * 0.28, p_hw * 2.8),
        arrowprops=dict(arrowstyle="->", color="#c45c00"),
        fontsize=9,
        color="#c45c00",
    )

    ax.set_xlabel("Arithmetic intensity (FLOP/byte)")
    ax.set_ylabel("Attainable performance (GOPS)")
    ax.set_title(
        "M4 roofline — software baseline vs accelerator\n"
        f"(speedup {hw['throughput_frames_per_s']/sw['throughput_frames_per_s']:.2f}× frames/s)"
    )
    ax.set_xlim(0.1, 8)
    ax.set_ylim(0.05, 5)
    ax.grid(True, which="both", ls=":", alpha=0.45)
    ax.legend(loc="upper left", fontsize=8)
    fig.tight_layout()
    fig.savefig(OUT, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
