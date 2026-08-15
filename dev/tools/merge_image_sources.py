#!/usr/bin/env python3
"""Merges externally-sourced current-plate images into the scraped history.

    python3 merge_image_sources.py ../research/plate-history.csv \\
                                   ../research/current-plate-sources.csv \\
        > merged.csv

Wikipedia has no photograph of the present-day plate for a dozen jurisdictions. Where
one was found elsewhere — a state agency, Keegan's catalogue, a Commons file the article
never linked, one government PDF — it is recorded in `current-plate-sources.csv` and
merged here, because the browser only ever reads the history file.

EVERY SOURCE NAMES THE ROW IT DEPICTS, and a source that names no row is not merged.
That column exists because the first version of this script did not have it, and the
damage was not subtle: it filled *any* current row that lacked a picture with *the*
image for that jurisdiction, on nothing but an HTTP 200. So California's 2026 row got a
DMV sample of the 1982 sunset plate; Wyoming's June 2024 row got WYDOT's `2017
SAMPLE.jpg`, which is the design it replaced; South Carolina's January 2026 row got the
"In God We Trust" base it replaced; Kansas's got the base before its own. And where a
jurisdiction has several concurrent designs — North Carolina three, Kentucky two,
Alaska three — one image was pasted across all of them.

A URL returning 200 says nothing about what is in the picture. `depicts_dates` has to
match the row's `dates_issued` exactly, so a mismatch is a loud failure rather than a
wrong plate on a card.

Adds `image_origin` so provenance survives the merge, and carries through `image_note`,
which is the scraper's record of a picture borrowed from a neighbouring row on
Wikipedia's own say-so.
"""

import csv
import re
import sys
import urllib.parse

PLACEHOLDER = "blank license plate shape"

# Commons file pages resolve to a page, not an image. Turn them into something the
# browser can actually draw via Special:FilePath, which redirects to the file itself.
COMMONS_PREFIX = "https://commons.wikimedia.org/wiki/File:"
FILEPATH = "https://commons.wikimedia.org/wiki/Special:FilePath/"

# Pictures held in the repo rather than fetched, because the source URL is a PDF to
# extract the plate from, or a CMS document id that is not a stable address for
# something the app has to keep finding. Relative paths: the browser is opened from
# disk, sitting beside this directory.
#
# Keyed by the row, not by the jurisdiction. Keying it by code was fine while every
# entry was a jurisdiction's only one, and became a live version of this file's whole
# failure mode the moment Wyoming had two: the 1988 Centennial row would have been
# handed the 2025 state-flag plate on nothing but a shared "WY".
LOCAL = {
    ("NE", "January 2023 - present"): "images/NE-2023-standard.png",
    ("WY", "June 2024 – present"): "images/WY-2025-standard.png",
    ("KS", "August 19, 2024 - Present"): "images/KS-2024-standard.png",
    # Cropped to the plate edge: the original is a print proof with a barcode and
    # cut marks around it.
    ("SC", "January 2026 – present"): "images/SC-2026-standard.png",
}


def usable(row):
    return bool(row["image_url"]) and PLACEHOLDER not in row["image_file"].lower()


def key(dates):
    """Loose enough to survive en dashes and stray spaces, strict enough to identify a
    row: "June 2024 – present" and "June 2024 - Present" are the same row."""
    return re.sub(r"[^a-z0-9]", "", (dates or "").lower())


def main(history_path, sources_path):
    sources, preceding = {}, {}
    for r in csv.DictReader(open(sources_path)):
        if r["status"] == "resolved" and r.get("depicts_dates"):
            sources[(r["code"], key(r["depicts_dates"]))] = r
        elif r["status"] == "preceding":
            preceding[r["code"]] = r

    rows = list(csv.DictReader(open(history_path)))
    fields = list(rows[0].keys()) + ["image_origin"]
    out = csv.DictWriter(sys.stdout, fieldnames=fields)
    out.writeheader()

    filled, matched = [], set()
    for r in rows:
        r["image_origin"] = ""
        if usable(r):
            r["image_origin"] = "same design, per Wikipedia" if r.get("image_note") \
                else "wikimedia"

        src = sources.get((r["code"], key(r["dates_issued"])))
        if not src:
            continue
        matched.add((r["code"], key(r["dates_issued"])))
        if usable(r):
            continue                    # Wikipedia has caught up; leave it alone

        url = src["url"]
        local = LOCAL.get((r["code"], src["depicts_dates"]))
        if local:
            url = local
        elif url.startswith(COMMONS_PREFIX):
            # Percent-encoded, because these filenames carry spaces and commas and
            # Swift's URL(string:) returns nil on both — the picture would simply not
            # appear, with nothing to say why.
            url = FILEPATH + urllib.parse.quote(url[len(COMMONS_PREFIX):])

        r["image_url"] = url
        r["image_file"] = src["design"] or r["image_file"]
        r["licence"] = src["licence"]
        r["credit"] = src["note"]
        r["image_origin"] = src["source_type"]
        filled.append(r["code"])

    # A design nobody has photographed yet, where the jurisdiction is named in the
    # sources file as one whose *previous* plate is what is actually on the road. Not a
    # fudge, but not automatic either: it is a per-jurisdiction judgement that a rollout
    # is still in progress, so it is written down there rather than inferred here.
    by_code = {}
    for r in rows:
        by_code.setdefault(r["code"], []).append(r)

    fellback = []
    for code, src in preceding.items():
        group = by_code.get(code, [])
        current = [r for r in group if r["is_current"] == "1"]
        if not current or any(usable(r) for r in current):
            continue
        dated = [r for r in group if usable(r) and r["first_issued"]]
        if not dated:
            continue
        newest = max(dated, key=lambda r: r["first_issued"])
        for r in current:
            r["image_url"] = newest["image_url"]
            r["image_file"] = newest["image_file"]
            r["licence"] = newest["licence"]
            r["credit"] = f"shows the {newest['dates_issued'] or newest['first_issued']}" \
                          f" design — {src['note']}"
            r["image_origin"] = "preceding design"
        fellback.append(f"{code}({newest['first_issued']})")

    for r in rows:
        out.writerow(r)

    print(f"filled {len(filled)} current-plate images: {' '.join(sorted(set(filled)))}",
          file=sys.stderr)
    if fellback:
        print(f"fell back to the preceding design for: {' '.join(sorted(fellback))}",
              file=sys.stderr)
    # A source whose `depicts_dates` matches nothing is the failure this script exists to
    # make loud: either the article was reworded or the source was never checked against
    # it. Silence here would put the wrong plate on a card.
    for (code, k), src in sources.items():
        if (code, k) not in matched:
            print(f"UNMATCHED SOURCE {code}: no row dated {src['depicts_dates']!r}",
                  file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
