"""Review-prompt construction and reviewer-output validation (D00 T01 §17).

Prompts are ephemeral `/tmp` files, but the rules that build them are
checked-in code so a fixture can prove them: delimiter tags are unique per
prompt (item 14: fixed delimiters are injectable from TODO text), prompt
bytes are canonicalized before counting (item 5: UTF-8/LF, so Windows and
WSL checkouts agree), and reviewer output is validated whole (item 15: one
valid-looking row must not mask malformed trailing findings).
"""

import re
import secrets

PANEL_LENSES = ("adversarial", "consistency", "integration", "record")
PANEL_VERDICTS = ("approve", "needs-attention", "advisory")
_PANEL_LINE_RE = re.compile(
    r"^\s*(?:[*`>\-]|\*{1,2})?\s*`?(adversarial|consistency|integration|record)`?\s*:?\s*"
    r"(approve|needs-attention|advisory)\b"
)


def unique_tag(prefix: str) -> str:
    """A delimiter tag no TODO text can predict: prefix plus 64 random bits."""
    return f"{prefix}-{secrets.token_hex(8)}"


def fence_chunks(tag: str, chunks: list[tuple[str, str]]) -> str:
    """Wrap (title, body) chunks in tagged delimiter lines.

    The tag is the control: a fake `--- SECTION ---` inside untrusted TODO
    text carries no tag and matches nothing.
    """
    parts = []
    for title, body in chunks:
        parts.append(f"--- {title} [{tag}] ---")
        parts.append(body.rstrip("\n"))
    parts.append(f"--- END [{tag}] ---")
    return "\n".join(parts) + "\n"


def canonical_prompt_bytes(text: str) -> bytes:
    """Prompt bytes as the manifest counts them: LF newlines, UTF-8."""
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def check_panel_output(text: str) -> tuple[bool, str]:
    """Whole-output validation for a panel round: every lens verdicts
    exactly once, and every other non-blank line is a detail line under the
    most recent non-approve verdict (an approve takes no details, and
    nothing precedes the first verdict). Returns (ok, reason); the first
    bad line is the reason, so trailing garbage after four good verdicts
    still fails instead of masking."""
    seen: dict[str, int] = {}
    detail_open = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        m = _PANEL_LINE_RE.match(line)
        if m:
            lens = m.group(1)
            if lens in seen:
                return False, f"line {lineno} repeats the {lens} verdict (first at line {seen[lens]})"
            seen[lens] = lineno
            detail_open = m.group(2) != "approve"
            continue
        if not seen:
            return False, f"line {lineno} precedes the first verdict: {line.strip()[:80]}"
        if not detail_open:
            return False, f"line {lineno} is not a verdict or finding detail: {line.strip()[:80]}"
    missing = [lens for lens in PANEL_LENSES if lens not in seen]
    if missing:
        return False, f"missing verdicts: {', '.join(missing)}"
    return True, "four lenses, one verdict each"


def check_plan_output(text: str) -> tuple[bool, str]:
    """Whole-output validation for a plan-review round: every non-blank line
    is one `- ` finding (or the round is an explicit no-findings
    statement). Returns (ok, reason)."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return False, "empty output"
    if len(lines) == 1 and re.search(r"no findings?", lines[0], re.IGNORECASE):
        return True, "explicit no-findings statement"
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        if not line.startswith("- "):
            return False, f"line {lineno} is not a `- ` finding: {line.strip()[:80]}"
    return True, f"{len(lines)} findings, one per line"


if __name__ == "__main__":
    import sys

    checkers = {"check-panel": check_panel_output, "check-plan": check_plan_output}
    if len(sys.argv) != 2 or sys.argv[1] not in checkers:
        print(f"usage: {sys.argv[0]} check-panel|check-plan < output.txt", file=sys.stderr)
        sys.exit(2)
    ok, reason = checkers[sys.argv[1]](sys.stdin.read())
    print(("PASS " if ok else "FAIL ") + reason)
    sys.exit(0 if ok else 1)
