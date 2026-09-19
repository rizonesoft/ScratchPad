#!/usr/bin/env python3
"""Bin layout guards: unique project stems plus evaluated-path conformance.

D00 T01 §41 items 2 (PR3) and 5 (PR7, PR8). `stems` needs no SDK; the
`conformance` evaluated legs shell `dotnet msbuild -getProperty` (repo-local
SDK on PATH, as in CI). Exit 0 when every leg holds, 1 with the violation
named otherwise.

Scan roots are `<root>/src`, `<root>/tests`, `<root>/tools`. Three fixture
trees stay out of the default scan (each documented beside the fixture, and
each proven by CI running green with the fixtures present):
`tests/Fixtures/dup-stems` (item 2 fire proof),
`tests/Fixtures/bad-output` (item 5 evaluated-leg fire proof), and
`tests/Fixtures/clean-bin` (item 8 fixture, holding a fake Bin/).
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

SCAN_DIRS = ("src", "tests", "tools")
EXCLUDE = (
    "tests/Fixtures/dup-stems",
    "tests/Fixtures/bad-output",
    "tests/Fixtures/clean-bin",
)


def excluded(root: Path, p: Path) -> bool:
    rel = p.relative_to(root).as_posix()
    return any(rel == e or rel.startswith(e + "/") for e in EXCLUDE)


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def iter_projects(root: Path):
    """Every scanned *.csproj under root, minus the fixture exclusions."""
    found = []
    for d in SCAN_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*.csproj")):
            if excluded(root, p):
                continue
            found.append(p)
    return found


def cmd_stems(root: Path) -> int:
    """Item 2: csproj stems are unique, so Bin/<Project>/ cannot collide."""
    seen: dict[str, Path] = {}
    failed = False
    for p in iter_projects(root):
        key = p.stem.casefold()
        if key in seen:
            print(f"collision: stem {p.stem}: {seen[key]} and {p}")
            failed = True
        else:
            seen[key] = p
    if failed:
        return 1
    print(f"unique stems: {len(seen)} projects, no collisions")
    return 0


def evaluated(dotnet: str, project: Path, prop: str) -> str | None:
    """One evaluated MSBuild property, or None when evaluation fails."""
    r = subprocess.run(
        [dotnet, "msbuild", str(project), f"-getProperty:{prop}", "-v:q", "-nologo"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        first = r.stderr.strip().splitlines()[:1]
        print(f"evaluation failed: {project} ({prop}): {first[0] if first else ''}")
        return None
    lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
    if not lines:
        return ""
    return lines[-1].strip()


def cmd_conformance(root: Path, dotnet: str, skip_eval: bool) -> int:
    """Item 5: evaluated outputs sit under Bin/<stem>/<Config>[/<RID>] and no
    source-tree bin/ exists. The project leg must equal the file stem: an
    MSBuildProjectName override would break the Bin/<stem> contract, so the
    probe treats any override as a shape violation."""
    failed = False
    projects = iter_projects(root)
    if not skip_eval:
        root_norm = root.resolve().as_posix()
        for p in projects:
            out = evaluated(dotnet, p, "OutputPath")
            if out is None:
                failed = True
                continue
            norm = out.replace("\\", "/")
            prefix = f"{root_norm}/Bin/{p.stem}/"
            if os.name == "nt":
                norm, prefix = norm.casefold(), prefix.casefold()
            rest = norm[len(prefix):].strip("/") if norm.startswith(prefix) else None
            legs = rest.split("/") if rest else []
            config = evaluated(dotnet, p, "Configuration")
            rid = evaluated(dotnet, p, "RuntimeIdentifier")
            if config is None or rid is None:
                failed = True
                continue
            if os.name == "nt":
                config, rid = config.casefold(), rid.casefold()
            want = [config] + ([rid] if rid else [])
            if rest is None or legs != want:
                print(f"shape violation: {p} evaluates to {out}")
                failed = True
    for d in SCAN_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for b in sorted(base.rglob("*")):
            if excluded(root, b):
                continue
            if b.is_dir() and b.name.lower() == "bin":
                print(f"stray bin/: {b}")
                failed = True
    if failed:
        return 1
    what = "filesystem legs only" if skip_eval else f"{len(projects)} projects evaluated"
    print(f"conformance: {what}, no stray bin/")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    ps = sub.add_parser("stems", help="item 2: unique csproj stems")
    ps.add_argument("--root", default=str(repo_root()), help="repo root to scan")
    pc = sub.add_parser("conformance", help="item 5: evaluated paths plus no-bin")
    pc.add_argument("--root", default=str(repo_root()), help="repo root to scan")
    pc.add_argument("--skip-eval", action="store_true", help="filesystem legs only")
    pc.add_argument("--dotnet", default="dotnet", help="dotnet executable for evaluation")
    args = ap.parse_args(argv)
    root = Path(args.root)
    if args.cmd == "stems":
        return cmd_stems(root)
    return cmd_conformance(root, args.dotnet, args.skip_eval)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
