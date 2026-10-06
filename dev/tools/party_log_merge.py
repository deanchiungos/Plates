#!/usr/bin/env python3
"""Merge party logs exported from several phones into one timeline.

TEMPORARY, like the recorder that writes them (`PartyDiagnostics.swift`).

Each phone's "Share party log" produces a JSON-lines file: a meta line saying
whose phone it is, the app's own party events, and MultipeerConnectivity's
internal log for the current launch. This lays every phone's lines out on one
clock, one column of names on the left.

    dev/tools/party_log_merge.py party-log-Anna-*.jsonl party-log-Dean-*.jsonl
    dev/tools/party_log_merge.py --app-only *.jsonl          # skip framework lines
    dev/tools/party_log_merge.py --since 14:02 --until 14:10 *.jsonl
    dev/tools/party_log_merge.py --grep 'invite|connect' *.jsonl

Phone clocks are NTP-synced and usually agree to well under a second, but not
always. The skew report compares when each phone says a link came up — both ends
see `connected` within a few hundred milliseconds of each other — and suggests a
per-phone offset; pass it back with --offset Dean=-0.8 if the order looks wrong.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone

SKIP = {"t", "src", "ev", "launch", "seq", "up", "role", "me", "gen", "wifi"}


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def load(path):
    who, rows = None, []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                print(f"{path}:{n}: unreadable line skipped", file=sys.stderr)
                continue
            if row.get("src") == "meta" and "who" in row and who is None:
                who = row["who"]
                print(f"# {who}: {row.get('model')} iOS {row.get('os')} app {row.get('app')} "
                      f"exported {row.get('exportedAt')}", file=sys.stderr)
            if "t" in row:
                rows.append(row)
    return who or path, rows


def describe(row):
    if row.get("src") == "os":
        return f"[{row.get('cat', '')}] {row.get('msg', '')}"
    extras = " ".join(f"{k}={v}" for k, v in sorted(row.items()) if k not in SKIP and v not in ("", "-"))
    head = row.get("ev", "?")
    if "me" in row:
        head = f"{head} ({row.get('role', '')} {row['me']} g{row.get('gen', '0')} wifi={row.get('wifi')})"
    return f"{head}  {extras}".rstrip()


def skew(phones):
    """Median gap between the two ends of each link coming up, per phone vs the first."""
    names = list(phones)
    if len(names) < 2:
        return {}
    base = names[0]
    def ups(rows):
        out = {}
        for r in rows:
            if r.get("ev") == "connected" and r.get("src") == "app":
                out.setdefault(r.get("peer", "").split("#")[0], []).append(parse_time(r["t"]))
        return out
    base_ups = ups(phones[base])
    report = {}
    for name in names[1:]:
        gaps = []
        for peer, times in ups(phones[name]).items():
            # This phone saw `peer` connect; the base phone's matching line is it
            # seeing this phone connect.
            for t in times:
                theirs = [b for bs in base_ups.values() for b in bs]
                if theirs:
                    nearest = min(theirs, key=lambda b: abs((b - t).total_seconds()))
                    gap = (t - nearest).total_seconds()
                    if abs(gap) < 30:
                        gaps.append(gap)
        if gaps:
            gaps.sort()
            report[name] = gaps[len(gaps) // 2]
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--app-only", action="store_true", help="drop MultipeerConnectivity's own lines")
    ap.add_argument("--offset", action="append", default=[], metavar="NAME=SECONDS",
                    help="shift one phone's clock, e.g. Dean=-0.8")
    ap.add_argument("--since", help="HH:MM[:SS] local time, inclusive")
    ap.add_argument("--until", help="HH:MM[:SS] local time, inclusive")
    ap.add_argument("--grep", help="regex on the rendered line")
    ap.add_argument("--utc", action="store_true", help="print UTC instead of local time")
    args = ap.parse_args()

    phones = {}
    for path in args.files:
        who, rows = load(path)
        while who in phones:
            who += "'"
        phones[who] = rows

    offsets = {}
    for item in args.offset:
        name, _, secs = item.partition("=")
        offsets[name] = float(secs)

    for name, gap in skew(phones).items():
        note = "" if abs(gap) < 0.5 else "  <- consider --offset"
        print(f"# skew: {name} reads {gap:+.2f}s vs {list(phones)[0]} at link-up{note}", file=sys.stderr)

    width = max(len(n) for n in phones)
    pattern = re.compile(args.grep, re.I) if args.grep else None
    tz = timezone.utc if args.utc else None
    merged = []
    for name, rows in phones.items():
        shift = timedelta(seconds=offsets.get(name, 0))
        for r in rows:
            if args.app_only and r.get("src") == "os":
                continue
            merged.append((parse_time(r["t"]) + shift, name, r))
    merged.sort(key=lambda x: (x[0], x[1]))

    def clip(text):
        parts = [int(p) for p in text.split(":")]
        return tuple(parts + [0] * (3 - len(parts)))

    for t, name, r in merged:
        local = t.astimezone(tz)
        hms = (local.hour, local.minute, local.second)
        if args.since and hms < clip(args.since):
            continue
        if args.until and hms > clip(args.until):
            continue
        text = describe(r)
        if pattern and not pattern.search(text):
            continue
        mark = ">>" if r.get("ev") == "MARK" else ("  " if r.get("src") == "app" else " .")
        print(f"{local.strftime('%H:%M:%S.%f')[:-3]} {name:<{width}} {mark} {text}")


if __name__ == "__main__":
    main()
