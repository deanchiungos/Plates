#!/usr/bin/env python3
"""Indexes every user-facing string in the app and says whether Xcode can edit it.

    python3 copy_audit.py

Writes `research/copy-audit.md` and `research/copy-audit.json`.

WHAT CHANGED, AND WHY THIS SCRIPT EXISTS AT ALL. The first version of this audit was
the only index of the app's copy, because most of it was invisible to the String
Catalog: the compiler harvests `LocalizedStringKey` and `LocalizedStringResource`
literals and nothing else, and the popup components declared their titles as plain
`String`. Ninety-odd sentences — every confirmation in the app — could only be
reworded by editing Swift.

They are keys now, so `Plates/Localizable.xcstrings` is the place to edit copy and
this file is the cross-check: it lists what is on screen, and flags anything the
catalog does not carry. A row marked ✗ is a string that can still only be changed in
the source, and each one should have a reason.

The scan is deliberately syntactic — it reads the text, it does not compile it — so
treat a surprising ✗ as a question rather than a verdict.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "ios/Plates"
CATALOG = APP / "Localizable.xcstrings"
OUT_MD = ROOT / "research/copy-audit.md"
OUT_JSON = ROOT / "research/copy-audit.json"

# Where a string literal is user-facing. The key is what to call it in the report.
CONTEXTS = [
    ("Text",           re.compile(r'\bText\(\s*(?:verbatim:\s*)?"')),
    ("popup title",    re.compile(r'\.present\(\s*(?:verbatim:\s*)?"')),
    ("popup message",  re.compile(r'\bmessage:\s*"')),
    ("popup button",   re.compile(r'\bPopupButton\(\s*title:\s*"')),
    ("popup choice",   re.compile(r'\b(?:verbatimT|t)itle:\s*"')),
    ("subtitle",       re.compile(r'\b(?:verbatimS|s)ubtitle:\s*"')),
    ("detail",         re.compile(r'\bdetail:\s*"')),
    ("button",         re.compile(r'\bButton\(\s*"')),
    ("label",          re.compile(r'\bLabel\(\s*"')),
    ("nav title",      re.compile(r'\.navigationTitle\(\s*"')),
    ("accessibility",  re.compile(r'\.accessibility(?:Label|Hint|Value)\(\s*"')),
    ("placeholder",    re.compile(r'\bTextField\(\s*"')),
    ("localized",      re.compile(r'\bString\(localized:\s*"|\.inflected\(\s*"')),
    ("alert",          re.compile(r'\.alert\(\s*"')),
    ("toggle",         re.compile(r'\bToggle\(\s*"')),
    ("section",        re.compile(r'\bSection\(\s*"|\bSettingsGroup\(\s*"|\bMoreSection\(\s*"')),
]

# A literal, allowing \" and interpolation. Non-greedy up to an unescaped quote.
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

# Strings that are never shown to anybody: SF Symbol names, asset names, keys.
NOISE_CALLS = re.compile(
    r'systemName:|systemImage:|forResource:|withExtension:|Image\(|'
    r'UserDefaults|AppStorage|uuidString:|forKey:|identifier:|withIdentifier:|'
    r'\.font\(|Font\(|subdirectory:|scheme:|host:|path:|URL\(string:'
)


def catalog_keys():
    if not CATALOG.exists():
        sys.exit(f"no catalog at {CATALOG}")
    return set(json.load(CATALOG.open())["strings"])


def to_key(literal: str) -> str:
    """Turn source text into the key the compiler would have produced.

    Interpolations become printf specifiers. `\\(x.count)` and anything the source
    calls a count or a number is an integer; everything else is treated as a string.
    This is a guess, and it is the one place the audit can disagree with the catalog
    for an uninteresting reason — a `%@` that should have been `%lld`.
    """
    out, i, n = [], 0, len(literal)
    while i < n:
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if literal[j] == "(":
                    depth += 1
                elif literal[j] == ")":
                    depth -= 1
                j += 1
            expr = literal[i + 2:j - 1]
            numeric = re.search(r'count|total|found|number|rarity|score|\bn\b|Count\b',
                                expr, re.IGNORECASE)
            out.append("%lld" if numeric else "%@")
            i = j
        else:
            out.append(literal[i])
            i += 1
    text = "".join(out)
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\u{2026}", "…") \
               .replace("\\u{201C}", "“").replace("\\u{201D}", "”") \
               .replace("\\u{00B7}", "·")


def scan():
    keys = catalog_keys()
    rows = []
    for path in sorted(APP.rglob("*.swift")):
        rel = path.relative_to(ROOT)
        for lineno, line in enumerate(path.read_text().split("\n"), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            context = next((name for name, rx in CONTEXTS if rx.search(line)), None)
            if not context or NOISE_CALLS.search(line):
                continue
            for m in LITERAL.finditer(line):
                raw = m.group(1)
                if not raw or not re.search(r'[A-Za-z]{2}', raw):
                    continue
                key = to_key(raw)
                rows.append({
                    "file": str(rel), "line": lineno, "context": context,
                    "text": raw, "key": key, "inCatalog": key in keys,
                })
    return rows, keys


def main():
    rows, keys = scan()
    missing = [r for r in rows if not r["inCatalog"]]
    by_file = {}
    for r in rows:
        by_file.setdefault(r["file"], []).append(r)

    counts = {}
    for r in rows:
        counts[r["context"]] = counts.get(r["context"], 0) + 1

    L = []
    L.append("# Copy audit\n")
    L.append(f"Every user-facing string in the app: **{len(rows)}** of them across "
             f"**{len(by_file)}** files.\n")
    L.append(f"**Edit copy in Xcode**, in `Plates/Localizable.xcstrings` — "
             f"**{len(keys)}** entries. This file is the cross-check, not the source.\n")
    L.append(f"✓ in the String Catalog · ✗ source-only (**{len(missing)}**)\n")
    if missing:
        L.append("The ✗ rows are expected to be a short list with reasons — search "
                 "photographs, plate names, and CloudKit's own error text. A ✗ on an "
                 "ordinary sentence is a bug in the source, not in this report.\n")
    L.append("| context | count |")
    L.append("| --- | --- |")
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        L.append(f"| {k} | {v} |")
    L.append("")

    for f in sorted(by_file):
        L.append(f"\n## {f}\n")
        L.append("| line | ✓ | context | string |")
        L.append("| --- | --- | --- | --- |")
        for r in by_file[f]:
            text = r["text"].replace("|", "\\|").replace("\\n", " ⏎ ")
            L.append(f"| {r['line']} | {'✓' if r['inCatalog'] else '✗'} "
                     f"| {r['context']} | {text} |")

    OUT_MD.write_text("\n".join(L) + "\n")
    OUT_JSON.write_text(json.dumps(
        {"strings": rows, "catalogEntries": len(keys), "sourceOnly": len(missing)},
        indent=2) + "\n")
    print(f"{len(rows)} strings, {len(by_file)} files, {len(keys)} catalog entries, "
          f"{len(missing)} source-only")
    print(f"wrote {OUT_MD.relative_to(ROOT)} and {OUT_JSON.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
