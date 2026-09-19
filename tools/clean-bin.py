#!/usr/bin/env python3
"""Prune stale project dirs under Bin/ (D00 T01 §41 item 8, PR12).

A Bin/<child>/ dir whose name matches no tracked csproj stem is a leftover
of a renamed or removed project: remove it. Matching is case-insensitive so
a pure rename (Foo to foo) still reads stale. Prints every removal; exits 0
always (an empty prune is the common green case). `--dry-run` lists without
removing. Full cleans stay `rm -rf Bin` (docs/build.md); this script clears
only the stale-project tail that a full wipe would also take.
"""

import argparse
import importlib.util
import shutil
import sys
from pathlib import Path


def _guards():
    spec = importlib.util.spec_from_file_location(
        "bin_layout_guards", Path(__file__).resolve().parent / "check-bin-layout.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_GUARDS = _guards()
EXCLUDE, SCAN_DIRS = _GUARDS.EXCLUDE, _GUARDS.SCAN_DIRS


def stems(repo: Path) -> set[str]:
    found = set()
    for d in SCAN_DIRS:
        base = repo / d
        if not base.is_dir():
            continue
        for p in base.rglob("*.csproj"):
            rel = p.relative_to(repo).as_posix()
            if any(rel == e or rel.startswith(e + "/") for e in EXCLUDE):
                continue
            found.add(p.stem.casefold())
    return found


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bin-dir", default="Bin", help="Bin dir to prune")
    ap.add_argument("--repo", default=".", help="repo root holding the projects")
    ap.add_argument("--dry-run", action="store_true", help="list without removing")
    args = ap.parse_args(argv)
    repo = Path(args.repo)
    bindir = Path(args.bin_dir)
    if not bindir.is_dir():
        print(f"no Bin dir at {bindir}, nothing to prune")
        return 0
    live = stems(repo)
    removed = kept = 0
    for child in sorted(bindir.iterdir()):
        if not child.is_dir():
            continue
        if child.name.casefold() in live:
            kept += 1
            continue
        print(f"{'would remove' if args.dry_run else 'removing'} stale {child}")
        if not args.dry_run:
            shutil.rmtree(child)
        removed += 1
    print(f"prune: {removed} removed, {kept} kept")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
