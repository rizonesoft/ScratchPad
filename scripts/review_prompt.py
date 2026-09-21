"""Review-prompt construction and reviewer-output validation (D00 T01 §17).

Prompts are ephemeral `/tmp` files, but the rules that build them are
checked-in code so a fixture can prove them: delimiter tags are unique per
prompt (item 14: fixed delimiters are injectable from TODO text), prompt
bytes are canonicalized before counting (item 5: UTF-8/LF, so Windows and
WSL checkouts agree), and reviewer output is validated whole (item 15: one
valid-looking row must not mask malformed trailing findings).
"""

import codecs
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import threading
import time

try:
    import fcntl
except ImportError:  # Windows
    fcntl = None
try:
    import msvcrt
except ImportError:  # Unix
    msvcrt = None

PANEL_LENSES = ("adversarial", "consistency", "integration", "record")
PANEL_VERDICTS = ("approve", "needs-attention", "advisory")
# Runner-output verdicts only (the prompt mandates bare `**<lens>:
# <verdict>**` headers, with nothing else on the line except an optional
# finding count): the line opens with `**`, names one lens and one
# verdict, and ends. The count is one alternation taking exactly one
# count in either Markdown position (`**v (2)**` or `**v** (2)`; models
# emit both, so both are legal), never both: two optional groups once
# accepted `**v (2)** (3)`. End-anchoring is what keeps a detail line
# quoting a header (`**record: approve** claim is stale`, with or
# without a count) a detail; dash-, backtick-, or bare-lens-opened
# lines are details, never verdicts. Stated residual: a detail line
# consisting of exactly a bare header (count or not) for an
# already-seen lens still reads as a repeat (quoting with any
# surrounding prose is safe).
# Count grammar (D00 T01 §19 item 20, bounded D00 T01 §23): ASCII
# digits only (`\d` would admit Unicode digits), no sign, no
# whitespace, no leading zeros (the canonical form is bare `0` or a
# nonzero digit first), zero allowed, at most four digits (no review
# round holds ten thousand findings; the cap keeps a hostile count
# from reaching `int()` unbounded, which raises past 4300 digits
# instead of failing closed).
_COUNT_MAX_DIGITS = 4
_COUNT_INNER = r"(?:0|[1-9][0-9]{0," + str(_COUNT_MAX_DIGITS - 1) + r"})"
# Reviewer-output bounds (D00 T01 §23): a hostile or malformed
# reviewer can exhaust parser resources before semantic comparison,
# so both checkers refuse oversized output first. The caps are
# generous multiples of any plausible review (a panel round is four
# verdicts plus details; a plan round is one line per finding), so a
# legitimate reviewer never nears them.
OUTPUT_MAX_BYTES = 2**20
OUTPUT_MAX_LINES = 100_000
# Runner-output token cap (D00 T01 §34 item 3): one whitespace-delimited
# run longer than this kills the producer. 4096 sits below the 4300
# digit interpreter cliff (no single token can crash a downstream
# int()) and above every legitimate digest, path, or URL.
TOKEN_MAX_CHARS = 4096
# Runner wall-clock default (D00 T01 §34 item 3): the panel precedent
# (600s panels, 900s plan reviews) with one default; --timeout
# overrides per run.
RUN_TIMEOUT_SECS = 600
# Runner wall-clock ceiling (D00 T01 §34 R1 adversarial 3): infinite
# or astronomic timeouts overflow the queue wait instead of bounding
# it, so --timeout and the library gate both refuse past one day (a
# longer round wants this constant moved, not removed).
RUN_TIMEOUT_MAX_SECS = 86400
# Producer stderr is diagnostic context only: captured to 64KB, then
# truncated (a chatty producer must not exhaust the collector).
STDERR_MAX_BYTES = 2**16
# Pending-reader chunks (D00 T01 §34 R2 adversarial 1): an unbounded
# queue lets a fast producer outrun a stalled validator without
# bound, so 32 chunks (2MB) of backpressure cap the backlog and the
# producer blocks on the pipe instead.
COLLECT_QUEUE_CHUNKS = 32
_PANEL_LINE_RE = re.compile(
    r"^\s*\*{2}\s*(adversarial|consistency|integration|record)\*{0,2}\s*:?\s*"
    r"(approve|needs-attention|advisory)(?:\s*\((?P<c1>" + _COUNT_INNER + r")\)\*{0,2}|\*{0,2}\s*\((?P<c2>"
    + _COUNT_INNER + r")\)|\*{0,2})\s*$"
)
# The same verdict shape with an over-long count (D00 T01 §23 review
# R1): a 5-digit count is not a verdict (the grammar caps at 4), but
# failing it as a stray line would name neither the count nor the cap,
# so the checker recognizes the shape and says which bound broke.
_LONG_DIGITS = r"[0-9]{%d,}" % (_COUNT_MAX_DIGITS + 1)
_PANEL_LONG_COUNT_RE = re.compile(
    r"^\s*\*{2}\s*(?:adversarial|consistency|integration|record)\*{0,2}\s*:?\s*"
    r"(?:approve|needs-attention|advisory)(?:\s*\(" + _LONG_DIGITS + r"\)\*{0,2}|\*{0,2}\s*\(" + _LONG_DIGITS + r"\))\s*$"
)
# A declared count is cross-checked against the findings it claims
# (D00 T01 §19 item 19): a finding is one numbered item (`1. ...`), one
# per line, so the count must equal the numbered-item tally under its
# verdict. Unnumbered detail lines are prose, never findings: they ride
# along without moving the tally. No declared count, no check: details
# in any shape pass, as before. ASCII digits like the count grammar: a
# Unicode-digit item is prose, not a finding.
_FINDING_ITEM_RE = re.compile(r"^\s*[0-9]+\.\s")


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


