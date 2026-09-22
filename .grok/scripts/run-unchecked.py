"""Feed a prompt to a producer on stdin, with a wall clock and no output checker.

Architecture rounds have no panel grammar. Panel and plan rounds stay on
scripts/review_prompt.py run. A timeout exits 124.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if "--" not in argv or argv.index("--") != 3:
        print(
            "usage: run-unchecked.py <prompt-file> <seconds> -- <producer> [args...]",
            file=sys.stderr,
        )
        return 2
    prompt = Path(argv[1]).read_bytes()
    try:
        seconds = float(argv[2])
    except ValueError:
        print("seconds must be a number", file=sys.stderr)
        return 2
    if not (0 < seconds <= 3600):
        print("seconds must be inside (0, 3600]", file=sys.stderr)
        return 2
    producer = argv[4:]
    if not producer:
        print("missing producer", file=sys.stderr)
        return 2
    try:
        proc = subprocess.run(
            producer,
            input=prompt,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        sys.stdout.buffer.write(exc.stdout or b"")
        sys.stderr.buffer.write(exc.stderr or b"")
        print(f"timeout after {seconds}s", file=sys.stderr)
        return 124
    except OSError as exc:
        print(f"producer failed to start: {exc}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write(proc.stdout)
    sys.stderr.buffer.write(proc.stderr)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
