#!/usr/bin/env python3
"""The one-design-per-jurisdiction set the app actually ships.

`plate_vision.py` describes every street-legal image — 268 of them, several per
jurisdiction where a state has multiple still-valid designs or the same design was
photographed more than once. The app wants exactly one, matching `Plate.all` in
Plate.swift one-for-one: 65 jurisdictions, 65 tiles.

PICKS below is the manual curation. Each entry names the winning image key and, where
the obvious choice — "whichever touches a `present` row" — was wrong, why:

  - specialty       the current-tagged row is a commemorative/vehicle-class variant
                     (Veteran, bicentennial, school bus...); the general passenger
                     design is not what's tagged current in the source data, so this
                     falls back to the newest clean photo of the actual issued plate.
  - obscured        the true current design's only clean-ish photo is blocked by a
                     dealer frame or similar; using an older still-street-legal design
                     instead because a blocked legend fails "clean good image".
There is no `scrape-bug` category any more. There was one, for Ontario, and it was
wrong: it read "1997-2020; 2020-present" as a table-parsing artifact that had merged
"present" onto the wrong row, when the source was simply recording a design that
stopped and then resumed. Audited afterwards across all 65 jurisdictions and the
signature it claimed — a `...-present` row that is not flagged current while some
other row is — occurs exactly nowhere. `is_current` sits on a `present` row every
single time. If a pick ever seems to disagree with the flag again, the flag is
probably right.
  - no-current-photo  the jurisdiction's actual current design has no usable photo
                     anywhere in the dataset (documented in plate-images-plan.md);
                     this is the newest still-street-legal design standing in for it.
  - language         a same-design bilingual pair; kept the English rendering.

Wyoming arrived late. Converse County publishes the state's own sample of the 2024
state-flag design, and once that was merged in and described, WY had exactly one
street-legal image and needed a pick like everywhere else.

No entry for YT, which still has none: its 1990 design is genuinely the one on the
road and no free photograph of it exists anywhere — checked against the article, a
Yukon News history piece and bcpl8s.ca. See current-plate-sources.csv.
"""

import csv
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESEARCH = os.path.join(ROOT, "dev", "research")
DESCRIPTIONS = os.path.join(RESEARCH, "plate-descriptions.csv")
CACHE = os.path.join(RESEARCH, "images", "cache")
PRIMARY_DIR = os.path.join(RESEARCH, "images", "primary")
OUT = os.path.join(RESEARCH, "plate-primary.csv")

