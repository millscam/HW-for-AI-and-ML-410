#!/usr/bin/env python3
"""
M4 benchmark collection: M1 SW baseline + HW synth_top (synthesis + Icarus cycles).

Writes:
  bench/sw_results.json
  bench/hw_results.json
  bench/benchmark_data.csv
"""
from __future__ import annotations

import csv
import json
import re
import subprocess
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent
M4_ROOT = BENCH_DIR.parent
REPO_ROOT = M4_ROOT.parents[1]
SYNTH_TOP = M4_ROOT / "rtl" / "synth_top.sv"
TB_BENCH = BENCH_DIR / "tb_bench_synth_top.sv"
CF02_TXT = REPO_ROOT / "codefest" / "cf02" / "profiling" / "project_profile.txt"

H, W = 1080, 1920
P = H * W
FLOPS_PER_PIXEL = 5
LANES = 2
F_CLK_MHZ = 76.9
CLK_PERIOD_NS = 13.0
BYTES_PER_CYCLE = 10.0
POWER_W = 2.0222e-3
SW_LABEL = (
    "M1 archival (one cProfile session over 10 sequential passes; "
    "not median-of-10 independent wall-clock runs)"
)


def load_m1_archival() -> dict:
    wall_s = 22.035
    frames = 880
    ops_per_frame = 43_545_600
    bytes_per_frame = 45_619_200
    ms_per_frame = 1000.0 * wall_s / frames
    fps = frames / wall_s
    gops = ops_per_frame * frames / wall_s / 1e9
    gbs = bytes_per_frame * frames / wall_s / 1e9

    t_cvt = 0.6992
    t_inrange = 4.2616 / 2.0
    t_kernel = t_cvt + t_inrange
    fps_kernel = frames / t_kernel
    gops_kernel = 11 * P * frames / t_kernel / 1e9

    return {
        "source": "codefest/cf02/profiling/project_profile.txt",
        "label": SW_LABEL,
        "measurement_note": (
            "22.035 s total for 10 passes in one profile run (880 frames). "
            "See project/m1/sw_baseline.md for median-of-10 requirement."
        ),
        "platform": "AMD Ryzen 9 4900HS, Windows 11, Python 3.9.13",
        "workload": "Phase-1 preprocess: VideoCapture.read + handsegment + cvtColor",
        "frames_total": frames,
        "frame_size": f"{H}x{W}",
        "execution_time_ms_total": round(wall_s * 1000, 3),
        "execution_time_ms_per_frame": round(ms_per_frame, 3),
        "throughput_frames_per_s": round(fps, 4),
        "throughput_gops": round(gops, 4),
        "throughput_gops_fused_5p": round(FLOPS_PER_PIXEL * P * fps / 1e9, 4),
        "arithmetic_intensity_flop_per_byte": round(21 / 22, 4),
        "implied_dram_gbs": round(gbs, 4),
        "memory_rss_mb": None,
        "kernel_matched_subset": {
            "execution_time_ms_total": round(t_kernel * 1000, 3),
            "throughput_frames_per_s": round(fps_kernel, 2),
            "throughput_gops": round(gops_kernel, 4),
            "arithmetic_intensity_flop_per_byte": 1.0,
        },
    }


