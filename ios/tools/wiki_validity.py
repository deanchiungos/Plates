#!/usr/bin/env python3
"""Scrapes which retired plate designs are still road-legal.

    python3 wiki_validity.py > ../../research/plate-validity.csv

For a spotting game this is the question that matters more than "when was it issued".
A 1911 Alabama plate is a museum piece; a 1980 California plate is still bolted to cars
on the freeway, and both look identical in a table sorted by year.

Source is the "Plate types no longer issued but still valid" table on
`United States license plate designs and serial formats`, which is per-jurisdiction and
carries a Status column in its own words — "Valid.", "Being replaced upon expiration",
and so on. Reproduced verbatim rather than reduced to a boolean: "valid only on the
vehicle it was originally issued to, continuously registered" is a real answer and is
not a yes or a no.

The table leans on rowspan for both Jurisdiction and Status, so those are carried down
rather than read per row.
"""

import csv
import json
import re
import sys
import urllib.parse
import urllib.request

UA = "plates-app-research/1.0 (eggeppel34@gmail.com)"
ARTICLE = "United States license plate designs and serial formats"
SECTION = "Plate types no longer issued but still valid"

# Article title -> the code used everywhere else in this project.
CODES = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
    "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE",
    "the District of Columbia": "DC", "District of Columbia": "DC", "Florida": "FL",
    "Georgia": "GA", "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL",
    "Indiana": "IN", "Iowa": "IA", "Kansas": "KS", "Kentucky": "KY",
    "Louisiana": "LA", "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA",
    "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO",
    "Montana": "MT", "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH",
    "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
    "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK",
    "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI",
    "South Carolina": "SC", "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX",
    "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
    "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
    "Puerto Rico": "PR",
    # Title variants used by this table's links, plus one territory outside the app's set.
    "Georgia (U.S. state)": "GA", "Washington, D.C.": "DC", "Guam": "GU",
}

JURIS = re.compile(r"\[\[Vehicle registration plates of ([^|\]]+)(?:\|[^\]]*)?\]\]")
ROWSPAN = re.compile(r'rowspan\s*=\s*"?(\d+)"?\s*\|', re.I)


def api(**kw):
    kw.setdefault("format", "json")
    kw.setdefault("formatversion", "2")
    req = urllib.request.Request(
        "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(kw),
        headers={"User-Agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=60))


def clean(text):
    text = re.sub(r"<ref[^>]*>.*?</ref>|<ref[^>]*/>", "", text, flags=re.S)
    text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"\[\[[^|\]]*\|([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[\[([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"</?[^>]+>", " ", text)
    text = text.replace("&nbsp;", " ").replace("'''", "").replace("''", "")
    text = ROWSPAN.sub("", text)
    text = re.sub(r'^\s*(?:colspan|style|class)\s*=\s*"?[^|]*"?\s*\|', "", text)
    return " ".join(text.split()).strip(" |")


def classify(status):
    """The Status column in its own words, bucketed for filtering."""
    s = status.lower()
    if not s or s in ("none",):
        return "unknown"
    if "no longer valid" in s or "invalid" in s or "recalled" in s:
        return "expired"
    if "replace" in s or "phased" in s or "must be" in s or "until" in s:
        return "expiring"
    if "valid" in s:
        return "valid"
    return "unknown"


def main():
    sections = api(action="parse", page=ARTICLE, prop="sections")["parse"]["sections"]
    index = next(s["index"] for s in sections if s["line"] == SECTION)
    wt = api(action="parse", page=ARTICLE, prop="wikitext",
             section=index)["parse"]["wikitext"]

    table = re.search(r"\{\|.*?\n\|\}", wt, flags=re.S).group(0)

    out = csv.writer(sys.stdout)
    out.writerow(["code", "jurisdiction", "dates_issued", "type", "plate_style",
                  "serial_format", "status", "status_class", "image_file"])

    code = name = status = ""
    juris_left = status_left = 0
    total = 0

    for block in table.split("|-")[1:]:
        if block.lstrip().startswith("!"):
            continue
        cells = [c for c in re.split(r"\n\s*\|", block) if c.strip()]
        if not cells:
            continue

        # Jurisdiction: present only on the first row of its rowspan group.
        m = JURIS.search(cells[0])
        if m:
            name = m.group(1)
            code = CODES.get(name, "")
            span = ROWSPAN.search(cells[0])
            juris_left = int(span.group(1)) - 1 if span else 0
            cells = cells[1:]
        elif juris_left > 0:
            juris_left -= 1
        if not cells:
            continue
        if re.search(r"colspan", cells[0], re.I) and "none" in cells[0].lower():
            continue                       # "American Samoa | none"

        # Status is the last column, and also rowspans.
        if len(cells) >= 6:
            span = ROWSPAN.search(cells[-1])
            status = clean(cells[-1])
            status_left = int(span.group(1)) - 1 if span else 0
        elif status_left > 0:
            status_left -= 1

        img = re.search(r"\[\[\s*File\s*:\s*([^|\]]+?)\s*[|\]]", cells[0], re.I)
        image = img.group(1).replace("_", " ") if img else ""
        rest = [clean(c) for c in cells[1:]]
        dates = rest[0] if len(rest) > 0 else ""
        typ = rest[1] if len(rest) > 1 else ""
        style = rest[2] if len(rest) > 2 else ""
        serial = rest[3] if len(rest) > 3 else ""

        if not (dates or typ):
            continue

        out.writerow([code, name, dates, typ, style, serial,
                      status, classify(status), image])
        total += 1

    print(f"{total} still-valid retired designs across "
          f"{len({c for c in [code]})} rows written", file=sys.stderr)


if __name__ == "__main__":
    main()