# Delimiter-tag contract (D00 T01 §19 item 11): 64 bits of entropy
# (`secrets.token_hex(8)`), collision-checked against every payload
# chunk, with bounded retries. A tag that appears in the payload would
# let TODO text forge structure, so generation retries until the tag is
# absent (a collision at 64 bits is a broken RNG, not luck, which is
# why exhaustion raises instead of degrading to a weak tag).
TAG_ENTROPY_BITS = 64
TAG_MAX_ATTEMPTS = 100


def fence_chunks_checked(prefix: str, chunks: list[tuple[str, str]]) -> tuple[str, str]:
    """Fence chunks under a fresh tag proven absent from the payload.

    Returns (tag, prompt). Raises RuntimeError if every attempt collides.
    """
    bodies = [body for _, body in chunks]
    for _ in range(TAG_MAX_ATTEMPTS):
        tag = unique_tag(prefix)
        if all(tag not in body for body in bodies):
            return tag, fence_chunks(tag, chunks)
    raise RuntimeError(f"tag collided with the payload {TAG_MAX_ATTEMPTS} times; refusing a weak tag")


def canonical_prompt_bytes(text: str) -> bytes:
    """Prompt bytes as the manifest counts them: LF newlines, UTF-8."""
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def _output_within_bounds(text: str) -> tuple[bool, str] | None:
    """The size gate both checkers run before semantic comparison, or
    None when the output fits. Bytes count UTF-8; lines count newline
    splits; both bounds are inclusive. The byte measure encodes in
    chunks with early exit, never a second full copy of the input, so
    a hostile string costs the gate bounded extra memory; the line
    split only runs once bytes fit, so it is bounded too. NUL has no
    legitimate reading in review text (D00 T01 §34 item 4) and fails
    here, so library callers get the same verdict as the runner."""
    if "\x00" in text:
        return False, f"NUL byte at offset {text.index(chr(0))}"
    total = 0
    for i in range(0, len(text), 8192):
        total += len(text[i:i + 8192].encode("utf-8"))
        if total > OUTPUT_MAX_BYTES:
            return False, f"output exceeds {OUTPUT_MAX_BYTES} bytes"
    if len(text.splitlines()) > OUTPUT_MAX_LINES:
        return False, f"output exceeds {OUTPUT_MAX_LINES} lines"
    return None


def check_panel_output(text: str) -> tuple[bool, str]:
    """Whole-output validation for a panel round: every lens verdicts
    exactly once, and every other non-blank line is a detail line under the
    most recent non-approve verdict (an approve takes no details, and
    nothing precedes the first verdict). A declared finding count must
    equal the numbered-item tally under its verdict. Returns (ok,
    reason); the first bad line is the reason, so trailing garbage after
    four good verdicts still fails instead of masking."""
    bounded = _output_within_bounds(text)
    if bounded is not None:
        return bounded
    seen: dict[str, int] = {}
    detail_open = False
    declared: int | None = None
    tally = 0
    open_lens = ""
    open_line = 0

    def close_block() -> tuple[bool, str] | None:
        if declared is not None and tally != declared:
            return False, (
                f"line {open_line} declares {declared} findings "
                f"but {tally} numbered items follow under {open_lens}"
            )
        return None

    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        m = _PANEL_LINE_RE.match(line)
        if m:
            bad = close_block()
            if bad:
                return bad
            lens = m.group(1)
            if lens in seen:
                return False, f"line {lineno} repeats the {lens} verdict (first at line {seen[lens]})"
            seen[lens] = lineno
            detail_open = m.group(2) != "approve"
            raw = m.group("c1") or m.group("c2")
            # An approve takes no details, so its tally is fixed at
            # zero: `approve (0)` passes, `approve (2)` fails.
            declared = int(raw) if raw is not None else None
            tally = 0
            open_lens, open_line = lens, lineno
            continue
        if _PANEL_LONG_COUNT_RE.match(line):
            return False, f"line {lineno} count exceeds {_COUNT_MAX_DIGITS} digits"
        if not seen:
            return False, f"line {lineno} precedes the first verdict: {line.strip()[:80]}"
        if not detail_open:
            return False, f"line {lineno} is not a verdict or finding detail: {line.strip()[:80]}"
        if _FINDING_ITEM_RE.match(line):
            tally += 1
    bad = close_block()
    if bad:
        return bad
    missing = [lens for lens in PANEL_LENSES if lens not in seen]
    if missing:
        return False, f"missing verdicts: {', '.join(missing)}"
    return True, "four lenses, one verdict each"


