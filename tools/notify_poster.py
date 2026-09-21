#!/usr/bin/env python3
"""Post unattended `query notify` payloads as one GitHub issue per obligation.

D00 T01 §53 items 1-3, 5, and 6 own this file: item 1 extracted the
poster the §29 plan-gates job inlined (stable rolling title, open-issue
dedup); item 2 rekeys it onto obligations, so repeat failures update
one issue per obligation instead of appending to a shared thread; item
3 assigns the mapped owners; item 5 assigns mapped escalation owners
off the overdue `escalate <owner>` suffix while keying on the ref
without it, so the due/overdue transition updates one issue; item 6
retries gh calls boundedly before failing loud.

Obligation identity is the stable part of a payload line
(`    <owner> | <day> | <ref>`): review lines normalize the
due/overdue transition, degraded lines drop the evolving state, finding
and expiry lines key whole. Titles read `<prefix><key>` (default prefix
`Risk watch: `). Per wave each live obligation resolves its issue by
exact title: missing creates it, open diffs its body and comments plus
mirrors on change (quiet when identical), closed reopens on recurrence.
Open watch issues absent from the wave clear-comment plus close. The
retired rolling title closes once when seen open.

Delivery is assignment, not mention: the mapping file
(`.github/owner-logins.json`, owner name to GitHub login) decides who
each obligation notifies. Created issues assign every mapped owner
plus mapped escalation owners off the overdue suffix;
updates and reopens add newly-mapped logins (additive only, read off
the mirrored body, so reassignment notifies without ever dropping an
assignee). Assignees are subscribed, so comments, reopens, and closes
notify without @-mention noise. Unmapped owners ride a body line
naming them plus the mapping file; `?` (unknown) maps to nobody.

Contract: exit 0 posted/updated/cleared (or nothing owed); exit 1 any
gh call failed, the payload file is unreadable, any line shape is
unknown, or the mapping file is missing, unparseable, or carries a bad
login, with the failed call on stderr. Unknown shapes fail closed: the
poster never silently drops an obligation.

Retry (item 6) is bounded and blind: every gh call runs up to
1 + --retries attempts (default 2 retries, 3 attempts) with
--retry-sleep seconds between (default 2), each retry noted on stderr,
and exhaustion raises the last failure with its attempt count. Blind
because gh exits 1 for flakes, auth loss, and rate limits alike;
the bound covers transient flakes, while persistent failures
fail loud here and the next scheduled wave retries the
obligations. Retrying create can theoretically double-mint when
success answers lost; the next wave's exact-title lookup then
updates the first match and the duplicate stays visible for the
operator rather than silently dropping the obligation.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PREFIX = "Risk watch: "
RETIRE_TITLE = "Unattended risk watch (scheduled)"
MAPPING = ".github/owner-logins.json"
# GitHub login rules: alphanumerics plus single hyphens, max 39, never
# leading or trailing hyphen.
LOGIN_RE = re.compile(r"(?!-)(?!.*--)[A-Za-z0-9-]{1,39}(?<!-)")


def fail(msg: str) -> int:
    print(f"notify_poster: {msg}", file=sys.stderr)
    return 1


def run_gh(gh: str, args: list, stdin_text: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [gh, *args],
        input=stdin_text,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def key_of(ref: str) -> str | None:
    """Stable obligation key for a payload ref, else None."""
    # The overdue escalation suffix never keys: refs are constructed
    # without " escalate " anywhere else, so the first one opens the
    # suffix the poster strips before matching.
    ref = ref.split(" escalate ", 1)[0]
    m = re.fullmatch(r"degraded (\S+)( .*)?", ref)
    if m:
        return f"degraded {m.group(1)}"
    m = re.fullmatch(r"(critical|major) (\S+) in (\S.*)", ref)
    if m:
        return ref
    m = re.fullmatch(r"review-(?:due|overdue) (\S.* in \S.*)", ref)
    if m:
        return f"review {m.group(1)}"
    m = re.fullmatch(r"expiring (\S.*)", ref)
    if m:
        return ref
    return None


def parse_payload(body: str) -> tuple[int, dict[str, list[str]]] | str:
    """(count, key -> lines) or an error string. Fails closed."""
    m = re.search(r"^notify: ([0-9]*) payloads", body, re.MULTILINE)
    if m is None or m.group(1) == "":
        head = body.split("\n", 1)[0] if body else ""
        return f"unparseable payload header: {head!r}"
    by_key: dict[str, list[str]] = {}
    for ln in body.splitlines():
        pm = re.fullmatch(r"    (\S.*) \| (\S+) \| (\S.*)", ln)
        if pm is None:
            if ln.strip() == "" or ln.startswith("notify:"):
                continue
            return f"unknown payload line shape: {ln!r}"
        key = key_of(pm.group(3))
        if key is None:
            return f"unknown obligation shape: {pm.group(3)!r}"
        by_key.setdefault(key, []).append(ln)
    return int(m.group(1)), by_key


def line_owner(ln: str) -> str:
    return ln.split("|", 1)[0].strip()


def have_logins(body_text: str) -> set[str]:
    m = re.search(r"^assignees: (.*)$", body_text, re.MULTILINE)
    return set(m.group(1).split()) if m else set()


def load_mapping(path: str) -> dict[str, str] | str:
    """Owner-to-login mapping or an error string. Fails closed."""
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        return f"cannot read mapping file {path}: {e}"
    try:
        data = json.loads(raw)
    except ValueError as e:
        return f"mapping file {path} is not JSON: {e}"
    if not isinstance(data, dict) or any(
        not isinstance(k, str) or not isinstance(v, str) for k, v in data.items()
    ):
        return f"mapping file {path} is not a string-to-string object"
    for owner, login in sorted(data.items()):
        if LOGIN_RE.fullmatch(login) is None:
            return f"mapping file {path} carries a bad GitHub login for {owner}: {login!r}"
    return data


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(description="post notify payloads as one issue per obligation")
    ap.add_argument("payloads", help="file holding `query notify` output")
    ap.add_argument("--prefix", default=PREFIX, help="per-obligation title prefix")
    ap.add_argument("--retire-title", default=RETIRE_TITLE, help="legacy rolling title to close once (empty disables)")
    ap.add_argument("--mapping", default=MAPPING, help="owner-to-login JSON mapping")
    ap.add_argument("--today", default=None, help="freeze wave dates (fixtures)")
    ap.add_argument("--gh", default="gh", help="gh binary (tests point at a fake)")
    ap.add_argument("--retries", default="2", help="gh retries after the first attempt (default 2)")
    ap.add_argument("--retry-sleep", default="2", help="seconds between gh retries (default 2)")
    ns = ap.parse_args(argv)
    if ns.today is not None:
        try:
            datetime.strptime(ns.today, "%Y-%m-%d")
        except ValueError:
            return fail(f"bad --today (want YYYY-MM-DD): {ns.today!r}")
    try:
        retries = int(ns.retries)
        retry_sleep = float(ns.retry_sleep)
        if retries < 0 or retry_sleep < 0:
            raise ValueError
    except ValueError:
        return fail(f"bad --retries/--retry-sleep (want numbers >= 0): {ns.retries!r} {ns.retry_sleep!r}")
    today = ns.today or datetime.now(timezone.utc).date().isoformat()
    try:
        body = Path(ns.payloads).read_text(encoding="utf-8")
    except OSError as e:
        return fail(f"cannot read payload file {ns.payloads}: {e}")
    parsed = parse_payload(body)
    if isinstance(parsed, str):
        return fail(parsed)
    _count, live = parsed
    mapping = load_mapping(ns.mapping)
    if isinstance(mapping, str):
        return fail(mapping)

    def split_owners(lines: list[str]) -> tuple[list[str], list[str]]:
        owners = sorted({line_owner(ln) for ln in lines} - {"?"})
        # Escalation owners (item 5) join the assignee set: an ignored
        # overdue notifies its escalation target, not just the line
        # owner. Unmapped escalation targets ride the unmapped line
        # like unmapped owners; `operator` (the default head) stays
        # visible-but-unassigned until a login exists.
        for ln in lines:
            em = re.search(r" escalate (\S.*)$", ln)
            if em and em.group(1) not in owners + ["?"]:
                owners.append(em.group(1))
        owners = sorted(owners)
        return (
            sorted({mapping[o] for o in owners if o in mapping}),
            sorted([o for o in owners if o not in mapping]),
        )

    def want_body(key: str, lines: list[str]) -> tuple[str, list[str], list[str]]:
        logins, unmapped = split_owners(lines)
        parts = [f"watch obligation: {key}"]
        if logins:
            parts.append(f"assignees: {' '.join(logins)}")
        if unmapped:
            parts.append(f"unmapped owners: {' '.join(unmapped)} (add to {ns.mapping})")
        parts.extend(lines)
        return "\n".join(parts) + "\n", logins, unmapped

    def gh(args: list, stdin_text: str | None = None) -> subprocess.CompletedProcess:
        last: subprocess.CompletedProcess | None = None
        for attempt in range(1, retries + 2):
            p = run_gh(ns.gh, args, stdin_text)
            if p.returncode == 0:
                return p
            last = p
            if attempt <= retries:
                print(
                    f"notify_poster: gh {' '.join(args)} failed (exit {p.returncode}), "
                    f"retry {attempt}/{retries} in {retry_sleep:g}s",
                    file=sys.stderr,
                )
                time.sleep(retry_sleep)
        assert last is not None
        raise RuntimeError(
            f"gh {' '.join(args)} failed (exit {last.returncode}): "
            f"{last.stderr.strip()[-500:]} (after {retries + 1} attempts)"
        )

    def find_issue(title: str, state: str) -> str:
        p = gh(["issue", "list", "--state", state, "--search", f'in:title "{title}"',
                "--json", "number,title"])
        try:
            rows = json.loads(p.stdout.strip() or "[]")
        except ValueError:
            raise RuntimeError(f"gh issue list returned non-JSON: {p.stdout.strip()[:200]!r}")
        for row in rows:
            if row.get("title") == title:
                num = str(row.get("number", ""))
                if not re.fullmatch(r"[0-9]+", num):
                    raise RuntimeError(f"gh issue list returned non-numeric issue: {num!r}")
                return num
        return ""

    def view_body(num: str) -> str:
        return gh(["issue", "view", num, "--json", "body", "-q", ".body"]).stdout

    def comment(num: str, text: str) -> None:
        gh(["issue", "comment", num, "--body-file", "-"], stdin_text=text)

    try:
        if ns.retire_title:
            legacy = find_issue(ns.retire_title, "open")
            if legacy:
                comment(legacy, f"retired as of {today}: obligations now track one issue each")
                gh(["issue", "close", legacy])
                print(f"notify_poster: retired legacy issue {legacy}")
        for key in sorted(live):
            title = f"{ns.prefix}{key}"
            want, logins, _unmapped = want_body(key, live[key])
            num = find_issue(title, "open")
            if not num:
                closed = find_issue(title, "closed")
                if closed:
                    gh(["issue", "reopen", closed])
                    new = sorted(set(logins) - have_logins(view_body(closed)))
                    edit = ["issue", "edit", closed, "--body-file", "-"]
                    for login in new:
                        edit += ["--add-assignee", login]
                    gh(edit, stdin_text=want)
                    comment(closed, f"recurring as of {today}:\n" + "\n".join(live[key]))
                    print(f"notify_poster: reopened issue {closed} for {key}")
                else:
                    create = ["issue", "create", "--title", title, "--body-file", "-"]
                    for login in logins:
                        create += ["--assignee", login]
                    created = gh(create, stdin_text=want)
                    print(f"notify_poster: created {created.stdout.strip() or '(no url)'} for {key}")
                continue
            have = view_body(num)
            if have != want:
                new = sorted(set(logins) - have_logins(have))
                edit = ["issue", "edit", num, "--body-file", "-"]
                for login in new:
                    edit += ["--add-assignee", login]
                gh(edit, stdin_text=want)
                comment(num, f"update as of {today}:\n" + "\n".join(live[key]))
                print(f"notify_poster: updated issue {num} for {key}")
            else:
                print(f"notify_poster: issue {num} for {key} unchanged")
        swept = gh(["issue", "list", "--state", "open", "--search", f'in:title "{ns.prefix}"',
                    "--json", "number,title"])
        try:
            open_rows = json.loads(swept.stdout.strip() or "[]")
        except ValueError:
            raise RuntimeError(f"gh issue list returned non-JSON: {swept.stdout.strip()[:200]!r}")
        for row in open_rows:
            title = row.get("title", "")
            if not title.startswith(ns.prefix):
                continue
            if title[len(ns.prefix):] in live:
                continue
            num = str(row.get("number", ""))
            if not re.fullmatch(r"[0-9]+", num):
                raise RuntimeError(f"gh issue list returned non-numeric issue: {num!r}")
            comment(num, f"clear as of {today}")
            gh(["issue", "close", num])
            print(f"notify_poster: closed cleared issue {num} ({title})")
    except RuntimeError as e:
        return fail(str(e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
