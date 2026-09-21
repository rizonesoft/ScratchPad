#!/usr/bin/env python3
"""Fail when the scheduled plan-gates job has no recent success.

D00 T01 §53 item 7 owns this file: last-success monitoring plus a
stale-run detector on the cron, so delayed or repeatedly failing
schedules surface instead of letting dates expire silently against
the section claim.

The detector reads GitHub workflow history at job time (`gh run list`
over completed schedule events) and fails when the newest success is
older than --max-age-hours (default 26: the daily cron plus slack for
runner delay). Completed runs with zero success fail too: that is the
repeatedly-failing schedule. No completed runs at all passes: a
workflow that never ran is bootstrapping, not stale, and failing
would wedge the first green permanently.

Residual, recorded: a deliberately disabled schedule never runs this
step, so no in-repo detector can catch it; disable stays
operator-visible on the workflow page (a conscious act, not silent
drift). gh outages fail this step closed: loud beats silent, and the
poster below would fail on the same outage.

Contract: exit 0 fresh success (or bootstrap); exit 1 stale, no
success among completed runs, gh failure, or unparseable history,
with the reason on stderr. --now freezes the clock for fixtures.
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone


def fail(msg: str) -> int:
    print(f"check_heartbeat: {msg}", file=sys.stderr)
    return 1


def parse_now(text: str) -> datetime:
    dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    # Naive --now reads UTC (the job clock): arithmetic against
    # offset-aware run stamps must never meet a naive datetime.
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(description="fail when the scheduled job has no recent success")
    ap.add_argument("--workflow", default="plan.yml", help="workflow file to inspect")
    ap.add_argument("--max-age-hours", default="26", help="oldest acceptable success age in hours")
    ap.add_argument("--now", default=None, help="freeze now as ISO-8601 (fixtures)")
    ap.add_argument("--gh", default="gh", help="gh binary (tests point at a fake)")
    ns = ap.parse_args(argv)
    try:
        max_age = float(ns.max_age_hours)
        if max_age < 0:
            raise ValueError
    except ValueError:
        return fail(f"bad --max-age-hours (want a number >= 0): {ns.max_age_hours!r}")
    try:
        now = parse_now(ns.now) if ns.now is not None else datetime.now(timezone.utc)
    except ValueError:
        return fail(f"bad --now (want ISO-8601): {ns.now!r}")
    try:
        p = subprocess.run(
            [ns.gh, "run", "list", "--workflow", ns.workflow, "--event", "schedule",
             "--status", "completed", "--limit", "20",
             "--json", "databaseId,conclusion,createdAt"],
            capture_output=True, text=True, encoding="utf-8",
        )
    except OSError as e:
        return fail(f"cannot run gh: {e}")
    if p.returncode != 0:
        return fail(f"gh run list failed (exit {p.returncode}): {p.stderr.strip()[-300:]}")
    try:
        runs = json.loads(p.stdout.strip() or "[]")
        if not isinstance(runs, list):
            raise ValueError
    except ValueError:
        return fail(f"gh run list returned non-JSON: {p.stdout.strip()[:200]!r}")
    if not runs:
        print(f"check_heartbeat: no completed schedule runs of {ns.workflow} yet (bootstrap)")
        return 0
    newest: datetime | None = None
    for row in runs:
        if not isinstance(row, dict) or row.get("conclusion") != "success":
            continue
        try:
            ts = parse_now(str(row.get("createdAt", "")))
        except ValueError:
            return fail(f"gh run list returned a bad timestamp: {row.get('createdAt')!r}")
        if newest is None or ts > newest:
            newest = ts
    if newest is None:
        latest = max(str(r.get("createdAt", "?")) for r in runs if isinstance(r, dict))
        return fail(
            f"no successful schedule run of {ns.workflow} in the last {len(runs)} "
            f"completed runs (newest completed {latest})"
        )
    age_hours = (now - newest).total_seconds() / 3600
    if age_hours > max_age:
        return fail(
            f"last successful schedule run of {ns.workflow} was "
            f"{newest.isoformat()} ({age_hours:.1f}h ago), older than {max_age:g}h"
        )
    print(
        f"check_heartbeat: last successful schedule run of {ns.workflow} was "
        f"{newest.isoformat()} ({age_hours:.1f}h ago)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
