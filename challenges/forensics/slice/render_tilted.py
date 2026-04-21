"""Parse and render tilted.gcode.

The object is tilted relative to the bed (supports present), so the flag is
probably embossed on a face that is no longer axis-aligned. We render:

  - top-down XY (all, filtered by type: exclude SUPPORT/SKIRT)
  - side XZ and YZ projections
  - slices through the object at various Z ranges
  - per-layer frames for a few candidate layers
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection

GCODE_PATH = Path(__file__).parent / "tilted.gcode"
OUT_DIR = Path(__file__).parent / "renders_tilted"
OUT_DIR.mkdir(exist_ok=True)

MOVE_RE = re.compile(
    r"^G[01]\b"
    r"(?:\s+F([-\d.]+))?"
    r"(?:\s+X([-\d.]+))?"
    r"(?:\s+Y([-\d.]+))?"
    r"(?:\s+Z([-\d.]+))?"
    r"(?:\s+E([-\d.]+))?",
)

SHELL_TYPES = {"WALL-OUTER", "WALL-INNER", "SKIN"}  # outline/surface
SUPPORT_TYPES = {"SUPPORT", "SUPPORT-INTERFACE", "SKIRT"}


@dataclass
class Segment:
    x0: float
    y0: float
    z0: float
    x1: float
    y1: float
    z1: float
    layer: int
    typ: str


def parse_gcode(path: Path) -> list[Segment]:
    segs: list[Segment] = []
    x = y = z = 0.0
    e = 0.0
    layer = -1
    absolute_extruder = True
    current_type = "NONE"

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
            if line.startswith(";TYPE:"):
                current_type = line.split(":", 1)[1].strip()
                continue
            if line.startswith(";MESH:"):
                continue
            if line.startswith("M82"):
                absolute_extruder = True
                continue
            if line.startswith("M83"):
                absolute_extruder = False
                continue
            if line.startswith("G92"):
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
                if new_e > e + 1e-6:
                    extruding = True
                e = new_e

            if extruding and (new_x != x or new_y != y or new_z != z):
                segs.append(Segment(x, y, z, new_x, new_y, new_z, layer, current_type))

            x, y, z = new_x, new_y, new_z

    return segs


def _lc(segs: list[Segment], axis1: str, axis2: str, lw: float) -> LineCollection:
    lines = np.empty((len(segs), 2, 2))
    for i, s in enumerate(segs):
        lines[i, 0] = (getattr(s, f"{axis1}0"), getattr(s, f"{axis2}0"))
        lines[i, 1] = (getattr(s, f"{axis1}1"), getattr(s, f"{axis2}1"))
    return LineCollection(lines, colors="black", linewidths=lw)


def plot(segs: list[Segment], a1: str, a2: str, title: str, out: Path,
         figsize=(16, 16), lw: float = 0.3) -> None:
    if not segs:
        print(f"SKIP {out}: no segments")
        return
    fig, ax = plt.subplots(figsize=figsize, dpi=150)
    ax.add_collection(_lc(segs, a1, a2, lw))
    ax.set_aspect("equal")
    ax.autoscale()
    ax.set_title(title)
    ax.set_xlabel(f"{a1.upper()} (mm)")
    ax.set_ylabel(f"{a2.upper()} (mm)")
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out} ({len(segs)} segs)")


def main() -> int:
    print(f"Parsing {GCODE_PATH}...")
    segs = parse_gcode(GCODE_PATH)
    print(f"Parsed {len(segs)} extrusion segments")

    # Distribution by type
    by_type: dict[str, int] = {}
    for s in segs:
        by_type[s.typ] = by_type.get(s.typ, 0) + 1
    print("Segments by TYPE:")
    for t, n in sorted(by_type.items(), key=lambda kv: -kv[1]):
        print(f"  {t}: {n}")

    max_layer = max(s.layer for s in segs)
    print(f"Layers: 0..{max_layer}")

    # Exclude supports/skirt (these clutter the outline)
    no_sup = [s for s in segs if s.typ not in SUPPORT_TYPES]
    print(f"Without support/skirt: {len(no_sup)}")

    # Shell-only (walls + skin) for the cleanest outline.
    shell = [s for s in segs if s.typ in SHELL_TYPES]
    print(f"Shell-only (WALLs + SKIN): {len(shell)}")

    # Top-down views
    plot(no_sup, "x", "y", "Top-down (no support/skirt)", OUT_DIR / "xy_no_support.png")
    plot(shell, "x", "y", "Top-down (shell only)", OUT_DIR / "xy_shell.png")
    # Bottom few layers
    first_few = [s for s in shell if s.layer <= 5]
    plot(first_few, "x", "y", "Layers 0..5 shell", OUT_DIR / "xy_bottom_shell.png",
         lw=0.5)

    # Side views
    plot(no_sup, "x", "z", "Side XZ (no support)", OUT_DIR / "xz_no_support.png",
         figsize=(20, 10))
    plot(no_sup, "y", "z", "Side YZ (no support)", OUT_DIR / "yz_no_support.png",
         figsize=(20, 10))
    plot(shell, "x", "z", "Side XZ (shell only)", OUT_DIR / "xz_shell.png",
         figsize=(20, 10))
    plot(shell, "y", "z", "Side YZ (shell only)", OUT_DIR / "yz_shell.png",
         figsize=(20, 10))

    return 0


if __name__ == "__main__":
    sys.exit(main())
