#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


def draw_base_icon(size: int = 1024) -> Image.Image:
    bg = (12, 16, 28, 255)
    fg = (245, 248, 255, 255)
    image = Image.new("RGBA", (size, size), bg)
    draw = ImageDraw.Draw(image)

    # Padding keeps the symbol clear at small icon sizes.
    pad = int(size * 0.08)
    inner = [pad, pad, size - pad, size - pad]
    corner = int(size * 0.22)
    draw.rounded_rectangle(inner, radius=corner, fill=bg)

    cx_left = int(size * 0.33)
    cx_right = int(size * 0.67)
    cy = int(size * 0.47)
    radius = int(size * 0.165)
    stroke = max(8, int(size * 0.055))

    draw.ellipse(
        [cx_left - radius, cy - radius, cx_left + radius, cy + radius],
        outline=fg,
        width=stroke,
    )
    draw.ellipse(
        [cx_right - radius, cy - radius, cx_right + radius, cy + radius],
        outline=fg,
        width=stroke,
    )

    bridge_half_h = max(4, stroke // 2)
    bridge_x0 = cx_left + radius - (stroke // 2)
    bridge_x1 = cx_right - radius + (stroke // 2)
    if bridge_x1 < bridge_x0:
        bridge_x0, bridge_x1 = bridge_x1, bridge_x0
    bridge = [bridge_x0, cy - bridge_half_h, bridge_x1, cy + bridge_half_h]
    draw.rounded_rectangle(bridge, radius=bridge_half_h, fill=fg)

    dot_r = max(5, int(size * 0.03))
    draw.ellipse(
        [cx_left - dot_r, cy - dot_r, cx_left + dot_r, cy + dot_r],
        fill=fg,
    )
    draw.ellipse(
        [cx_right - dot_r, cy - dot_r, cx_right + dot_r, cy + dot_r],
        fill=fg,
    )
    return image


def build_iconset(base_image: Image.Image, iconset_dir: Path) -> None:
    sizes = [16, 32, 128, 256, 512]
    for px in sizes:
        one_x = base_image.resize((px, px), Image.Resampling.LANCZOS)
        two_x = base_image.resize((px * 2, px * 2), Image.Resampling.LANCZOS)
        one_x.save(iconset_dir / f"icon_{px}x{px}.png")
        two_x.save(iconset_dir / f"icon_{px}x{px}@2x.png")


def main() -> int:
    if len(sys.argv) > 2:
        print(f"Usage: {Path(sys.argv[0]).name} [output.icns]", file=sys.stderr)
        return 2

    if shutil.which("iconutil") is None:
        print("error: iconutil not found (macOS only)", file=sys.stderr)
        return 1

    out_path = (
        Path(sys.argv[1]).expanduser().resolve()
        if len(sys.argv) == 2
        else Path("macOS/AppIcon.icns").resolve()
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    base = draw_base_icon(1024)

    with tempfile.TemporaryDirectory(prefix="stereofool-icon-") as tmp:
        iconset_dir = Path(tmp) / "StereoFool.iconset"
        iconset_dir.mkdir(parents=True, exist_ok=True)
        build_iconset(base, iconset_dir)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(out_path)],
            check=True,
        )

    print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