def run_icarus_extrapolation() -> dict:
    out_exe = BENCH_DIR / "bench_synth_top.out"
    if not SYNTH_TOP.is_file():
        return {"error": "synth_top.sv missing", "label": "unavailable"}

    try:
        subprocess.run(
            [
                "iverilog",
                "-g2012",
                "-o",
                str(out_exe),
                str(TB_BENCH),
                str(SYNTH_TOP),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        proc = subprocess.run(
            ["vvp", str(out_exe)],
            check=True,
            capture_output=True,
            text=True,
            cwd=str(BENCH_DIR),
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        return {"error": str(e), "label": "unavailable"}

    log = proc.stdout + proc.stderr
    m_pairs = re.search(r"M4_BENCH N_PAIRS=(\d+) cycles=(\d+)", log)
    m_period = re.search(r"M4_BENCH period_ns=(\d+)", log)
    if not m_pairs:
        return {"error": "parse failed", "log": log[-500:], "label": "unavailable"}

    n_pairs = int(m_pairs.group(1))
    cycles_rep = int(m_pairs.group(2))
    period_ns = float(m_period.group(1)) if m_period else CLK_PERIOD_NS

    cycles_per_pair = cycles_rep / n_pairs
    pairs_per_frame = P // 2
    cycles_frame = int(cycles_per_pair * pairs_per_frame) + 2
    time_frame_s = cycles_frame * period_ns * 1e-9
    fps = 1.0 / time_frame_s
    gops = FLOPS_PER_PIXEL * P * fps / 1e9

    return {
        "source": "Icarus cycle benchmark (tb_bench_synth_top.sv)",
        "label": "cycle-measured (sim) + extrapolation to full frame",
        "rtl": str(SYNTH_TOP.relative_to(REPO_ROOT)),
        "representative_n_pairs": n_pairs,
        "representative_cycles": cycles_rep,
        "cycles_per_pair_observed": round(cycles_per_pair, 4),
        "cycles_per_frame_extrapolated": cycles_frame,
        "clk_period_ns": period_ns,
        "f_clk_mhz": round(1000.0 / period_ns, 2),
        "execution_time_ms_per_frame": round(time_frame_s * 1000, 4),
        "throughput_frames_per_s": round(fps, 3),
        "throughput_gops": round(gops, 4),
        "arithmetic_intensity_flop_per_byte": 1.0,
        "implied_stream_gbs": round(BYTES_PER_CYCLE * (1000.0 / period_ns) / 1000.0, 4),
        "extrapolation": (
            f"{cycles_rep} cycles for {n_pairs} pairs; "
            f"cycles/frame = ({cycles_rep}/{n_pairs})*(P/2)+2 = {cycles_frame} @ {period_ns} ns."
        ),
    }


def projected_from_synthesis() -> dict:
    fps = F_CLK_MHZ * 1e6 * LANES / P
    ms_per_frame = 1000.0 / fps
    gops = FLOPS_PER_PIXEL * LANES * F_CLK_MHZ / 1000.0
    energy_uj = POWER_W / fps * 1e6

    return {
        "source": "project/m4/synth/ (OpenLane RUN_2026-05-22_05-04-01)",
        "label": "projected (post-synthesis f_clk, 2 lanes, 1 result/cycle)",
        "dut": "synth_top (project/m4/rtl/synth_top.sv)",
        "clk_period_ns": CLK_PERIOD_NS,
        "f_clk_mhz": F_CLK_MHZ,
        "lanes": LANES,
        "projection_formula": "fps = f_clk * lanes / (H*W); GOPS = 5 * lanes * f_clk_MHz / 1000",
        "throughput_frames_per_s": round(fps, 3),
        "execution_time_ms_per_frame": round(ms_per_frame, 4),
        "throughput_gops": round(gops, 4),
        "arithmetic_intensity_flop_per_byte": 1.0,
        "implied_stream_gbs": round(BYTES_PER_CYCLE * F_CLK_MHZ / 1000.0, 4),
        "power_w": POWER_W,
        "power_source": "project/m4/synth/power_report.txt",
        "energy_uj_per_frame": round(energy_uj, 3),
    }


def write_csv(sw: dict, hw_proj: dict, hw_sim: dict) -> None:
    rows = [
        ("software", "label", sw["label"], "", sw["source"]),
        (
            "software",
            "measurement_note",
            sw.get("measurement_note", ""),
            "",
            "not median-of-10 wall runs",
        ),
        ("software", "throughput_frames_per_s", sw["throughput_frames_per_s"], "frames/s", "M1: 880 frames / 22.035 s wall"),
        ("software", "execution_time_ms_per_frame", sw["execution_time_ms_per_frame"], "ms", "M1: 880 frames / 22.035 s wall"),
        ("software", "throughput_gops_full_preprocess", sw["throughput_gops"], "GOPS", "21 ops/px wall clock"),
        ("software", "throughput_gops_fused_5p", sw["throughput_gops_fused_5p"], "GOPS", "5 FLOP/px wall clock"),
        ("software", "arithmetic_intensity", sw["arithmetic_intensity_flop_per_byte"], "FLOP/byte", "M1 byte model"),
        ("software", "implied_dram_bandwidth", sw["implied_dram_gbs"], "GB/s", "conservative byte model"),
        (
            "hardware_primary",
            "label",
            hw_proj["label"],
            "",
            hw_proj["source"],
        ),
        (
            "hardware_primary",
            "throughput_frames_per_s",
            hw_proj["throughput_frames_per_s"],
            "frames/s",
            hw_proj["projection_formula"],
        ),
        (
            "hardware_primary",
            "execution_time_ms_per_frame",
            hw_proj["execution_time_ms_per_frame"],
            "ms",
            hw_proj["projection_formula"],
        ),
        (
            "hardware_primary",
            "throughput_gops",
            hw_proj["throughput_gops"],
            "GOPS",
            "5 FLOP/px * 2 lanes @ signoff MHz",
        ),
        (
            "hardware_primary",
            "arithmetic_intensity",
            hw_proj["arithmetic_intensity_flop_per_byte"],
            "FLOP/byte",
            "fused kernel upper bound",
        ),
        (
            "hardware_primary",
            "power_w",
            hw_proj["power_w"],
            "W",
            hw_proj["power_source"],
        ),
        (
            "hardware_primary",
            "energy_uj_per_frame",
            hw_proj["energy_uj_per_frame"],
            "uJ",
            "power_w / fps",
        ),
        (
            "speedup",
            "frame_throughput_ratio",
            round(hw_proj["throughput_frames_per_s"] / sw["throughput_frames_per_s"], 4),
            "x",
            "hw_primary_fps / sw_fps",
        ),
        (
            "speedup",
            "fused_gops_ratio",
            round(hw_proj["throughput_gops"] / sw["throughput_gops_fused_5p"], 4),
            "x",
            "hw_primary_gops / sw_fused_5p_gops",
        ),
    ]
    if "throughput_frames_per_s" in hw_sim:
        rows.extend(
            [
                ("hardware_sim", "label", hw_sim["label"], "", hw_sim["source"]),
                (
                    "hardware_sim",
                    "throughput_frames_per_s",
                    hw_sim["throughput_frames_per_s"],
                    "frames/s",
                    hw_sim.get("extrapolation", ""),
                ),
                (
                    "hardware_sim",
                    "throughput_gops",
                    hw_sim["throughput_gops"],
                    "GOPS",
                    hw_sim.get("extrapolation", ""),
                ),
                (
                    "hardware_sim",
                    "cycles_per_frame_extrapolated",
                    hw_sim["cycles_per_frame_extrapolated"],
                    "cycles",
                    "",
                ),
            ]
        )

    path = BENCH_DIR / "benchmark_data.csv"
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["category", "metric", "value", "unit", "method_or_source"])
        w.writerows(rows)


def main() -> None:
    sw = load_m1_archival()
    hw_proj = projected_from_synthesis()
    hw_sim = run_icarus_extrapolation()

    (BENCH_DIR / "sw_results.json").write_text(json.dumps(sw, indent=2), encoding="utf-8")
    (BENCH_DIR / "hw_results.json").write_text(
        json.dumps({"primary": hw_proj, "sim_extrapolation": hw_sim}, indent=2),
        encoding="utf-8",
    )
    write_csv(sw, hw_proj, hw_sim)

    print("Wrote sw_results.json, hw_results.json, benchmark_data.csv")
    print(f"SW: {sw['throughput_frames_per_s']} fps")
    print(f"HW (primary): {hw_proj['throughput_frames_per_s']} fps")
    if "throughput_frames_per_s" in hw_sim:
        print(f"HW (sim): {hw_sim['throughput_frames_per_s']} fps")


if __name__ == "__main__":
    main()
