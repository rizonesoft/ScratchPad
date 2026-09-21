#!/usr/bin/env python3
"""Fail when the scheduled plan-gates job goes silent.

D00 T01 §53 item 7 owns this file: last-completion monitoring plus a
stale-run detector on the cron, so delayed schedules surface instead
of letting dates expire silently against the section claim.

The detector reads GitHub workflow history at job time (`gh run list`
over recent completed runs) and fails when no schedule completion is
newer than --max-age-hours (default 26: the daily cron plus slack
for runner delay). Completion, not success (fix-loop R2):
conclusions are ignored on purpose, because a success-gated
detector latches red permanently (its own failure keeps the next
success off the record, so every later run fails too), while a
completion-gated one heals the moment the schedule produces
anything. Repeatedly failing schedules need no heartbeat failure:
their red jobs plus the always-run notifications already surface.

Empty schedule history splits two ways from the same listing. No
completed runs of any event passes with a bootstrap note (a
workflow that never ran is starting, not stale, and failing would
wedge the first green permanently). Completed runs with zero from
schedule fail: pushes prove CI works while the cron never fired,
which is exactly the silent schedule. A trigger set with no push
escape stays operator-visible on the Actions page (nothing runs,
so nothing can report from inside).

Residual, recorded: a deliberately disabled schedule never runs this
step, so no in-repo detector can catch it; disable stays
operator-visible on the workflow page (a conscious act, not silent
drift). gh outages fail this step closed: loud beats silent, and the
poster below would fail on the same outage.

Contract: exit 0 fresh completion (or bootstrap); exit 1 stale
schedule, schedule-never-ran, gh failure, or unparseable history,
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


def parse_stamp(value: object) -> datetime:
    return parse_now(str(value))


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(description="fail when the scheduled job goes silent")
    ap.add_argument("--workflow", default="plan.yml", help="workflow file to inspect")
    ap.add_argument("--max-age-hours", default="26", help="oldest acceptable completion age in hours")
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
            [ns.gh, "run", "list", "--workflow", ns.workflow,
             "--status", "completed", "--limit", "20",
             "--json", "databaseId,event,createdAt"],
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
    sched: list[datetime] = []
    other: list[datetime] = []
    for row in runs:
        if not isinstance(row, dict):
            return fail(f"gh run list returned a non-object row: {row!r}"[:200])
        try:
            ts = parse_stamp(row.get("createdAt", ""))
        except ValueError:
            return fail(f"gh run list returned a bad timestamp: {row.get('createdAt')!r}")
        (sched if row.get("event") == "schedule" else other).append(ts)
    if not sched and not other:
        print(f"check_heartbeat: no completed runs of {ns.workflow} yet (bootstrap)")
        return 0
    if not sched:
        newest_other = max(other)
        return fail(
            f"schedule never produced a completed run of {ns.workflow} "
            f"({len(other)} other-event completions, newest {newest_other.isoformat()})"
        )
    newest = max(sched)
    age_hours = (now - newest).total_seconds() / 3600
    if age_hours > max_age:
        return fail(
            f"no schedule completion of {ns.workflow} in {max_age:g}h "
            f"(newest {newest.isoformat()}, {age_hours:.1f}h ago)"
        )
    print(
        f"check_heartbeat: last schedule completion of {ns.workflow} was "
        f"{newest.isoformat()} ({age_hours:.1f}h ago)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
