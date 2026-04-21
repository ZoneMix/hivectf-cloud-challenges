"""Render the entire tilted.gcode scene rotated by -45 about Y axis."""
from __future__ import annotations

import math
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection

sys.path.insert(0, str(Path(__file__).parent))
from render_tilted import GCODE_PATH, SHELL_TYPES, SUPPORT_TYPES, parse_gcode
from untilt import rotate_segments

OUT_DIR = Path(__file__).parent / "renders_tilted"


def plot_xy(segs, title, out, figsize=(24, 24), lw=0.3):
    if not segs:
        return
    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (s.x0, s.y0)
        lines[i, 1] = (s.x1, s.y1)
    fig, ax = plt.subplots(figsize=figsize, dpi=150)
    lc = LineCollection(lines, colors="black", linewidths=lw)
    ax.add_collection(lc)
    ax.set_aspect("equal")
    ax.autoscale()
    ax.set_title(title)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segs)")


def main() -> int:
    segs = parse_gcode(GCODE_PATH)
    # Keep shells and fills, drop supports and skirts
    no_sup = [s for s in segs if s.typ not in {"SUPPORT", "SUPPORT-INTERFACE", "SKIRT"}]

    # Rotate all non-support segments by -45 about Y.
    theta = math.radians(-45)
    rotated = rotate_segments(no_sup, theta)

    plot_xy(rotated, "Full scene rotated -45 deg about Y",
            OUT_DIR / "full_scene_-45.png", figsize=(24, 24), lw=0.3)

    # Also shell-only
    shell = [s for s in no_sup if s.typ in SHELL_TYPES]
    rot_shell = rotate_segments(shell, theta)
    plot_xy(rot_shell, "Full scene (shell only) rotated -45 deg",
            OUT_DIR / "full_shell_-45.png", figsize=(24, 24), lw=0.3)

    return 0


if __name__ == "__main__":
    sys.exit(main())
