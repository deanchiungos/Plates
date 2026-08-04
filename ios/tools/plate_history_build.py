#!/usr/bin/env python3
"""Turns the scraped plate history into the app's Historical plates resource.

    python3 plate_history_build.py ../../research/plate-history.csv \\
        > ../Plates/Resources/PlateHistory.json

Only rows with a picture. A design Wikipedia describes but does not illustrate is
worth keeping in the research CSV — it is how the image gaps stay countable — but on
a screen whose whole purpose is looking at plates, a row with nothing to look at is
just a gap someone has to scroll past.

URLS, NOT FILES, and that is the one real compromise here. The app already bundles
268 street-legal plate photographs for the lookup screen and they come to 6.4 MB; the
3,100 historical ones would be about 75 MB, which is not a reasonable thing to add to
a game that is otherwise a few megabytes. So these are Wikimedia thumbnail URLs, and
this screen is the one part of the app that needs a network. Everything you do while
actually driving still works offline.
"""

import csv
import json
import re
import sys
import urllib.parse

PLACEHOLDER = "blank license plate shape"

# Wikimedia serves fixed thumbnail widths and 330 is the one the API hands back; ask
# for 320 and you get a 400. Originals are frequently 2000px wide and several
# megabytes, which is not what a 150pt row needs.
UPLOAD = re.compile(
    r"(https://upload\.wikimedia\.org/wikipedia/(?:commons|en))/"
    r"(?:thumb/)?([0-9a-f]/[0-9a-f]{2})/([^/]+)$")


def thumbnail(url):
    # Commons' Special:FilePath redirects to the original, which for these is
    # frequently a couple of megabytes. It takes a width, so ask for one rather than
    # shipping a 2000px scan to a 150pt row.
    if "/Special:FilePath/" in url:
        return url + ("&" if "?" in url else "?") + "width=330"

    m = UPLOAD.match(url)
    if not m:
        return url                       # a state agency's own copy; already small
    name = m.group(3)
    # SVGs have no smaller original to serve, so the thumbnailer rasterises them and
    # the result is a .png on the end of the .svg name.
    suffix = ".png" if name.lower().endswith(".svg") else ""
    return f"{m.group(1)}/thumb/{m.group(2)}/{name}/330px-{name}{suffix}"


def main(path):
    by_code = {}
    for r in csv.DictReader(open(path)):
        url = r["image_url"]
        if not url.startswith("http"):
            continue                     # a file committed beside the research, not shipped
        if PLACEHOLDER in r["image_file"].lower():
            continue

        by_code.setdefault(r["code"], []).append({
            "dates": r["dates_issued"] or r["first_issued"],
            "year": int(r["first_issued"]) if r["first_issued"].isdigit() else 0,
            "current": r["is_current"] == "1",
            "note": r["description"][:180],
            "url": thumbnail(url),
            "licence": r["licence"],
            "credit": r["credit"][:60],
            # Set when the picture belongs to a neighbouring row that Wikipedia says
            # is the same design. The card has to say so.
            "shared": bool(r.get("image_note")),
        })

    # Newest first. A plate history read from the top should open on the one you
    # might actually see out of the window.
    #
    # And de-duplicated on (dates, picture). Where a table shares one Design cell
    # across several serial formats, every one of those rows is a separate design in
    # the research data — correctly, because they *are* separate serial series — but
    # on this screen they arrive as the same photograph with the same date range
    # printed two or three times in a row, which reads as a bug.
    for code, rows in by_code.items():
        rows.sort(key=lambda d: (-d["year"], d["dates"]))
        seen, unique = set(), []
        for d in rows:
            key = (d["dates"], d["url"])
            if key in seen:
                continue
            seen.add(key)
            unique.append(d)
        by_code[code] = unique

    json.dump(by_code, sys.stdout, separators=(",", ":"), ensure_ascii=False)
    total = sum(len(v) for v in by_code.values())
    print(f"{total} designs across {len(by_code)} jurisdictions", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