CHECKER_VERSION = "review_prompt/1"


def _producer_binding(argv: list[str]) -> tuple[str, str]:
    """Model and effort taken from a producer argv, or empty when absent."""
    model = ""
    effort = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-m", "--model") and i + 1 < len(argv):
            model = argv[i + 1]
            i += 2
            continue
        if arg == "--effort" and i + 1 < len(argv):
            effort = argv[i + 1]
            i += 2
            continue
        if arg.startswith("--model="):
            model = arg.split("=", 1)[1]
        elif arg.startswith("-c") and "model_reasoning_effort=" in arg:
            effort = arg.split("model_reasoning_effort=", 1)[1].strip("\"'")
        elif arg == "-c" and i + 1 < len(argv) and "model_reasoning_effort=" in argv[i + 1]:
            effort = argv[i + 1].split("model_reasoning_effort=", 1)[1].strip("\"'")
            i += 2
            continue
        i += 1
    return model, effort


def _dirty_state() -> str:
    """Whether the checkout has uncommitted changes. Unknown if git cannot say."""
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    if out.returncode != 0:
        return "unknown"
    return "dirty" if out.stdout.strip() else "clean"


def clone_token() -> str:
    """Eight hex chars from this checkout's path (D00 T01 §55 item 20).

    Two clones mint different run IDs even when neither has seen the
    other's claims. The same checkout keeps one token, so its own
    `-rN` sequence still walks.
    """
    root = str(Path(__file__).resolve().parent.parent)
    return hashlib.sha256(root.encode("utf-8")).hexdigest()[:8]


def next_run_id(
    todo_path: str,
    section: int,
    family: str,
    date: str,
    *texts: str,
    clone: str = "",
) -> str:
    """The canonical run ID for a review run (D00 T01 §20 item 1).

    The base is `<YYYYMMDD>-D<dom>-T<num>-S<section>-<family>`, derived
    from the TODO path (`todo/<dom>-<name>/TODO-<num>-*.md`); the suffix
    walks past every run already claimed in the given texts (marker and
    manifest lines): no claim, no suffix, else `-r<max+1>`. One
    generator, so two writers cannot mint competing identities by hand.
    Raises ValueError on an off-shape input. Numbering: within one date
    base the bare base is run 1 and `-rN` is run N for N >= 2, so a
    claimed base (or `-r1`, its accepted synonym) yields `-r2` next; a
    later day mints a bare base again.
    """
    if not re.fullmatch(r"[a-z0-9]+", family):
        raise ValueError(f"family {family!r} is outside [a-z0-9]+")
    if not re.fullmatch(r"\d{8}", date):
        raise ValueError(f"date {date!r} is outside YYYYMMDD")
    parts = todo_path.replace("\\", "/").split("/")
    try:
        dom = parts[-2].split("-")[0]
        num = parts[-1].split("-")[1]
    except IndexError:
        raise ValueError(f"TODO path {todo_path!r} carries no domain/number") from None
    if not re.fullmatch(r"\d+", dom) or not re.fullmatch(r"\d+", num):
        raise ValueError(f"TODO path {todo_path!r} carries no domain/number")
    if not isinstance(section, int) or isinstance(section, bool) or section < 1:
        raise ValueError(f"section {section!r} is outside positive-int")
    if clone and not re.fullmatch(r"[0-9a-f]{8}", clone):
        raise ValueError(f"clone {clone!r} is outside 8 lowercase hex")
    base = f"{date}-D{dom}-T{num}-S{section}-{family}"
    if clone:
        base = f"{base}-c{clone}"
    taken = set()
    for text in texts:
        for rm in re.finditer(r"\brun\s+(\S+?)(?=[,;)]|\s|$)", text):
            taken.add(rm.group(1))
    if base not in taken and not any(t.startswith(base + "-r") for t in taken):
        return base
    mx = 1
    for t in taken:
        if t == base:
            mx = max(mx, 1)
        elif t.startswith(base + "-r"):
            tail = t[len(base) + 2:]
            # ASCII digits of sane length only (D00 T01 §34 item 5):
            # `isdigit` admits `²` (which `int()` rejects) and
            # unbounded runs (which `int()` refuses past 4300
            # digits), so both fail closed with a naming diagnostic
            # instead of crashing. Non-digit tails stay non-claims.
            if tail.isdigit() and (not tail.isascii() or len(tail) > 9):
                shown = tail[:20] + ("..." if len(tail) > 20 else "")
                raise ValueError(f"run suffix -r{shown} is outside ASCII digits of length 1-9")
            if tail.isdigit():
                mx = max(mx, int(tail))
    return f"{base}-r{mx + 1}"


