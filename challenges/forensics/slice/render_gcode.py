"""Parse a Marlin G-code file and render extrusion paths.

Produces several views of the printed object to look for text/markings:
  - top-down view (XY) of ALL extrusion
  - top-down view of the top N layers only
  - top-down view of the bottom N layers only
  - side view (XZ) of all extrusion
  - side view (YZ) of all extrusion
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

GCODE_PATH = Path(__file__).parent / "HiveCTF.gcode"
OUT_DIR = Path(__file__).parent / "renders"
OUT_DIR.mkdir(exist_ok=True)

# Regex to capture G0/G1 movement values.
MOVE_RE = re.compile(
    r"^G[01]\b"                      # G0 or G1
    r"(?:\s+F([-\d.]+))?"            # optional feedrate
    r"(?:\s+X([-\d.]+))?"            # optional X
    r"(?:\s+Y([-\d.]+))?"            # optional Y
    r"(?:\s+Z([-\d.]+))?"            # optional Z
    r"(?:\s+E([-\d.]+))?",           # optional E
)

@dataclass
class Segment:
    """Extrusion segment (start and end points)."""
    x0: float
    y0: float
    z0: float
    x1: float
    y1: float
    z1: float
    layer: int


def parse_gcode(path: Path) -> list[Segment]:
    """Parse G-code and return list of extrusion segments only (no travel)."""
    segs: list[Segment] = []
    x = y = z = 0.0
    e = 0.0
    layer = -1
    absolute_extruder = True  # M82

    with path.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(";LAYER:"):
                try:
                    layer = int(line.split(":", 1)[1])
                except ValueError:
                    pass
                continue
            if line.startswith("M82"):
                absolute_extruder = True
                continue
            if line.startswith("M83"):
                absolute_extruder = False
                continue
            if line.startswith("G92"):
                # Reset axis values. We only care about E.
                m = re.search(r"E([-\d.]+)", line)
                if m:
                    e = float(m.group(1))
                continue
            if not (line.startswith("G0") or line.startswith("G1")):
                continue

            m = MOVE_RE.match(line)
            if not m:
                continue
            _, nx, ny, nz, ne = m.groups()
            new_x = float(nx) if nx is not None else x
            new_y = float(ny) if ny is not None else y
            new_z = float(nz) if nz is not None else z

            extruding = False
            if ne is not None:
                new_e = float(ne) if absolute_extruder else e + float(ne)
                # Only count positive extrusion (not retract).
                if new_e > e + 1e-6:
                    extruding = True
                e = new_e

            # Only store extruding segments that move in X or Y or Z.
            if extruding and (new_x != x or new_y != y or new_z != z):
                segs.append(Segment(x, y, z, new_x, new_y, new_z, layer))

            x, y, z = new_x, new_y, new_z

    return segs


def plot_xy(segs: list[Segment], title: str, out: Path, linewidth: float = 0.3) -> None:
    """Top-down XY plot of segments."""
    xs = np.empty((len(segs), 2))
    ys = np.empty((len(segs), 2))
    for i, s in enumerate(segs):
        xs[i] = (s.x0, s.x1)
        ys[i] = (s.y0, s.y1)

    fig, ax = plt.subplots(figsize=(16, 16), dpi=150)
    # Plot all segments as one LineCollection-like batch.
    from matplotlib.collections import LineCollection

    lines = np.stack([xs, ys], axis=-1)  # (N, 2, 2) -> each row: [[x0,y0],[x1,y1]]
    # Correct shape: we need ((N,2,2)) where N segments of 2 points of (x,y).
    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (s.x0, s.y0)
        lines[i, 1] = (s.x1, s.y1)
    lc = LineCollection(lines, colors="black", linewidths=linewidth)
    ax.add_collection(lc)
    ax.set_aspect("equal")
    ax.autoscale()
    ax.set_title(title)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segments)")


def plot_xz(segs: list[Segment], title: str, out: Path, linewidth: float = 0.3) -> None:
    """Side view XZ plot."""
    from matplotlib.collections import LineCollection

    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (s.x0, s.z0)
        lines[i, 1] = (s.x1, s.z1)
    fig, ax = plt.subplots(figsize=(16, 8), dpi=150)
    lc = LineCollection(lines, colors="black", linewidths=linewidth)
    ax.add_collection(lc)
    ax.set_aspect("equal")
    ax.autoscale()
    ax.set_title(title)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Z (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segments)")


def plot_yz(segs: list[Segment], title: str, out: Path, linewidth: float = 0.3) -> None:
    """Side view YZ plot."""
    from matplotlib.collections import LineCollection

    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (s.y0, s.z0)
        lines[i, 1] = (s.y1, s.z1)
    fig, ax = plt.subplots(figsize=(16, 8), dpi=150)
    lc = LineCollection(lines, colors="black", linewidths=linewidth)
    ax.add_collection(lc)
    ax.set_aspect("equal")
    ax.autoscale()
    ax.set_title(title)
    ax.set_xlabel("Y (mm)")
    ax.set_ylabel("Z (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segments)")


def main() -> int:
    print(f"Parsing {GCODE_PATH}...")
    segs = parse_gcode(GCODE_PATH)
    print(f"Parsed {len(segs)} extrusion segments")

    max_layer = max(s.layer for s in segs)
    print(f"Layers: 0..{max_layer}")

    # Layer stats
    by_layer: dict[int, int] = {}
    for s in segs:
        by_layer[s.layer] = by_layer.get(s.layer, 0) + 1
    print(f"Segments per layer (min/avg/max): "
          f"{min(by_layer.values())}/{sum(by_layer.values())/len(by_layer):.0f}/{max(by_layer.values())}")

    # Render all extrusion (top-down)
    plot_xy(segs, "All extrusion (top-down)", OUT_DIR / "xy_all.png")

    # Render top 10 layers
    top_cutoff = max_layer - 10
    top_segs = [s for s in segs if s.layer >= top_cutoff]
    plot_xy(top_segs, f"Top layers ({top_cutoff}..{max_layer})", OUT_DIR / "xy_top.png",
            linewidth=0.5)

    # Render last layer only
    last_segs = [s for s in segs if s.layer == max_layer]
    plot_xy(last_segs, f"Last layer only ({max_layer})", OUT_DIR / "xy_last.png",
            linewidth=0.8)

    # Render bottom 5 layers
    bottom_segs = [s for s in segs if s.layer <= 5]
    plot_xy(bottom_segs, f"Bottom layers (0..5)", OUT_DIR / "xy_bottom.png",
            linewidth=0.5)

    # Render first layer only (layer 0)
    first_segs = [s for s in segs if s.layer == 0]
    plot_xy(first_segs, "First layer only (0)", OUT_DIR / "xy_first.png",
            linewidth=0.8)

    # Side views
    plot_xz(segs, "Side view (XZ)", OUT_DIR / "xz_all.png")
    plot_yz(segs, "Side view (YZ)", OUT_DIR / "yz_all.png")

    return 0


if __name__ == "__main__":
    sys.exit(main())
