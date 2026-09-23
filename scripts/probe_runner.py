"""Bounded capability probe for the review-runner templates.

The templates come from ``.conclave/panel.toml`` (D00 T04 §15): one
argv per codex slot, rendered by ``panel_slots``. A CLI that drops
those flags, or that again requires ``--reasoning``, fails here before
a review run starts. No model call.

``--self-test`` checks the TOML templates plus hermetic negatives.
``--live`` asks the installed ``codex`` for ``exec --help`` and for
rejection of ``--reasoning``. A missing binary prints ``SKIP live
probe`` and exits 0 so a runner without Codex stays honest. A present
binary that fails the contract exits 1.

D00 T04 §25 adds the Grok leg: the `fallback` slot's argv must pass the
prompt as a file with read-only flags, and ``--live`` asks the
installed Grok CLI for ``--help`` and checks it still names every flag
the template uses. A missing Grok CLI prints ``SKIP live grok probe``.
"""

from __future__ import annotations

import shutil
import subprocess
import sys

import panel_slots

REQUIRED_HELP = (
    "-c, --config",
    "-m, --model",
    "-s, --sandbox",
    "read-only",
)


# Flags the Grok template passes (panel_slots.argv_for_slot); the live
# help must still name each one.
GROK_REQUIRED_HELP = (
    "--model",
    "--reasoning-effort",
    "--output-format",
    "--permission-mode",
    "--no-subagents",
    "--disable-web-search",
    "--tools",
    "--prompt-file",
)


def grok_template_ok(argv: list[str], effort: str) -> list[str]:
    """Problems in one Grok template argv. Empty means it matches."""
    problems = []
    if argv[:1] != ["grok"] or "-m" not in argv:
        problems.append("template does not start with grok -m")
    if argv[-2:-1] != ["--prompt-file"]:
        problems.append("template does not pass the prompt as a file")
    if "--reasoning-effort" not in argv or effort not in argv:
        problems.append(f"template does not set --reasoning-effort {effort}")
    for flag, value in (("--permission-mode", "plan"), ("--tools", "Read")):
        if flag not in argv or argv[argv.index(flag) + 1] != value:
            problems.append(f"template does not pass {flag} {value}")
    if "--no-subagents" not in argv or "--disable-web-search" not in argv:
        problems.append("template does not disable subagents and web search")
    return problems


def help_gaps(text: str) -> list[str]:
    return [needle for needle in REQUIRED_HELP if needle not in text]


def reasoning_rejected(code: int, text: str) -> bool:
    return code != 0 and "unexpected argument '--reasoning'" in text


def template_ok(argv: list[str], model: str, effort: str) -> list[str]:
    """Problems in one codex template argv. Empty means it matches."""
    problems = []
    if "--reasoning" in argv:
        problems.append("template still passes --reasoning")
    if argv[:2] != ["codex", "exec"]:
        problems.append("template does not start with codex exec")
    if "-m" not in argv or model not in argv:
        problems.append(f"template does not name {model}")
    if f"model_reasoning_effort={effort}" not in argv:
        problems.append(f"template does not set model_reasoning_effort={effort}")
    if "-s" not in argv or "read-only" not in argv:
        problems.append("template does not request the read-only sandbox")
    if argv[-1] != "-":
        problems.append("template does not read the prompt from stdin")
    return problems


def templates_ok() -> list[str]:
    """Problems in the TOML's codex templates. Empty means all match."""
    try:
        slots = panel_slots.load_slots()
    except panel_slots.PanelSlotsError as exc:
        return [str(exc)]
    problems = []
    for name, argv in panel_slots.codex_templates(slots):
        entry = slots[name]
        problems.extend(f"{name}: {p}" for p in template_ok(argv, entry["model"], entry["effort"]))
    for name in sorted(slots):
        if slots[name]["family"] != "grok":
            continue
        try:
            argv = panel_slots.argv_for_slot(name, slots)
        except panel_slots.PanelSlotsError as exc:
            problems.append(f"{name}: {exc}")
            continue
        problems.extend(f"{name}: {p}" for p in grok_template_ok(argv, slots[name]["effort"]))
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
    problems = templates_ok() + judge(help_code, help_text, bad_code, bad_text)
    grok = panel_slots.grok_binary()
    if grok == "grok" and shutil.which("grok") is None:
        print("SKIP live grok probe: grok CLI not found")
    else:
        try:
            out = subprocess.run([grok, "--help"], capture_output=True, timeout=30)
            text = (out.stdout or b"").decode("utf-8", "replace") + (out.stderr or b"").decode("utf-8", "replace")
            if out.returncode != 0:
                problems.append(f"grok --help exited {out.returncode}")
            problems.extend(f"grok help missing {flag}" for flag in GROK_REQUIRED_HELP if flag not in text)
        except (OSError, subprocess.TimeoutExpired) as exc:
            problems.append(f"grok --help failed: {exc}")
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

    check("templates match the wiring", templates_ok(), [])
    bulk = panel_slots.argv_for_slot("bulk")
    drifted = list(bulk)
    drifted[drifted.index("-c")] = "--reasoning"
    sol, med = panel_slots.load_slots()["bulk"]["model"], "medium"
    check("a --reasoning template is rejected", "--reasoning" in " ".join(template_ok(drifted, sol, med)), True)
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
    grok_slots = {"fallback": {"model": "grok-4.7", "effort": "high", "timeout": 900, "family": "grok"}}
    grok_argv = panel_slots.argv_for_slot("fallback", grok_slots, prompt_path="p.md")
    check("the Grok template matches", grok_template_ok(grok_argv, "high"), [])
    stdin_argv = [a for a in grok_argv if a not in ("--prompt-file", "p.md")] + ["-p", "-"]
    check(
        "a Grok template reading stdin is rejected",
        "template does not pass the prompt as a file" in grok_template_ok(stdin_argv, "high"),
        True,
    )
    writable = list(grok_argv)
    writable[writable.index("--permission-mode") + 1] = "bypassPermissions"
    check(
        "a Grok template leaving plan mode is rejected",
        "template does not pass --permission-mode plan" in grok_template_ok(writable, "high"),
        True,
    )
    total = 9
    if failed:
        print(f"probe_runner self-test: {failed} failed")
        return 1
    print(f"probe_runner self-test: {total} cases, 0 failed")
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