def check_plan_output(text: str) -> tuple[bool, str]:
    """Whole-output validation for a plan-review round: every non-blank line
    is one `- ` finding (or the round is an explicit no-findings
    statement). Returns (ok, reason)."""
    bounded = _output_within_bounds(text)
    if bounded is not None:
        return bounded
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


def _read_scan_files(paths: list[str], prefix: str) -> list[str]:
    """Claim texts for run minting, shared by run-id and run.

    A genesis run mints before its findings file exists, so a missing
    scan file warns and reads as no claims (collisions still fail loud
    downstream at the duplicate-run check); other read errors stay
    fatal with a naming diagnostic.
    """
    import sys

    texts = []
    for path in paths:
        try:
            with open(path, encoding="utf-8") as fh:
                texts.append(fh.read())
        except FileNotFoundError:
            print(f"{prefix}: warning: {path} does not exist, reading as no claims", file=sys.stderr)
        except OSError as exc:
            print(f"{prefix}: cannot read {path}: {exc}", file=sys.stderr)
            sys.exit(2)
        except UnicodeDecodeError as exc:
            # Malformed scans fail named (D00 T01 §34 R2 adversarial
            # 2): UnicodeDecodeError is not an OSError, so without
            # this leg both run-id and run crash on hostile bytes.
            print(f"{prefix}: cannot decode {path}: {exc}", file=sys.stderr)
            sys.exit(2)
    return texts


