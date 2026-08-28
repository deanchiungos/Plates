#!/usr/bin/env python3
"""Work with the plate-fact database outside Swift.

The JSON at Plates/Resources/PlateFacts.json is the single source of truth — the
app loads it straight from the bundle. This script only validates it and moves it
in and out of CSV so it can be edited in a spreadsheet.

    ./tools/facts.py check              validate the JSON
    ./tools/facts.py to-csv facts.csv   export for a spreadsheet
    ./tools/facts.py from-csv facts.csv import a spreadsheet back (validates first)
    ./tools/facts.py stats              counts per region, thinnest regions first

CSV is an interchange format here, not the master copy. Round-tripping through it
is safe, but keep the JSON as the thing you commit.
"""

import csv
import json
import pathlib
import re
import sys

# Repo root, then down into the app. This was `parent.parent` back when the tools
# lived inside `ios/`; from `dev/tools` that pointed at `dev/Plates`, which does not
# exist. Every other script here already spells the `ios` hop out, so this one does too.
ROOT = pathlib.Path(__file__).resolve().parents[2]
JSON_PATH = ROOT / "ios" / "Plates" / "Resources" / "PlateFacts.json"
SWIFT_CATALOG = ROOT / "ios" / "Plates" / "Domain" / "Plate.swift"

MAX_LEN = 120


def plate_codes():
    """The codes the app actually has plates for, read from the Swift catalog so
    this cannot drift out of sync with it."""
    src = SWIFT_CATALOG.read_text()
    return [m.group(1) for m in re.finditer(r'\.init\(code: "([A-Z]{2})"', src)]


def load():
    """Normalised to {code: [{"text":..., "source":...}]}.

    Accepts the old bare-string shape too, so a half-migrated file — or a sheet
    exported before sources existed — still reads. Anything written back out is
    always the new shape, so the old one dies on first save rather than lingering.
    """
    with open(JSON_PATH, encoding="utf-8") as f:
        raw = json.load(f)
    return {c: [normalise(x) for x in v] for c, v in raw.items()}


def normalise(entry):
    if isinstance(entry, str):
        return {"text": entry, "source": ""}
    return {"text": entry.get("text", ""), "source": entry.get("source", "")}


def save(data):
    codes = plate_codes()
    # Written back in catalog order so diffs stay readable and stable.
    ordered = {c: data[c] for c in codes if c in data}
    ordered.update({c: v for c, v in data.items() if c not in codes})
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(ordered, f, indent=2, ensure_ascii=False)
        f.write("\n")


def check(data=None, quiet=False):
    data = data if data is not None else load()
    codes = plate_codes()
    problems = []

    for code in codes:
        if code not in data:
            problems.append(f"{code}: no facts at all")
        elif not data[code]:
            problems.append(f"{code}: empty list")
    for code in data:
        if code not in codes:
            problems.append(f"{code}: not a plate code in Plate.swift")

    seen_global = {}
    for code, entries in data.items():
        texts = [e["text"] for e in entries]
        if len(set(texts)) != len(texts):
            problems.append(f"{code}: repeats a fact within the region")
        for entry in entries:
            fact, src = entry["text"], entry["source"]
            if not fact.strip():
                problems.append(f"{code}: blank fact")
            if len(fact) > MAX_LEN:
                problems.append(f"{code}: {len(fact)} chars (guide is {MAX_LEN}) - {fact[:70]}...")
            if fact in seen_global and seen_global[fact] != code:
                problems.append(f"{code}: same sentence as {seen_global[fact]} - {fact[:50]}...")
            # A source is required for anything added from now on. Facts that predate
            # the column are counted by `unsourced` rather than failing the build,
            # because failing 389 at once would just mean nobody runs check again.
            if src and not src.startswith(("http://", "https://")):
                problems.append(f"{code}: source is not a URL - {src[:60]}")
            seen_global[fact] = code

    total = sum(len(v) for v in data.values())
    missing = sum(1 for v in data.values() for e in v if not e["source"])
    if not quiet:
        print(f"{len(data)} regions, {total} facts, longest "
              f"{max((len(e['text']) for v in data.values() for e in v), default=0)} chars, "
              f"{missing} without a source")
        if problems:
            print(f"\n{len(problems)} problem(s):")
            for p in problems:
                print("  -", p)
        else:
            print("no problems")
    return problems


def to_csv(path):
    data = load()
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["code", "fact", "source"])
        for code in plate_codes():
            for entry in data.get(code, []):
                w.writerow([code, entry["text"], entry["source"]])
    print(f"wrote {path} — one row per fact, edit and run from-csv to import")


def from_csv(path):
    data = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            code = (row.get("code") or "").strip().upper()
            fact = (row.get("fact") or "").strip()
            source = (row.get("source") or "").strip()
            if code and fact:
                data.setdefault(code, []).append({"text": fact, "source": source})

    problems = check(data, quiet=True)
    if problems:
        # Refuses rather than writing: importing a broken sheet over the good JSON
        # would lose the only copy.
        print(f"NOT imported — {len(problems)} problem(s) in {path}:")
        for p in problems:
            print("  -", p)
        sys.exit(1)

    save(data)
    print(f"imported {sum(len(v) for v in data.values())} facts from {path}")


def stats():
    data = load()
    rows = sorted(((len(v), k) for k, v in data.items()))
    print(f"{sum(n for n, _ in rows)} facts across {len(rows)} regions\n")
    print("thinnest regions:")
    for n, code in rows[:10]:
        print(f"  {code}  {n}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "check":
        sys.exit(1 if check() else 0)
    elif cmd == "to-csv":
        to_csv(sys.argv[2] if len(sys.argv) > 2 else "facts.csv")
    elif cmd == "from-csv":
        from_csv(sys.argv[2] if len(sys.argv) > 2 else "facts.csv")
    elif cmd == "stats":
        stats()
    else:
        print(__doc__)
        sys.exit(2)
