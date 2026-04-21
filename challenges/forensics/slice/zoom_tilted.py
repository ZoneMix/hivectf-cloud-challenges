"""High-resolution zoom of the untilted flag text and verification.

Also checks other faces and the untilt sweep for alternative flags.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection

sys.path.insert(0, str(Path(__file__).parent))
from render_tilted import GCODE_PATH, SHELL_TYPES, SUPPORT_TYPES, parse_gcode
from untilt import rotate_segments, segments_in_slab_region

OUT_DIR = Path(__file__).parent / "renders_tilted"


def _lc(segs, a1, a2, lw):
    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (getattr(s, f"{a1}0"), getattr(s, f"{a2}0"))
        lines[i, 1] = (getattr(s, f"{a1}1"), getattr(s, f"{a2}1"))
    return LineCollection(lines, colors="black", linewidths=lw)


def plot(segs, a1, a2, title, out, figsize=(24, 6), lw=0.4, xlim=None, ylim=None):
    if not segs:
        print(f"SKIP {out}: empty")
        return
    fig, ax = plt.subplots(figsize=figsize, dpi=200)
    ax.add_collection(_lc(segs, a1, a2, lw))
    if xlim:
        ax.set_xlim(xlim)
    if ylim:
        ax.set_ylim(ylim)
    else:
        ax.autoscale()
    ax.set_aspect("equal")
    ax.set_title(title)
    ax.set_xlabel(f"{a1.upper()} (mm)")
    ax.set_ylabel(f"{a2.upper()} (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segs)")


def main() -> int:
    segs = parse_gcode(GCODE_PATH)
    shell = [s for s in segs if s.typ in SHELL_TYPES]
    slab = segments_in_slab_region(shell)
    print(f"Slab shell segments: {len(slab)}")

    # Rotate by -45 deg about Y (found from earlier render).
    theta = math.radians(-45)
    rotated = rotate_segments(slab, theta)

    # Determine Z strata of the rotated slab.
    zs = [p for s in rotated for p in (s.z0, s.z1)]
    z_min, z_max = min(zs), max(zs)
    print(f"Rotated Z range: {z_min:.2f}..{z_max:.2f}")

    # Try several Z strata to separate faces.
    strata = [
        ("bottom_1mm", lambda s: max(s.z0, s.z1) <= z_min + 1.0),
        ("bottom_3mm", lambda s: max(s.z0, s.z1) <= z_min + 3.0),
        ("bottom_5mm", lambda s: max(s.z0, s.z1) <= z_min + 5.0),
        ("middle", lambda s: (z_min + 5.0 < min(s.z0, s.z1)
                              and max(s.z0, s.z1) < z_max - 5.0)),
        ("top_5mm", lambda s: min(s.z0, s.z1) >= z_max - 5.0),
        ("top_3mm", lambda s: min(s.z0, s.z1) >= z_max - 3.0),
        ("top_1mm", lambda s: min(s.z0, s.z1) >= z_max - 1.0),
    ]
    for name, pred in strata:
        filt = [s for s in rotated if pred(s)]
        plot(filt, "x", "y", f"-45deg slab / stratum={name}",
             OUT_DIR / f"untilt_-45_{name}.png", figsize=(24, 6), lw=0.5)

    # Try a few fine-grained angle sweeps.
    for deg in (-46, -45, -44, -43, -42, -41, -40):
        rot = rotate_segments(slab, math.radians(deg))
        plot(rot, "x", "y", f"slab @ {deg} deg", OUT_DIR / f"fine_{deg:+d}.png",
             figsize=(24, 8), lw=0.4)

    # High-res zoom of the -45 text region.
    # Based on untilt_-45.png: text at approximately X=0..140, Y=58..72
    rot45 = rotate_segments(slab, math.radians(-45))
    text_region = [s for s in rot45
                   if 0 <= s.x0 <= 140 and 50 <= s.y0 <= 78
                   and 0 <= s.x1 <= 140 and 50 <= s.y1 <= 78]
    plot(text_region, "x", "y", "Flag zoom (-45 deg)",
         OUT_DIR / "untilt_-45_flag_zoom.png", figsize=(32, 8), lw=0.7,
         xlim=(0, 140), ylim=(55, 75))

    return 0


if __name__ == "__main__":
    sys.exit(main())