def collect_producer(argv: list[str], prompt: bytes, timeout_secs: float) -> tuple[bool, str, dict]:
    """Run one reviewer producer under streaming bounds (D00 T01 §34
    items 3-4): the prompt bytes feed stdin while stdout streams
    through the byte, line, token, and wall-clock gates plus strict
    UTF-8 decoding and NUL rejection. Any excess kills the producer
    (threads + queue, so no platform needs select); a nonzero producer
    exit fails even with well-shaped output. Returns (ok, text,
    info) on success with the exact text, else (False, reason, info);
    info always carries returncode, stderr_tail, bytes_read,
    lines_read, and the raw collected bytes (partial on failure, for
    the artifact store). Raises ValueError on a timeout outside 0 <
    seconds <= RUN_TIMEOUT_MAX_SECS (infinite, NaN, non-positive, or
    non-numeric: fail closed before spawning).
    """
    import queue

    try:
        _bounded = 0 < timeout_secs <= RUN_TIMEOUT_MAX_SECS
    except TypeError:
        _bounded = False
    if not _bounded:
        raise ValueError(f"timeout {timeout_secs!r} is outside 0 < seconds <= {RUN_TIMEOUT_MAX_SECS} (finite)")
    started = time.monotonic()
    try:
        proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        # The raw key rides even here (D00 T01 §34 R2 integration
        # 1): the run branch stores info["raw"] unconditionally, so
        # an unstartable producer must ledger an empty artifact
        # instead of crashing on the missing key.
        return False, f"producer failed to start: {exc}", {"returncode": None, "stderr_tail": "", "bytes_read": 0, "lines_read": 0, "raw": b""}

    def _feed() -> None:
        try:
            assert proc.stdin is not None
            proc.stdin.write(prompt)
            proc.stdin.close()
        except (BrokenPipeError, OSError, ValueError):
            pass

    chunks: queue.Queue = queue.Queue(maxsize=COLLECT_QUEUE_CHUNKS)
    _EOF, _EXC = object(), object()

    # read1, not read: read() blocks for a full buffer, holding back
    # the partial chunk a mid-stream gate must see now (D00 T01 §34 R1
    # integration 2: a final short write would stall the line gate to
    # the wall clock).
    def _drain() -> None:
        try:
            assert proc.stdout is not None
            while True:
                data = proc.stdout.read1(65536)
                if not data:
                    chunks.put((_EOF, b""))
                    return
                chunks.put((None, data))
        except (OSError, ValueError) as exc:
            chunks.put((_EXC, exc))

    errbuf: list[bytes] = []

    def _derr() -> None:
        # Drain to EOF while retaining only the cap (D00 T01 §34 R1
        # adversarial 2): stopping the drain at the cap lets a
        # still-writing producer fill the pipe, block, and fail only
        # at the wall clock.
        try:
            assert proc.stderr is not None
            kept = 0
            while True:
                data = proc.stderr.read1(65536)
                if not data:
                    return
                if kept < STDERR_MAX_BYTES:
                    errbuf.append(data[: STDERR_MAX_BYTES - kept])
                    kept += len(errbuf[-1])
        except (OSError, ValueError):
            pass

    feeder = threading.Thread(target=_feed, daemon=True)
    reader = threading.Thread(target=_drain, daemon=True)
    errout = threading.Thread(target=_derr, daemon=True)
    feeder.start()
    reader.start()
    errout.start()

    def _reap() -> int | None:
        try:
            proc.kill()
        except OSError:
            pass
        try:
            return proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            return proc.returncode

    def _drain_queue() -> None:
        # Free a reader blocked in put (D00 T01 §34 R2 adversarial
        # 1): the bounded queue backpressures the reader, so after
        # the reap the main loop takes until EOF, error, or quiet
        # instead of stranding the thread.
        while True:
            try:
                kind, _ = chunks.get(timeout=5)
            except queue.Empty:
                return
            if kind is not None:
                return

    def _stderr_tail() -> str:
        raw = b"".join(errbuf)[:STDERR_MAX_BYTES].decode("utf-8", "replace")
        flat = " ".join(raw.split())
        return flat[:200]

    raw_parts: list[bytes] = []
    text_parts: list[str] = []
    decoder = codecs.getincrementaldecoder("utf-8")()
    total_bytes = 0
    total_lines = 0
    carry = 0
    # Incremental splitlines count (D00 T01 §34 R1 integration 2): a
    # per-chunk join would go quadratic under hostile short reads,
    # so breaks count per piece with the \r\n split-pair adjusted and
    # the unterminated tail added exactly like splitlines.
    _breaks = 0
    _tail_cr = False
    _tail_break = False
    _seen_text = False

    def _count_breaks(piece: str) -> None:
        nonlocal _breaks, _tail_cr, _tail_break, _seen_text, total_lines
        _n = len(re.findall(r"\r\n|[\n\r\x0b\x0c\x1c\x1d\x1e\x85\u2028\u2029]", piece))
        if _tail_cr and piece.startswith("\n"):
            _n -= 1
        _breaks += _n
        if piece:
            _tail_cr = piece.endswith("\r")
            _tail_break = piece[-1] in "\n\r\x0b\x0c\x1c\x1d\x1e\x85\u2028\u2029"
            _seen_text = True
        total_lines = _breaks + (0 if (not _seen_text or _tail_break) else 1)

    reason = ""
    eof = False
    while not eof:
        remaining = timeout_secs - (time.monotonic() - started)
        if remaining <= 0:
            reason = f"producer exceeded {timeout_secs:g}s wall clock"
            break
        try:
            kind, payload = chunks.get(timeout=remaining)
        except queue.Empty:
            reason = f"producer exceeded {timeout_secs:g}s wall clock"
            break
        if kind is _EXC:
            reason = f"producer output unreadable: {payload}"
            break
        if kind is _EOF:
            eof = True
            break
        base = total_bytes
        total_bytes += len(payload)
        # The failing chunk is evidence (D00 T01 §34 R1 record 1):
        # raw keeps every collected byte including the one that trips
        # a gate, so the stored artifact and digest preserve it.
        raw_parts.append(payload)
        if total_bytes > OUTPUT_MAX_BYTES:
            reason = f"output exceeds {OUTPUT_MAX_BYTES} bytes"
            break
        nul = payload.find(b"\x00")
        if nul != -1:
            reason = f"NUL byte at byte offset {base + nul}"
            break
        try:
            # Error offsets index the decoder's combined buffered
            # plus new bytes (D00 T01 §34 R2 adversarial 3: probed, a
            # split sequence reports exc.start against the held
            # prefix), so the held count comes off the base.
            _held = len(decoder.getstate()[0])
            piece = decoder.decode(payload)
        except UnicodeDecodeError as exc:
            reason = f"malformed UTF-8 at byte offset {base - _held + exc.start}"
            break
        text_parts.append(piece)
        # Logical lines, exactly like the checker (D00 T01 §34 R1
        # integration 2): every splitlines break counts once (a \r\n
        # split across pieces counts on its \r half), so a final
        # unterminated line trips the runner boundary mid-stream
        # instead of reaching the checker after the producer ends.
        _count_breaks(piece)
        if total_lines > OUTPUT_MAX_LINES:
            reason = f"output exceeds {OUTPUT_MAX_LINES} lines"
            break
        # Tokens are characters delimited by Unicode whitespace (D00
        # T01 §34 R1 adversarial 1): the str pattern measures what
        # the cap names, and carry rides in chars across read chunks
        # (an empty piece means the decoder held a split code point,
        # so the run continues).
        for match in re.finditer(r"\S+", piece):
            runlen = len(match.group(0)) + (carry if match.start() == 0 else 0)
            if runlen > TOKEN_MAX_CHARS:
                reason = f"token exceeds {TOKEN_MAX_CHARS} chars"
                break
        if reason:
            break
        if re.search(r"\s$", piece):
            carry = 0
        elif piece:
            tail = re.search(r"\S+$", piece)
            assert tail is not None
            run = tail.group(0)
            carry = len(run) + (carry if tail.start() == 0 else 0)
    if not reason and eof:
        try:
            final = decoder.decode(b"", final=True)
        except UnicodeDecodeError as exc:
            # End-relative, unlike the mid-stream gate above: only a
            # valid-prefix truncation can reach the flush (anything
            # invalid already raised), so the defect sits at the
            # stream end.
            reason = f"malformed UTF-8 at byte offset {total_bytes + exc.start}"
            final = ""
        if not reason and final:
            text_parts.append(final)
            # The flush can complete a line break or a token run (a
            # split multi-byte break or an over-cap tail must not slip
            # past the per-chunk gates): run it through the same
            # incremental count.
            _count_breaks(final)
            if total_lines > OUTPUT_MAX_LINES:
                reason = f"output exceeds {OUTPUT_MAX_LINES} lines"
            else:
                fm = re.match(r"\S+", final)
                if fm is not None and carry + len(fm.group(0)) > TOKEN_MAX_CHARS:
                    reason = f"token exceeds {TOKEN_MAX_CHARS} chars"
    rc = proc.returncode
    if reason:
        rc = _reap()
        _drain_queue()
    else:
        remaining = timeout_secs - (time.monotonic() - started)
        try:
            rc = proc.wait(timeout=max(remaining, 0))
        except subprocess.TimeoutExpired:
            reason = f"producer exceeded {timeout_secs:g}s wall clock"
            rc = _reap()
    errout.join(timeout=5)
    info = {"returncode": rc, "stderr_tail": _stderr_tail(), "bytes_read": total_bytes, "lines_read": total_lines, "raw": b"".join(raw_parts)}
    if reason:
        return False, reason, info
    if rc != 0:
        tail = f": {info['stderr_tail']}" if info["stderr_tail"] else ""
        return False, f"producer exited {rc}{tail}", info
    return True, "".join(text_parts), info


