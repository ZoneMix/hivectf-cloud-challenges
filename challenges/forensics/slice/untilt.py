"""Un-tilt the tilted.gcode slab and render flat.

Strategy:
  1. Parse extrusion segments.
  2. Isolate the diagonal slab points — they are WALL-OUTER segments in the
     region X in [100, 205], Y in [40, 90], separate from the bee/pads.
  3. Rotate all segment points by a range of angles about the Y axis
     (rotation in XZ plane) and render top-down XY views of the slab region.
  4. Also determine the angle automatically via PCA on the slab points:
     the dominant XZ direction of the slab = tilt axis.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection

sys.path.insert(0, str(Path(__file__).parent))
from render_tilted import GCODE_PATH, SHELL_TYPES, SUPPORT_TYPES, parse_gcode  # noqa: E402

OUT_DIR = Path(__file__).parent / "renders_tilted"
OUT_DIR.mkdir(exist_ok=True)


def segments_in_slab_region(segs):
    """Return only segments inside the diagonal slab's bounding box in XY."""
    # From the xy_shell.png render: slab X~100..205, Y~45..90
    return [
        s for s in segs
        if s.typ in SHELL_TYPES
        and 100 <= s.x0 <= 210 and 40 <= s.y0 <= 90
        and 100 <= s.x1 <= 210 and 40 <= s.y1 <= 90
    ]


def pca_tilt_angle(slab_segs) -> float:
    """Compute the tilt angle (radians) in the XZ plane via PCA.

    Returns the angle of the slab's long axis from the X axis.
    """
    pts = []
    for s in slab_segs:
        pts.append((s.x0, s.z0))
        pts.append((s.x1, s.z1))
    arr = np.array(pts)  # (N, 2) in (X, Z)
    arr = arr - arr.mean(axis=0)
    cov = np.cov(arr.T)
    eigvals, eigvecs = np.linalg.eigh(cov)
    # eigvecs[:, -1] is the largest (dominant direction)
    v = eigvecs[:, -1]
    angle = math.atan2(v[1], v[0])  # angle of (dx, dz)
    return angle


def rotate_segments(segs, angle_rad: float):
    """Rotate all segments by -angle about the Y axis (undo the tilt).

    X' =  cos(angle)*X + sin(angle)*Z
    Z' = -sin(angle)*X + cos(angle)*Z
    """
    c = math.cos(angle_rad)
    s = math.sin(angle_rad)
    out = []
    for seg in segs:
        nx0 = c * seg.x0 + s * seg.z0
        nz0 = -s * seg.x0 + c * seg.z0
        nx1 = c * seg.x1 + s * seg.z1
        nz1 = -s * seg.x1 + c * seg.z1
        out.append(type(seg)(nx0, seg.y0, nz0, nx1, seg.y1, nz1,
                             seg.layer, seg.typ))
    return out


def plot_xy(segs, title: str, out: Path, figsize=(20, 10), lw: float = 0.3,
            xlim=None, ylim=None) -> None:
    if not segs:
        print(f"SKIP {out}: no segments")
        return
    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (s.x0, s.y0)
        lines[i, 1] = (s.x1, s.y1)
    fig, ax = plt.subplots(figsize=figsize, dpi=200)
    lc = LineCollection(lines, colors="black", linewidths=lw)
    ax.add_collection(lc)
    if xlim:
        ax.set_xlim(xlim)
    if ylim:
        ax.set_ylim(ylim)
    else:
        ax.autoscale()
    ax.set_aspect("equal")
    ax.set_title(title)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segs)")


def main() -> int:
    segs = parse_gcode(GCODE_PATH)
    print(f"Total extrusion segments: {len(segs)}")

    shell = [s for s in segs if s.typ in SHELL_TYPES]
    slab_segs = segments_in_slab_region(shell)
    print(f"Slab region segments (shell only): {len(slab_segs)}")

    angle = pca_tilt_angle(slab_segs)
    print(f"PCA tilt angle: {math.degrees(angle):.2f} deg")

    # Also characterize slab Z range
    zs = [p for s in slab_segs for p in (s.z0, s.z1)]
    print(f"Slab Z range: {min(zs):.2f}..{max(zs):.2f}")

    # Rotate slab segments by -angle (to make long axis horizontal).
    for test_angle_deg in (-math.degrees(angle),):
        theta = math.radians(test_angle_deg)
        rotated = rotate_segments(slab_segs, theta)
        # Recompute extent
        xs_r = [p for s in rotated for p in (s.x0, s.x1)]
        zs_r = [p for s in rotated for p in (s.z0, s.z1)]
        print(f"After {test_angle_deg:.2f} deg rotation: "
              f"X={min(xs_r):.2f}..{max(xs_r):.2f}, Z={min(zs_r):.2f}..{max(zs_r):.2f}")

    # Render the slab at several candidate angles
    candidate_angles = [-60, -55, -50, -48, -46, -45, -44, -42, -40, -38, -35, -30]
    for a_deg in candidate_angles:
        theta = math.radians(a_deg)
        rotated = rotate_segments(slab_segs, theta)
        plot_xy(rotated, f"Slab rotated by {a_deg} deg about Y",
                OUT_DIR / f"untilt_{a_deg:+d}.png", lw=0.4)

    # Use the PCA-derived angle: rotate by -angle (so long axis aligns with X).
    theta_best = -angle
    rotated = rotate_segments(slab_segs, theta_best)
    plot_xy(rotated, f"Slab untilted by PCA ({math.degrees(theta_best):.2f} deg)",
            OUT_DIR / "untilt_pca.png", lw=0.4)

    # After rotation, the slab's "top face" (where the flag is embossed) will be
    # at some Z value. Slice the rotated point cloud by Z to isolate just the
    # top face: pick segments with Z near the max.
    zs_r = sorted({round(min(s.z0, s.z1), 2) for s in rotated} |
                  {round(max(s.z0, s.z1), 2) for s in rotated})
    print(f"Rotated Z distinct values: {len(zs_r)}, range {zs_r[0]}..{zs_r[-1]}")

    z_min = min(min(s.z0, s.z1) for s in rotated)
    z_max = max(max(s.z0, s.z1) for s in rotated)
    print(f"Rotated slab Z range: {z_min:.2f}..{z_max:.2f}")

    # Top face: within 2mm of z_max
    top_face = [s for s in rotated if min(s.z0, s.z1) >= z_max - 3.0]
    plot_xy(top_face, f"Top face only (Z near {z_max:.1f})",
            OUT_DIR / "untilt_top_face.png", lw=0.5)

    # Bottom face: within 2mm of z_min
    bot_face = [s for s in rotated if max(s.z0, s.z1) <= z_min + 3.0]
    plot_xy(bot_face, f"Bottom face only (Z near {z_min:.1f})",
            OUT_DIR / "untilt_bot_face.png", lw=0.5)

    return 0


if __name__ == "__main__":
    sys.exit(main())
