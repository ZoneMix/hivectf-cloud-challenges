"""Re-render only the flag region of the first layer at high resolution."""
from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection

from render_gcode import GCODE_PATH, OUT_DIR, parse_gcode

OUT_DIR.mkdir(exist_ok=True)


def main() -> int:
    segs = parse_gcode(GCODE_PATH)
    first = [s for s in segs if s.layer == 0]
    print(f"First-layer segments: {len(first)}")

    # Bounding box of flag text is roughly X=[75, 200], Y=[40, 65] (from xy_first.png).
    x_min, x_max = 70, 205
    y_min, y_max = 35, 70

    region = [
        s for s in first
        if (x_min <= s.x0 <= x_max or x_min <= s.x1 <= x_max)
        and (y_min <= s.y0 <= y_max or y_min <= s.y1 <= y_max)
    ]
    print(f"Region segments: {len(region)}")

    lines = np.empty((len(region), 2, 2))
    for i, s in enumerate(region):
        lines[i, 0] = (s.x0, s.y0)
        lines[i, 1] = (s.x1, s.y1)

    fig, ax = plt.subplots(figsize=(24, 8), dpi=200)
    lc = LineCollection(lines, colors="black", linewidths=0.6)
    ax.add_collection(lc)
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_min, y_max)
    ax.set_aspect("equal")
    ax.set_title("Flag region (first layer) — zoomed")
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    fig.tight_layout()
    out = OUT_DIR / "xy_flag_zoom.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