PICKS = {
    "AL": ("27bf8f9548a2", ""),
    "AK": ("35df0d601fed", ""),
    "AZ": ("92a34279d920", "Wikipedia spans one Design cell across January 2008, April 2020 and February 2021, so all three are one design differing only in serial format; this photo's serial sits inside the 2008 row's own stated range. Was the 1996 embossed plate, which the scraper had borrowed for this design under the 'as above, but...' rule and which is visibly a different plate"),
    "AR": ("3597f77f448c", ""),
    "CA": ("b4cfc33079fc", ""),
    "CO": ("cf72f5c92701", ""),
    "CT": ("e1a3df2e53a0", ""),
    "DE": ("1f4436b23318", ""),
    "FL": ("312351db9de0", ""),
    "GA": ("e3882e079174", ""),
    "HI": ("563eeedcb58f", ""),
    "ID": ("c863675dca44", ""),
    "IL": ("12a764c85e6f", ""),
    "IN": ("b3c603adb2f2", ""),
    "IA": ("4c84de7eb5d1", ""),
    "KS": ("c855f04273da", "the 'To the Stars' design issued from August 2024; the agency serves it as a flat PNG from a bare img/ path, which the earlier JS-rendered page did not expose"),
    "KY": ("d5bb6a64c2cd", ""),
    "LA": ("43f4e890e462", "specialty: the current-tagged row is a semiquincentennial commemorative (shield badge, not the pelican); this is the newest photo of the standard design"),
    "ME": ("90f5792d92cb", ""),
    "MD": ("71ff9729d86d", ""),
    "MA": ("4d2e32d7cfbd", ""),
    "MI": ("051c9a891427", ""),
    "MN": ("e0665da4a77b", ""),
    "MS": ("b9a825d8677f", ""),
    "MO": ("16840b69ef65", "specialty: the current-tagged row is a statehood-bicentennial commemorative (wave rules, no bluebird); this is the newest photo of the standard design"),
    "MT": ("0116da0a6130", ""),
    "NE": ("f67ce1a8456c", ""),
    "NV": ("12435930ee06", ""),
    "NH": ("945f8a19005f", ""),
    "NJ": ("4c37e97be1e2", ""),
    "NM": ("41eb7ccebc9f", ""),
    "NY": ("5fc0b85390e4", ""),
    "NC": ("1eeaa1b18c2b", "obscured: the current 'First in Freedom' design's only photo has an aftermarket backup-camera bracket across the top legend; this is the previous still-street-legal 'First in Flight' design instead"),
    "ND": ("8ee242aa05c6", ""),
    "OH": ("8f8190344ff8", ""),
    "OK": ("0c6b68ae7c23", ""),
    "OR": ("3f26796c7d5a", ""),
    "PA": ("0215376e674d", ""),
    "RI": ("ab165863cd2d", ""),
    "SC": ("6b24d8076eae", "the January 2026 Revolutionary War design, from SCDMV's own artwork; the article gives that row no design description, so this is checked against the SC250 Commission's published design rather than the row's words"),
    "SD": ("4c332dc8bed6", ""),
    "TN": ("aa7c9beb08e8", ""),
    "TX": ("0962884afa99", ""),
    "UT": ("b37838dfda2d", ""),
    "VT": ("b762d8762f80", ""),
    "VA": ("0770392654b9", ""),
    "WA": ("4e4aa1e90ab4", ""),
    "WV": ("a2b855d8ea2f", ""),
    "WI": ("536f9e074d94", ""),
    "WY": ("91875c6070bd", ""),
    # federal / territory
    "DC": ("007771e083f1", ""),
    "PR": ("414748104b35", ""),
    # provinces
    "ON": ("d252f912e202", "reverted pick: this was 960c92a2c948, the blue 2020 'A Place to Grow' plate, on the theory that the source's is_current flag had been merged onto the wrong row. It had not. Ontario pulled the blue plate before general issue over night-visibility failures and went back to the white one, which is why the source reads '1997-2020; 2020-present' — a design that stopped and resumed, recorded correctly. The white plate with the crown is what is actually on the road"),
    "QC": ("6f9aaae6b124", ""),
    "BC": ("6afd136a34c3", ""),
    "AB": ("4e55ab81e5e0", ""),
    "MB": ("ffa8485d6307", ""),
    "SK": ("8eac211a55b4", ""),
    "NS": ("875236c63443", ""),
    "NB": ("08af175372a4", ""),
    "NL": ("8f432cc67308", "obscured: the current (Nov 2025-present) design's only photo is small and blurred; this is the design it replaced, still street-legal and cleanly photographed"),
    "PE": ("08e4d27077ee", "language: 7a84d5eeea26 is the identical design in French; kept the English rendering"),
    "NT": ("5eebab811335", ""),
    "NU": ("47a5694250d4", ""),
    # no entry: WY, YT — zero street-legal images in the dataset for either
}

ALL_CODES = """AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT
NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY
DC PR
ON QC BC AB MB SK NS NB NL PE NT YT NU""".split()

FIELDS = ["code", "key", "note", "codes", "rows", "caption", "base", "serial_color",
          "finish", "typeface", "top_legend", "bottom_legend", "graphics", "separator",
          "border", "confidence", "caveat", "image_path"]


def main():
    by_key = {r["key"]: r for r in csv.DictReader(open(DESCRIPTIONS))}

    missing_keys = [c for c, (k, _) in PICKS.items() if k not in by_key]
    if missing_keys:
        sys.exit(f"keys not found in {DESCRIPTIONS}: {missing_keys}")

    zero = [c for c in ALL_CODES if c not in PICKS]

    os.makedirs(PRIMARY_DIR, exist_ok=True)
    rows = []
    for code, (key, note) in PICKS.items():
        d = by_key[key]
        src = os.path.join(CACHE, f"{key}.jpg")
        dest = os.path.join(PRIMARY_DIR, f"{code}.jpg")
        shutil.copyfile(src, dest)
        rows.append({
            "code": code, "key": key, "note": note,
            "image_path": os.path.relpath(dest, ROOT),
            **{f: d[f] for f in ("codes", "rows", "caption", "base", "serial_color",
                                  "finish", "typeface", "top_legend", "bottom_legend",
                                  "graphics", "separator", "border", "confidence",
                                  "caveat")},
        })
    rows.sort(key=lambda r: r["code"])

    with open(OUT, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)

    print(f"{len(rows)} jurisdictions -> {OUT}")
    print(f"images copied to {PRIMARY_DIR}/<code>.jpg")
    overridden = [c for c, (_, n) in PICKS.items() if n]
    print(f"{len(overridden)} picks overrode the naive 'current' flag: {sorted(overridden)}")
    print(f"zero entries: {zero}")


if __name__ == "__main__":
    main()