def _ledger_claims(store: str) -> tuple[str, set[str]]:
    """Claim text plus claimed run IDs from a review-run ledger (D00
    T01 §34 R1 integration 1): receipts feed the run-ID minter as
    `run <id>` lines, so a repeated run walks past its own prior
    receipt. A missing ledger is the first run (no claims); an
    unreadable one raises (minting blind would duplicate rows).
    """
    path = os.path.join(store, "ledger.jsonl")
    try:
        with open(path, encoding="utf-8") as fh:
            data = fh.read()
    except FileNotFoundError:
        return "", set()
    ids = re.findall(r'"run"\s*:\s*"([^"]+)"', data)
    return "".join(f"run {i}\n" for i in ids), set(ids)


@contextlib.contextmanager
def _held_ledger_lock(store: str):
    """Mutual exclusion for the run-ledger append (D00 T01 §34 R2
    record 1): the guard read and the append hold one lock, so two
    concurrent runs cannot both observe an ID as absent. A sidecar
    lock file carries the mutex (never the ledger handle: no offset
    games on either side); locks release on close and crash, so the
    file never goes stale. fcntl on Unix, msvcrt on Windows (the two
    do not interoperate, but the store is always local); no
    primitive fails closed rather than appending unlocked.
    """
    if fcntl is None and msvcrt is None:
        raise OSError("no file-locking primitive for the run ledger")
    os.makedirs(store, exist_ok=True)
    with open(os.path.join(store, "ledger.lock"), "a+b") as fh:
        if os.fstat(fh.fileno()).st_size == 0:
            fh.write(b"x")
            fh.flush()
        if fcntl is not None:
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
        else:
            assert msvcrt is not None
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_LOCK, 1)
        try:
            yield
        finally:
            if fcntl is not None:
                fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
            else:
                assert msvcrt is not None
                fh.seek(0)
                msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)


