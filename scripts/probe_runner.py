"""Bounded capability probe for the review-runner template.

The template is ``codex exec -m gpt-5.6-terra -c model_reasoning_effort=high
-s read-only -``. A CLI that drops those flags, or that again requires
``--reasoning``, fails here before a review run starts. No model call.

``--self-test`` is hermetic. ``--live`` asks the installed ``codex`` for
``exec --help`` and for rejection of ``--reasoning``. A missing binary
prints ``SKIP live probe`` and exits 0 so a runner without Codex stays
honest. A present binary that fails the contract exits 1.
"""

from __future__ import annotations

import shutil
import subprocess
import sys

TEMPLATE = [
    "codex",
    "exec",
    "-m",
    "gpt-5.6-terra",
    "-c",
    "model_reasoning_effort=high",
    "-s",
    "read-only",
    "-",
]

REQUIRED_HELP = (
    "-c, --config",
    "-m, --model",
    "-s, --sandbox",
    "read-only",
)


def help_gaps(text: str) -> list[str]:
    return [needle for needle in REQUIRED_HELP if needle not in text]


def reasoning_rejected(code: int, text: str) -> bool:
    return code != 0 and "unexpected argument '--reasoning'" in text


def template_ok(argv: list[str] = TEMPLATE) -> list[str]:
    """Problems in the checked-in template. Empty means it matches."""
    problems = []
    if "--reasoning" in argv:
        problems.append("template still passes --reasoning")
    if argv[:2] != ["codex", "exec"]:
        problems.append("template does not start with codex exec")
    if "-m" not in argv or "gpt-5.6-terra" not in argv:
        problems.append("template does not name gpt-5.6-terra")
    if "model_reasoning_effort=high" not in argv:
        problems.append("template does not set model_reasoning_effort=high")
    if "-s" not in argv or "read-only" not in argv:
        problems.append("template does not request the read-only sandbox")
    if argv[-1] != "-":
        problems.append("template does not read the prompt from stdin")
    return problems


def judge(help_code: int, help_text: str, bad_code: int, bad_text: str) -> list[str]:
    problems = []
    if help_code != 0:
        problems.append(f"codex exec --help exited {help_code}")
    problems.extend(f"help missing {gap}" for gap in help_gaps(help_text))
    if not reasoning_rejected(bad_code, bad_text):
        problems.append("codex exec accepted --reasoning")
    return problems


def _run(argv: list[str]) -> tuple[int, str]:
    binary = shutil.which(argv[0])
    if binary is None:
        raise FileNotFoundError(argv[0])
    out = subprocess.run(
        [binary, *argv[1:]],
        capture_output=True,
        timeout=30,
    )
    text = (out.stdout or b"").decode("utf-8", "replace") + (out.stderr or b"").decode(
        "utf-8", "replace"
    )
    return out.returncode, text


def live() -> int:
    if shutil.which("codex") is None:
        print("SKIP live probe: codex not on PATH")
        return 0
    try:
        help_code, help_text = _run(["codex", "exec", "--help"])
        bad_code, bad_text = _run(["codex", "exec", "--reasoning", "high", "--help"])
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"FAIL live probe: {exc}")
        return 1
    problems = template_ok() + judge(help_code, help_text, bad_code, bad_text)
    if problems:
        print("FAIL live probe")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print("probe ok")
    return 0


def self_test() -> int:
    failed = 0

    def check(name: str, got, want) -> None:
        nonlocal failed
        if got != want:
            print(f"FAIL {name}: got {got!r}, want {want!r}")
            failed += 1

    check("template matches the contract", template_ok(), [])
    drifted = list(TEMPLATE)
    drifted[drifted.index("-c")] = "--reasoning"
    check("a --reasoning template is rejected", "--reasoning" in " ".join(template_ok(drifted)), True)
    good_help = "\n".join(REQUIRED_HELP)
    check("complete help passes", judge(0, good_help, 2, "error: unexpected argument '--reasoning' found"), [])
    check(
        "help missing the sandbox flag fails",
        "help missing -s, --sandbox" in judge(0, "-c, --config\n-m, --model\n", 2, "unexpected argument '--reasoning'"),
        True,
    )
    check(
        "an accepted --reasoning fails",
        "codex exec accepted --reasoning" in judge(0, good_help, 0, "ok"),
        True,
    )
    check("a help crash fails", "codex exec --help exited 1" in judge(1, "", 2, "unexpected argument '--reasoning'"), True)
    if failed:
        print(f"probe_runner self-test: {failed} failed")
        return 1
    print("probe_runner self-test: 6 cases, 0 failed")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    if argv == ["--live"]:
        return live()
    print("usage: probe_runner.py --self-test | --live", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
