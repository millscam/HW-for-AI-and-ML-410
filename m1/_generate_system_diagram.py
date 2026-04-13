"""One-off generator for project/m1/system_diagram.png — run: python _generate_system_diagram.py"""
from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle

OUT = Path(__file__).resolve().parent / "system_diagram.png"


def main() -> None:
    fig, ax = plt.subplots(figsize=(11, 6.2), dpi=150)
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 6.2)
    ax.axis("off")
    fig.patch.set_facecolor("white")

    # --- Host ---
    host = FancyBboxPatch(
        (0.35, 2.0),
        2.4,
        2.2,
        boxstyle="round,pad=0.08,rounding_size=0.15",
        facecolor="#E3F2FD",
        edgecolor="#1565C0",
        linewidth=2,
    )
    ax.add_patch(host)
    ax.text(1.55, 3.85, "Host", ha="center", va="center", fontsize=13, fontweight="bold", color="#0D47A1")
    ax.text(
        1.55,
        3.15,
        "x64 CPU\n(video decode,\nOpenCV, TensorFlow,\norchestration)",
        ha="center",
        va="center",
        fontsize=8.5,
        color="#333",
        linespacing=1.35,
    )

    # --- Interface (PCIe) ---
    iface = FancyBboxPatch(
        (3.15, 2.35),
        1.55,
        1.5,
        boxstyle="round,pad=0.06,rounding_size=0.1",
        facecolor="#FFF3E0",
        edgecolor="#E65100",
        linewidth=2,
    )
    ax.add_patch(iface)
    ax.text(3.92, 3.35, "Interface", ha="center", va="center", fontsize=12, fontweight="bold", color="#BF360C")
    ax.text(3.92, 2.75, "PCIe\n(DMA)", ha="center", va="center", fontsize=9, color="#5D4037")

    # Arrows host <-> interface
    ax.add_patch(
        FancyArrowPatch(
            (2.78, 3.1),
            (3.12, 3.1),
            arrowstyle="<->",
            mutation_scale=14,
            linewidth=2,
            color="#1565C0",
        )
    )
    ax.add_patch(
        FancyArrowPatch(
            (4.72, 3.1),
            (5.05, 3.1),
            arrowstyle="<->",
            mutation_scale=14,
            linewidth=2,
            color="#1565C0",
        )
    )

    # --- Chiplet boundary (dashed outer box) ---
    chiplet_x, chiplet_y = 5.0, 0.55
    chiplet_w, chiplet_h = 5.65, 5.1
    boundary = Rectangle(
        (chiplet_x, chiplet_y),
        chiplet_w,
        chiplet_h,
        fill=False,
        linestyle=(0, (8, 5)),
        linewidth=2.8,
        edgecolor="#37474F",
    )
    ax.add_patch(boundary)
    ax.text(
        chiplet_x + chiplet_w / 2,
        chiplet_y + chiplet_h - 0.28,
        "Chiplet boundary",
        ha="center",
        va="top",
        fontsize=11,
        fontweight="bold",
        color="#263238",
    )

    # --- Inside chiplet: on-chip memory + compute engine ---
    mem = FancyBboxPatch(
        (5.45, 3.15),
        2.35,
        1.85,
        boxstyle="round,pad=0.08,rounding_size=0.12",
        facecolor="#E8F5E9",
        edgecolor="#2E7D32",
        linewidth=2,
    )
    ax.add_patch(mem)
    ax.text(
        6.62,
        4.55,
        "On-chip memory",
        ha="center",
        va="center",
        fontsize=12,
        fontweight="bold",
        color="#1B5E20",
    )
    ax.text(
        6.62,
        3.65,
        "SRAM / scratchpads\n(weights, tiles,\nactivations)",
        ha="center",
        va="center",
        fontsize=8.5,
        color="#333",
        linespacing=1.35,
    )

    comp = FancyBboxPatch(
        (8.15, 3.15),
        2.15,
        1.85,
        boxstyle="round,pad=0.08,rounding_size=0.12",
        facecolor="#F3E5F5",
        edgecolor="#6A1B9A",
        linewidth=2,
    )
    ax.add_patch(comp)
    ax.text(
        9.22,
        4.55,
        "Compute engine",
        ha="center",
        va="center",
        fontsize=12,
        fontweight="bold",
        color="#4A148C",
    )
    ax.text(
        9.22,
        3.55,
        "Fused preprocess\n+ CNN / RNN\n(PE array)",
        ha="center",
        va="center",
        fontsize=8.5,
        color="#333",
        linespacing=1.35,
    )

    # Memory <-> Compute (wide internal path)
    ax.add_patch(
        FancyArrowPatch(
            (7.82, 4.05),
            (8.12, 4.05),
            arrowstyle="<->",
            mutation_scale=15,
            linewidth=2.2,
            color="#2E7D32",
        )
    )
    ax.text(7.97, 4.35, "wide\non-chip", ha="center", va="bottom", fontsize=7.5, color="#2E7D32")

    # Subtitle
    ax.text(
        5.5,
        0.2,
        "Sign-language gesture pipeline — high-level accelerator integration (M1)",
        ha="left",
        va="bottom",
        fontsize=9,
        color="#666",
    )

    fig.tight_layout()
    fig.savefig(OUT, bbox_inches="tight", facecolor="white", edgecolor="none")
    plt.close(fig)
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
