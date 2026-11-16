"""Render the ScratchPad brand rasters from the SVG masters in resources/brand.

Masters (hand-authored, text already outlined): scratchpad-icon.svg (48 px and
up), scratchpad-icon-small.svg (16 to 32 px), the two wordmarks, the social
preview and the README banner. This script only rasterizes; re-run it after
editing a master and commit the outputs with it.

Outputs:
  resources/notepad.ico              app icon, 16 to 256 px (path kept: the
                                     csproj, the window code and AppIconTests name it)
  resources/titlebar-icon-16.png     title bar glyph at 100 and 125 percent scale
  resources/titlebar-icon-32.png     title bar glyph at 150 percent scale and up
  resources/brand/*.png              icon, wordmarks, social preview, README banner

Needs: pip install resvg_py pillow. Usage: python tools/build-brand-assets.py
"""
import io
import os
import sys
import tempfile
from pathlib import Path

import resvg_py
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent if len(sys.argv) < 2 else Path(sys.argv[1])
RES = ROOT / "resources"
BRAND = RES / "brand"
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
SMALL_MAX = 32


def render(svg_name: str, width: int) -> Image.Image:
    data = resvg_py.svg_to_bytes(svg_string=(BRAND / svg_name).read_text(encoding="utf-8"), width=width)
    return Image.open(io.BytesIO(bytes(data))).convert("RGBA")


def write_atomic(path: Path, save) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=path.suffix)
    os.close(fd)
    try:
        save(tmp)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def icon(size: int) -> Image.Image:
    return render("scratchpad-icon-small.svg" if size <= SMALL_MAX else "scratchpad-icon.svg", size)


def main() -> None:
    frames = [icon(s) for s in ICO_SIZES]
    write_atomic(RES / "notepad.ico", lambda p: frames[-1].save(
        p, format="ICO", sizes=[(s, s) for s in ICO_SIZES], append_images=frames[:-1]))
    for size in (16, 32):
        write_atomic(RES / f"titlebar-icon-{size}.png", lambda p, s=size: icon(s).save(p, format="PNG"))
    write_atomic(BRAND / "scratchpad-icon-512.png", lambda p: render("scratchpad-icon.svg", 512).save(p, format="PNG"))
    for name, width in (("scratchpad-wordmark-light", 960), ("scratchpad-wordmark-dark", 960),
                        ("social-preview", 1280), ("readme-banner", 1280)):
        write_atomic(BRAND / f"{name}.png", lambda p, n=name, w=width: render(f"{n}.svg", w).save(p, format="PNG"))
    with Image.open(RES / "notepad.ico") as ico:
        got = sorted(ico.info.get("sizes", []))
    want = sorted((s, s) for s in ICO_SIZES)
    if got != want:
        raise SystemExit(f"notepad.ico holds {got}, expected {want}")
    print(f"wrote notepad.ico ({len(ICO_SIZES)} sizes), 2 title bar PNGs, 5 brand PNGs")


main()
