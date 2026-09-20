#!/usr/bin/env python3
"""Resolve and launch the ScratchPad app (D00 T01 §41 item 7, PR11).

The stable pointer over the deep tree: computes
Bin/ScratchPad/<Config>[/<RID>]/ScratchPad.exe and execs it, so operators
never spell the layout. `--print-path` resolves without launching (CI smoke
resolves through it and asserts the resolved path against the evaluated
`OutputPath`). RID defaults to
win-<arch> on every OS, mirroring the csproj unconditional default; `--rid ''`
empties the leg for explicit-RID-empty builds. Extra arguments forward to the app.
"""

import argparse
import os
import platform
import sys
from pathlib import Path


def exe_path(root: Path, config: str, rid: str | None) -> Path:
    parts = ["Bin", "ScratchPad", config]
    if rid:
        parts.append(rid)
    parts.append("ScratchPad.exe")
    return root.joinpath(*parts)


def default_rid() -> str | None:
    arch = platform.machine().lower()
    return "win-arm64" if arch in ("arm64", "aarch64") else "win-x64"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", default="Debug", help="build configuration")
    ap.add_argument("--rid", default=None, help="RID leg (default: platform default)")
    ap.add_argument("--print-path", action="store_true", help="resolve only")
    args, extra = ap.parse_known_args(argv)
    rid = args.rid if args.rid is not None else default_rid()
    if args.rid == "":
        rid = None
    root = Path(__file__).resolve().parent.parent
    exe = exe_path(root, args.config, rid)
    if args.print_path:
        print(exe, flush=True)
        if exe.is_file():
            return 0
        print(f"not built: {exe} (build first, then launch)", file=sys.stderr)
        return 1
    if not exe.is_file():
        print(f"not built: {exe} (build first, then launch)", file=sys.stderr)
        return 1
    os.execv(exe, [str(exe), *extra])
    return 0  # unreachable; exec replaces the process


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