def _record_run(store: str, run_id: str, mint, build) -> tuple[str, dict]:
    """Finalize one run ID and append its receipt atomically: under
    the ledger lock the claims re-read, a taken ID re-mints once
    (nothing interleaves, so one pass suffices), and the built
    receipt appends. Returns the final ID plus receipt.
    """
    with _held_ledger_lock(store):
        claims_text, ids = _ledger_claims(store)
        if run_id in ids:
            run_id = mint(claims_text)
        receipt = build(run_id)
        with open(os.path.join(store, "ledger.jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(receipt, sort_keys=True) + "\n")
        return run_id, receipt


if __name__ == "__main__":
    import sys

    # `tag` serves ad-hoc uses: one randomness source, no copies
    # (`$RANDOM` is a bash-ism that degrades to a bare timestamp under sh).
    # The prompt templates use `fence`, which checks the tag against the
    # payload before the prompt ships (a bare tag plus shell echo would
    # never check).
    if len(sys.argv) == 3 and sys.argv[1] == "tag":
        print(unique_tag(sys.argv[2]))
        sys.exit(0)
    if len(sys.argv) >= 4 and sys.argv[1] == "fence":
        chunks = []
        for pair in sys.argv[3:]:
            title, sep, path = pair.partition("=")
            if not sep or not title or not path:
                print(f"fence: want <title>=<path>, got {pair!r}", file=sys.stderr)
                sys.exit(2)
            try:
                with open(path, encoding="utf-8") as fh:
                    chunks.append((title, fh.read()))
            except OSError as exc:
                print(f"fence: cannot read {path}: {exc}", file=sys.stderr)
                sys.exit(2)
        try:
            tag, prompt = fence_chunks_checked(sys.argv[2], chunks)
        except RuntimeError as exc:
            print(f"fence: {exc}", file=sys.stderr)
            sys.exit(1)
        print(f"TAG {tag}")
        print(prompt, end="")
        sys.exit(0)
    if len(sys.argv) >= 6 and sys.argv[1] == "run-id":
        # run-id <todo-path> <section> <family> <YYYYMMDD> <scan-file>...
        # The date rides explicit (no hidden clock): the caller fills it
        # from `date -u +%Y%m%d` (the skill's plan-review paragraph shows
        # the invocation; scan files are the findings files holding
        # claimed runs).
        try:
            section = int(sys.argv[3])
        except ValueError:
            print(f"run-id: section {sys.argv[3]!r} is not an integer", file=sys.stderr)
            sys.exit(2)
        texts = _read_scan_files(sys.argv[6:], "run-id")
        try:
            print(
                next_run_id(
                    sys.argv[2],
                    section,
                    sys.argv[4],
                    sys.argv[5],
                    *texts,
                    clone=clone_token(),
                )
            )
        except ValueError as exc:
            print(f"run-id: {exc}", file=sys.stderr)
            sys.exit(2)
        sys.exit(0)
    if len(sys.argv) >= 10 and sys.argv[1] == "run":
        # run <panel|plan> <prompt-file> <todo-path> <section> <family>
        #   <YYYYMMDD> [--timeout S] [--store DIR] [--candidate SHA]
        #   <scan-file>... -- <producer> [args...]
        # One atomic review run (D00 T01 §34 item 7): mint the run,
        # execute the producer bounded, validate its output, store the
        # bytes content-addressed, and append the run ledger. Prompt
        # and scans read strict (item 4: malformed bytes fail, never
        # corrupt); the receipt prints the run, the artifact, and a
        # Provenance line. Exit 0 PASS, 1 FAIL, 2 usage/setup.
        kind = sys.argv[2]
        if kind not in ("panel", "plan"):
            print(f"run: kind {kind!r} is outside panel|plan", file=sys.stderr)
            sys.exit(2)
        prompt_path, todo_path = sys.argv[3], sys.argv[4]
        try:
            run_section = int(sys.argv[5])
        except ValueError:
            print(f"run: section {sys.argv[5]!r} is not an integer", file=sys.stderr)
            sys.exit(2)
        family, date = sys.argv[6], sys.argv[7]
        timeout: float = RUN_TIMEOUT_SECS
        store = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "review-runs")
        candidate = ""
        scans: list[str] = []
        rest = sys.argv[8:]
        if "--" not in rest:
            print("run: want <scan-file>... -- <producer> [args...]", file=sys.stderr)
            sys.exit(2)
        sep = rest.index("--")
        pre, producer = rest[:sep], rest[sep + 1:]
        if not producer:
            print("run: no producer after --", file=sys.stderr)
            sys.exit(2)
        i = 0
        while i < len(pre):
            if pre[i] == "--timeout" and i + 1 < len(pre):
                try:
                    timeout = float(pre[i + 1])
                except ValueError:
                    timeout = -1
                if not 0 < timeout <= RUN_TIMEOUT_MAX_SECS:
                    print(
                        f"run: --timeout takes a positive number of seconds up to {RUN_TIMEOUT_MAX_SECS}, got {pre[i + 1]!r}",
                        file=sys.stderr,
                    )
                    sys.exit(2)
                i += 2
            elif pre[i] == "--store" and i + 1 < len(pre):
                store = pre[i + 1]
                i += 2
            elif pre[i] == "--candidate" and i + 1 < len(pre):
                candidate = pre[i + 1]
                i += 2
            elif pre[i].startswith("--"):
                print(f"run: unknown option {pre[i]!r}", file=sys.stderr)
                sys.exit(2)
            else:
                scans.append(pre[i])
                i += 1
        try:
            with open(prompt_path, encoding="utf-8") as fh:
                prompt_text = fh.read()
        except FileNotFoundError:
            print(f"run: prompt file {prompt_path} does not exist", file=sys.stderr)
            sys.exit(2)
        except (OSError, UnicodeDecodeError) as exc:
            print(f"run: cannot read prompt file {prompt_path}: {exc}", file=sys.stderr)
            sys.exit(2)
        claim_texts = _read_scan_files(scans, "run")
        try:
            ledger_text, _ = _ledger_claims(store)
        except (OSError, ValueError) as exc:
            print(f"run: cannot read the run ledger under {store}: {exc}", file=sys.stderr)
            sys.exit(1)
        try:
            run_id = next_run_id(
                todo_path,
                run_section,
                family,
                date,
                *claim_texts,
                ledger_text,
                clone=clone_token(),
            )
        except ValueError as exc:
            print(f"run: {exc}", file=sys.stderr)
            sys.exit(2)
        if not candidate:
            try:
                git = subprocess.run(
                    ["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30
                )
                candidate = git.stdout.strip() if git.returncode == 0 else ""
            except OSError:
                candidate = ""
            if re.fullmatch(r"[0-9a-fA-F]{40}", candidate) is None:
                print("run: cannot resolve HEAD for provenance (pass --candidate SHA)", file=sys.stderr)
                sys.exit(2)
        elif re.fullmatch(r"[0-9a-fA-F]{7,40}", candidate) is None:
            print(f"run: --candidate takes 7-40 hex chars, got {candidate!r}", file=sys.stderr)
            sys.exit(2)
        ok, payload, info = collect_producer(producer, canonical_prompt_bytes(prompt_text), timeout)
        raw = info["raw"]
        digest = hashlib.sha256(raw).hexdigest()
        try:
            os.makedirs(store, exist_ok=True)
            artifact = os.path.join(store, digest)
            # PID-suffixed temp (D00 T01 §34 R1 integration 1): two
            # concurrent runs storing identical bytes share the
            # digest, so a fixed temp name lets one rename steal the
            # other's file; distinct temps converge on one artifact.
            tmp = f"{artifact}.tmp.{os.getpid()}"
            try:
                with open(tmp, "wb") as fh:
                    fh.write(raw)
                os.replace(tmp, artifact)
            except OSError:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                raise
        except OSError as exc:
            print(f"run: cannot store artifact under {store}: {exc}", file=sys.stderr)
            sys.exit(1)
        verdict = ""
        if ok:
            checker = check_panel_output if kind == "panel" else check_plan_output
            passed, why = checker(payload)
            verdict = ("PASS " if passed else "FAIL ") + why
        else:
            verdict = "FAIL " + payload
        # Run uniqueness (D00 T01 §34 R1 integration 1, locked D00
        # T01 §34 R2 record 1): the mint already walked past the
        # ledger claims read before the producer ran; recording
        # re-checks under the lock and re-mints once when taken.
        try:
            run_id, receipt = _record_run(
                store,
                run_id,
                lambda ct: next_run_id(
                    todo_path, run_section, family, date, *claim_texts, ct, clone=clone_token()
                ),
                lambda rid, _prompt=prompt_text, _producer=list(producer): {
                    "run": rid,
                    "kind": kind,
                    "digest": "sha256:" + digest,
                    "verdict": verdict,
                    "artifact": artifact,
                    "prompt_sha256": hashlib.sha256(
                        canonical_prompt_bytes(_prompt)
                    ).hexdigest(),
                    "model": _producer_binding(_producer)[0],
                    "effort": _producer_binding(_producer)[1],
                    "producer": _producer,
                    "checker": CHECKER_VERSION,
                    "dirty": _dirty_state(),
                },
            )
        except (OSError, ValueError) as exc:
            print(f"run: cannot record the run under {store}: {exc}", file=sys.stderr)
            sys.exit(1)
        try:
            shown = os.path.relpath(artifact, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
            if shown.startswith(".."):
                shown = artifact
        except ValueError:
            shown = artifact
        command = shlex.join(sys.argv).replace(";", " ").replace("\n", " ")
        print(verdict)
        print(f"run {run_id}")
        print(f"artifact {shown}")
        print(
            f"Provenance: candidate {candidate}; command `{command}`; exit {0 if verdict.startswith('PASS') else 1}; "
            f"tool CPython {sys.version.split()[0]}; digest {digest}; path {shown}; run {run_id}"
        )
        sys.exit(0 if verdict.startswith("PASS") else 1)
    checkers = {"check-panel": check_panel_output, "check-plan": check_plan_output}
    if len(sys.argv) != 2 or sys.argv[1] not in checkers:
        print(
            f"usage: {sys.argv[0]} tag <prefix> | fence <prefix> <title=path>... | run-id <todo-path> <section> <family> <YYYYMMDD> <scan-file>... | run <panel|plan> <prompt-file> <todo-path> <section> <family> <YYYYMMDD> [--timeout S] [--store DIR] [--candidate SHA] <scan-file>... -- <producer> [args...] | check-panel|check-plan < output.txt",
            file=sys.stderr,
        )
        sys.exit(2)
    # Bounded at the read (D00 T01 §23 review R1): slurping stdin
    # unbounded would let hostile output exhaust memory before the
    # size gate runs. One byte past the cap proves the excess without
    # decoding it. Decoding is strict (D00 T01 §34 item 4): malformed
    # bytes and NULs fail with naming diagnostics instead of decoding
    # lossily, and the checker re-measures the text.
    raw = sys.stdin.buffer.read(OUTPUT_MAX_BYTES + 1)
    if len(raw) > OUTPUT_MAX_BYTES:
        print(f"FAIL output exceeds {OUTPUT_MAX_BYTES} bytes")
        sys.exit(1)
    nul_at = raw.find(b"\x00")
    if nul_at != -1:
        print(f"FAIL NUL byte at byte offset {nul_at}")
        sys.exit(1)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        print(f"FAIL malformed UTF-8 at byte offset {exc.start}")
        sys.exit(1)
    ok, reason = checkers[sys.argv[1]](text)
    print(("PASS " if ok else "FAIL ") + reason)
    sys.exit(0 if ok else 1)
