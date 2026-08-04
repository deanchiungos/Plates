#!/usr/bin/env python3
"""Scrapes the passenger baseplate history for every US state and Canadian province
out of Wikipedia, with each image's licence resolved from Commons.

    python3 wiki_plates.py > ../../research/plate-history.csv

WHY THIS AND NOT THE KEEGAN CATALOGUE. Keegan's repo is a snapshot of what you could
*order* in 2023: no history, fourteen states missing their own standard plate, no
Canada, and no licence on anything. Wikipedia's per-jurisdiction articles carry a
"Passenger baseplates" table that is exactly the design history — image, first year
issued, description — going back to the 1900s, and every image has an explicit
licence. Ontario alone has 222 images.

ON LICENSING, because it is the whole reason this source is preferable. Commons hosts
these under two stacked claims: the plate design itself is below the threshold of
originality ({{PD-textlogo}}, {{PD-ineligible}}), and the photograph of it is
separately released by whoever took it ({{Self}} plus CC BY-SA or CC0). That is a
real, checkable grant per image, which the state-agency images never had. It is not
legal advice and the `licence` column is there to be read: CC BY-SA rows carry
attribution and share-alike obligations, PD and CC0 rows carry none.

Throttled deliberately. Wikipedia asks for a contact in the User-Agent and will
return 429 if you hammer it, which it did to an earlier version of this script.
"""

import csv
import json
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

UA = "plates-app-research/1.0 (eggeppel34@gmail.com)"
PAUSE = 1.5

# Article wikitext is cached so that fixing the parser costs no API calls. Delete the
# directory to re-fetch.
CACHE = pathlib.Path(".wiki-cache")
CACHE.mkdir(exist_ok=True)
LIC_CACHE = CACHE / "licences.json"

STATES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
    "DC": "the District of Columbia", "FL": "Florida", "GA": "Georgia (U.S. state)",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
    "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
    "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
    "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
    "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
    "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
    "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
    "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington (state)",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
    "PR": "Puerto Rico",
    # Canada — the half Keegan's catalogue cannot supply at all.
    "ON": "Ontario", "QC": "Quebec", "BC": "British Columbia", "AB": "Alberta",
    "MB": "Manitoba", "SK": "Saskatchewan", "NS": "Nova Scotia",
    "NB": "New Brunswick", "NL": "Newfoundland and Labrador",
    "PE": "Prince Edward Island", "NT": "the Northwest Territories",
    "YT": "Yukon", "NU": "Nunavut",
}

# Only the passenger series. Commercial, dealer and specialty tables live under their
# own level-2 headings and are not what a plate-spotting game counts.
#
# The negative lookbehind is load-bearing. Without it this also matched
# "Non-passenger plates", which is a heading most of these articles have, and swept in
# every trailer, motorcycle, dealer, OHV and U.S. Senate table in the encyclopedia —
# 8.4% of the dataset, and it buried the real current-design row for eight jurisdictions
# under a trailer plate.
WANTED_SECTION = re.compile(r"(?<!non-)(?<!non )passenger\s+(base)?plates?", re.I)

# Headings that are never the general issue, at any level. Two different holes let
# these in.
#
# Ohio has a level-2 "Alternative passenger plates" section — one table, the yellow
# plate issued to DUI offenders, "1967–present" — and "passenger plates" is right
# there in the heading, so it read as a baseplate still in issue and outranked every
# real Ohio design back to 1908.
#
# Alberta has no "passenger" heading at all. Its history lives under "List of plate
# issues", so the whole-article fallback ran, and the fallback took the article: the
# personalized plates, the specialty plates, the non-passenger section, ANTIQUE,
# CONSULAR CORPS. Forty-two designs claiming 1983 to the present at once.
NOT_A_BASEPLATE = re.compile(
    r"\b(non-?passenger|alternative|optional|special(ty|ised|ized)?|personali[sz]ed|"
    r"vanity|commemorative|veteran|military|amateur radio|government|diplomatic|"
    r"dealer|trailer|motorcycle|truck|apportioned|temporary|disabled|charit\w+|"
    r"organizational|collegiate|sports?)\b", re.I)

# Jurisdictions whose final passenger row is open-ended — a start date and no end — so
# nothing in the row says "present" even though it is the design in issue. Checked one
# at a time against the article; the note is what the article actually shows.
LAST_ROW_IS_CURRENT = {
    "CA": "last row is the 2026 serial-format change; the section heading carries the "
          "'1963 to present' range instead of the row",
    "DE": "last row is 1969 — Delaware still issues that gold-on-blue design",
    "IL": "last row 2024, open-ended",
    "IN": "last row 2017, open-ended",
    "NJ": "last row April 2014, open-ended; heading reads '1959 to present'",
    "NU": "last row August 2025, the new polar-bear plate",
    "YT": "last row 1990, open-ended",
}


def api(host, **kw):
    kw.setdefault("format", "json")
    kw.setdefault("formatversion", "2")
    url = f"https://{host}/w/api.php?" + urllib.parse.urlencode(kw)
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return json.load(urllib.request.urlopen(req, timeout=60))
        except Exception:
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"gave up on {url[:120]}")


def level2_sections(wikitext):
    """Split into (heading, body) on level-2 headings, keeping subsections in body."""
    parts = re.split(r"\n==([^=][^\n]*?)==\n", "\n" + wikitext)
    out = []
    for i in range(1, len(parts) - 1, 2):
        out.append((parts[i].strip(), parts[i + 1]))
    return out


def sections(wikitext):
    """Every section at every heading level, as (path, body-without-subsections).

    `path` is the chain of headings above the body — ["List of plate issues",
    "Specialty plates"] — so a section can be judged on its ancestors as well as on
    its own name. `level2_sections` cannot do that: it hands back a level-2 body with
    every subsection still inside it, which is right when the level-2 heading is
    "Passenger baseplates" and wrong when it is "List of plate issues" and three of
    the subsections are specialty plates.
    """
    lead, path, out = [], [], []
    body = lead
    for line in wikitext.split("\n"):
        m = re.match(r"^(={2,6})\s*(.+?)\s*\1\s*$", line)
        if not m:
            body.append(line)
            continue
        level = len(m.group(1)) - 1        # == is depth 1
        path = path[:level - 1] + [m.group(2)]
        body = []
        out.append((list(path), body))
    return [(p, "\n".join(b)) for p, b in out]


def is_baseplate_section(path):
    """Whether a section is the general passenger issue, judged on its whole path."""
    return not any(NOT_A_BASEPLATE.search(h) for h in path)


# The digit lookarounds matter in both directions. Without a trailing one the serial
# range "A-1 to approximately A-112000" matched on the "2000" inside 112000 and was read
# as a date. Without a leading one, `\b` failed on the unspaced "April1975" these tables
# are full of, and the year fell through to being guessed from the filename.
YEAR_RE = r"(?<!\d)(1[89]\d{2}|20[0-4]\d)(?!\d)"
YEAR = re.compile(YEAR_RE)

# Filenames that carry the uploader's camera or screenshot date rather than anything
# about the plate. Texas's 1927 plate is illustrated by "Screen Shot 2024-03-11 at
# 10.03.23 PM.png", and reading a year out of that dated a 1927 plate to 2024.
JUNK_FILENAME = re.compile(r"screen ?shot|^img[_ ]|^dsc|^photo|^p10|whatsapp|^image[_ ]?\d", re.I)
FILE = re.compile(r"\[\[\s*(?:File|Image)\s*:\s*([^|\]]+?)\s*[|\]]", re.I)


def clean(text):
    """Wikitext to something readable enough for a caption."""
    text = re.sub(r"<ref[^>]*>.*?</ref>|<ref[^>]*/>", "", text, flags=re.S)
    text = re.sub(r"\{\{nowrap\|([^}]*)\}\}", r"\1", text)
    text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"\[\[[^|\]]*\|([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[\[([^\]]*)\]\]", r"\1", text)
    # A line break inside a cell separates two things and has to survive as a
    # separator, not be deleted. Ontario's dates cell is literally
    # `1997–2020<br>2020–present` — the white plate, the blue plate that was
    # scrapped, then the white plate again — and stripping the tag welded it into
    # "1997–20202020–present", which every year regex downstream reads straight
    # past as plain "1997".
    text = re.sub(r"<\s*(br|hr)\s*/?\s*>", "; ", text, flags=re.I)
    text = re.sub(r"</?[^>]+>", "", text)
    text = text.replace("&nbsp;", " ").replace("'''", "").replace("''", "")
    text = re.sub(r'\s*rowspan\s*=\s*"?\d+"?\s*\|?', " ", text)
    return " ".join(text.split()).strip(" |")


# What separates the two ends of a range, as opposed to a hyphen that is simply part
# of a word. An en or em dash, a spaced hyphen, a hyphen between two numbers, or the
# word "present". A bare letter-hyphen-digit is none of those: "mid-1997" is one date,
# and reading its hyphen as a range split Ohio's "August 1996 – mid-1997" into two
# periods and reported the design as overlapping itself.
RANGE_DASH = re.compile(r"[\u2013\u2014]|\s-\s|[0-9]\s*-\s*[0-9]|present", re.I)


def clean_dates(raw):
    """`clean`, plus the one thing a date cell needs that a description does not.

    A line break inside a date cell is ambiguous and both readings appear in the same
    article. Newfoundland writes `September 2003 – April<br>2007`, where the break is
    a line wrap inside one date, and two rows later `April 2007 – December 2021` and
    `January 2023 – November 2025` on separate lines, where it separates two periods
    of a plate that was withdrawn and reissued. Treating every break as a separator
    breaks the first; treating none as one welds the second.

    So the break is provisional, and each fragment is asked whether it can stand as a
    period on its own — a range or the word "present", and a year. "2007" cannot, and
    goes back onto the end of the date it fell off.
    """
    text = re.sub(r"<\s*br\s*/?\s*>|\n", " ; ", raw, flags=re.I)
    parts = [p.strip() for p in clean(text).split(";") if p.strip()]
    if len(parts) <= 1:
        return parts[0] if parts else ""

    merged, waiting = [], ""
    for p in parts:
        if YEAR.search(p) and RANGE_DASH.search(p):
            merged.append(f"{waiting} {p}".strip())
            waiting = ""
        elif merged:
            merged[-1] += " " + p          # fell off the end of the period above
        else:
            # Nothing to attach to yet: "mid<br>1993 – September 1996" opens with a
            # word that belongs to the date on the next line.
            waiting = f"{waiting} {p}".strip()
    if waiting:
        merged.append(waiting)
    return "; ".join(merged)


# A date cell: "1972", "January 2008 – December 2016", "June 2024 – present". Short, and
# always carries a year or the word "present" — which is what tells you which row is the
# design currently on the road.
DATES = re.compile(YEAR_RE + r"|present", re.I)

# Serial ranges live one column over and routinely contain a bare four-digit number:
# "A-1 to approximately S-2000" is not a date range. Real date cells never take this
# shape, so rejecting it is safe.
SERIALISH = re.compile(r"\bto approximately\b|\bto\s+[A-Z0-9]{1,4}[- ]?\d", re.I)


PLACEHOLDER = "blank license plate shape"

# "As above, but with thinner, squarer serial dies" — the article's own words for a
# variant of the row directly above rather than a new plate.
AS_ABOVE = re.compile(r"\s*(as|same as)\s+above\b", re.I)

# The article pointing at another section for a row: "As 1987-89 Montana Centennial plate
# (see Optional Plates below), but with serial screened". That parenthetical is Wikipedia
# saying this one is an optional plate documented elsewhere, so it does not belong in a
# baseplate history — Montana's 2012 block is four replica designs a motorist may choose
# between, and the Centennial is the one of them that is not a standard issue.
#
# Deliberately keyed on the cross-reference rather than on words like "centennial" or
# "veteran". It matches exactly one row in the corpus, which is the point: the article
# said so itself, so there is nothing to second-guess.
ELSEWHERE = re.compile(
    r"\(\s*see\b[^)]*\b(optional|special|specialty|personalized|vanity|commemorative)\b[^)]*\)",
    re.I)

# The last hole, and the only one that cannot be closed structurally. New Hampshire's
# "Passenger baseplates" section ends with two extra tables — the veteran plates, the
# state-parks decal plate — carrying no heading of their own and the identical column
# layout to the real one, so nothing about where they sit or how they are built says
# they are different. What gives them away is that they say so: "As standard veteran
# plate with DISABLED VETERAN screened in red".
#
# Kept as narrow as ELSEWHERE and for the same reason. These three phrases match five
# rows in the whole corpus, all five of them New Hampshire, and every one is a plate
# you have to qualify for rather than one you get with a car.
NOT_GENERAL_ISSUE = re.compile(r"\b(veterans?|national guard|state parks?)\b", re.I)

# And a row that opens by declaring itself a personalized plate, which is Prince
# Edward Island's "Personalized plates; can choose to have Province House on the
# left" — inside the baseplate section, so no heading rules it out.
#
# Anchored, unlike the above, because "personalized" turns up mid-sentence in
# descriptions of perfectly ordinary bases: New York's Liberty plate says the
# personalized version used a different serial format, and that row is the general
# issue.
OPENS_NON_GENERAL = re.compile(r"^\s*(personali[sz]ed|vanity)\b", re.I)


# Some rows only give themselves away in the filename of their own photograph.
# Ontario's baseplate table carries five historic-vehicle plates and an electric-
# vehicle one, each described in the same words as the general issue it is based on,
# so nothing in the row's text separates them — but the uploader named the file.
NOT_PASSENGER_FILE = re.compile(
    r"\b(tab|sticker|decal|validation|historic(al)? vehicle|electric vehicle|farm|"
    r"trailer|motorcycle|dealer|commercial|apportioned|snowmobile|diplomatic|"
    r"antique|amateur|moped|bus)\b", re.I)


def not_passenger(image):
    """Whether a filename says outright that this is not the general passenger issue.

    Unless it also says "passenger", which is the one case that matters: New Mexico's
    "1990 New Mexico license plate 466*KGC passenger stamped on trailer base" is a
    passenger plate that happens to have been struck on trailer stock, and the word
    "trailer" in it describes the metal rather than the plate.
    """
    if not image or not NOT_PASSENGER_FILE.search(image):
        return False
    return not re.search(r"\bpassenger\b", image, re.I)


# A filename claiming a range that has already closed — "Montana 2010–2016 standard
# license plate (old font).png". On a "– present" row that is the superseded variant.
CLOSED_RANGE = re.compile(YEAR_RE + r"\s*[-–—]\s*" + YEAR_RE)
SUPERSEDED_YEAR = 2026        # bumping this only ever makes the check stricter


def pick_image(files, current):
    """One filename out of an image cell that may hold several.

    75 rows stack more than one photograph in a single cell, and taking the first is
    usually right — they are variants of one design, listed oldest first. On a row that
    is still being issued it is the wrong end of the list. Montana's 2010–present cell
    holds `Montana 2010–2016 standard license plate (old font).png` next to `Montana
    2010-present standard plate (new font).jpg`; Montana changed the serial font in
    mid-2016, so the first file is the plate the current one replaced.

    Only two current rows in the corpus stack images, both Montana, and the other pair
    is two 2012 replica plates with nothing in either name to separate them — so the
    rule has to be narrow enough to leave that one alone. It keys on the filename saying
    outright which era it is: "present" wins, a closed range that has already ended loses,
    everything else keeps its position.
    """
    files = [f.replace("_", " ") for f in files]
    real = [f for f in files if not f.lower().startswith(PLACEHOLDER)]
    if not real:
        return files[0] if files else ""
    if not current or len(real) == 1:
        return real[0]

    def rank(f):
        if re.search(r"present", f, re.I):
            return 0
        m = CLOSED_RANGE.search(f)
        return 2 if m and int(m.group(2)) < SUPERSEDED_YEAR else 1

    return min(real, key=rank)


def owns_image(row):
    """True when the row has a real picture of its own — not the blank placeholder, and
    not one already borrowed from another row.

    Borrowing must never chain. Idaho's current design is the fourth link in an
    "as above" chain and Arizona's the third; following the chain to its end hands the
    2020 Arizona plate the 1996 embossed one, which looks nothing like it. One hop from
    a row that genuinely holds the picture, or nothing.
    """
    return bool(row[0]) and not row[0].lower().startswith(PLACEHOLDER) and not row[6]

# A cell may be written `attrs | content`. The attribute half never contains a link or a
# template, and always contains an `=`, which is what separates it from a content cell
# that merely happens to have a pipe in it.
CELL_ATTRS = re.compile(r'^\s*([^|\[\]{}\n]{0,120}?=[^|\[\]{}\n]{0,120}?)\s*\|(?!\|)')
ROWSPAN = re.compile(r'rowspan\s*=\s*"?(\d+)"?', re.I)
COLSPAN = re.compile(r'colspan\s*=\s*"?(\d+)"?', re.I)


def split_cells(block, sep="|"):
    """One wikitable row into raw cell strings.

    Cells are separated by `||` inline or by a `|` starting a line. Splitting naively on
    every pipe destroys file links and templates, so line starts are found first and the
    inline split tracks `[[ ]]` and `{{ }}` depth.
    """
    parts = []
    for line in re.split(r"\n\s*(?=" + re.escape(sep) + r")", "\n" + block):
        line = line.strip()
        if not line:
            continue
        if not line.startswith(sep):
            if parts:                         # continuation of the previous cell
                parts[-1] += "\n" + line
            continue
        line, buf, depth, i = line[1:], "", 0, 0
        while i < len(line):
            two = line[i:i + 2]
            if two in ("[[", "{{"):
                depth += 1
                buf, i = buf + two, i + 2
            elif two in ("]]", "}}"):
                depth -= 1
                buf, i = buf + two, i + 2
            elif two == "||" and depth <= 0:
                parts.append(buf)
                buf, i = "", i + 2
            else:
                buf, i = buf + line[i], i + 1
        parts.append(buf)
    return parts


def split_attrs(raw):
    m = CELL_ATTRS.match(raw)
    return (m.group(1), raw[m.end():]) if m else ("", raw)


def parse_grid(table):
    """(headers, rows) with every `rowspan` expanded into the rows it covers.

    Each cell comes back as (content, inherited, owner) — `inherited` meaning it was
    supplied by a span from an earlier row, and `owner` the index of the row that
    declared it. That distinction is the point of parsing the table properly rather than
    scanning it: a spanned Design cell is Wikipedia stating "this is the same design as
    above", which is evidence about the plate, not a guess.
    """
    table = re.sub(r"\n\|\}\s*$", "", table)
    blocks = table.split("|-")

    headers = []
    for b in blocks:
        if b.lstrip().startswith("!"):
            headers = [clean(split_attrs(c)[1]) for c in split_cells(b, "!")]
            break

    grid, pending = [], {}                    # column -> [rows left, content, owner]
    for b in blocks:
        s = b.lstrip()
        if s.startswith("!") or not s.startswith("|"):
            continue
        raw = split_cells(b)
        row, col, k = [], 0, 0
        while k < len(raw) or col in pending:
            if col in pending:
                left, content, owner = pending[col]
                row.append((content, True, owner))
                if left <= 1:
                    del pending[col]
                else:
                    pending[col][0] = left - 1
                col += 1
                continue
            attrs, content = split_attrs(raw[k])
            k += 1
            span = ROWSPAN.search(attrs)
            wide = COLSPAN.search(attrs)
            for _ in range(int(wide.group(1)) if wide else 1):
                row.append((content, False, len(grid)))
                if span and int(span.group(1)) > 1:
                    pending[col] = [int(span.group(1)) - 1, content, len(grid)]
                col += 1
        grid.append(row)
    return headers, grid


def column(headers, *words):
    for i, h in enumerate(headers):
        if any(w in h.lower() for w in words):
            return i
    return None


def parse_tables(body):
    """Rows of (image_file, dates, year, current, description, inherited, note).

    Rows with no image are KEPT, with an empty image_file.

    They used to be skipped, on the reasoning that a row with no picture is not a design
    worth recording. That was exactly backwards. Wyoming's current plate — June 2024 to
    present — has an empty image cell, so dropping those rows deleted the very thing a
    coverage check is looking for, and made "which jurisdictions are missing their
    present-day design?" unanswerable from the output. Worse, it made the answer look
    good: every surviving row had an image by construction.
    """
    rows = []
    for table in re.findall(r"\{\|.*?\n\|\}", body, flags=re.S):
        headers, grid = parse_grid(table)
        c_img = column(headers, "image", "photo")
        # "issued" on its own is in there for Alberta, whose column is headed just
        # "Issued". Without it the table failed the header test, fell through to the
        # positional scanner, and the scanner takes the first cell over 24 characters
        # as the design — which in that table is the serial range. Alberta's 1921
        # plate was described as "1 to approximately 40-000".
        #
        # "Serials issued" matches too, but only ever after a real date column, since
        # `column` returns the first hit and every one of these tables puts the dates
        # first. If a table somehow has only the serial column, `SERIALISH` below
        # throws the value out anyway.
        c_date = column(headers, "date", "first issued", "year", "issued")
        c_desc = column(headers, "design", "description")
        if c_img is None or c_date is None:
            rows += scan_table(table)         # headerless: fall back to scanning
            continue

        parsed = []
        for row in grid:
            def get(i):
                return row[i] if i is not None and i < len(row) else ("", False, -1)

            dates = clean_dates(get(c_date)[0])
            if SERIALISH.search(dates) or not DATES.search(dates):
                dates = ""

            img_raw, img_inherited, _ = get(c_img)
            image = pick_image(FILE.findall(img_raw),
                               bool(re.search(r"present", dates, re.I)))
            # Renewal tabs, stickers and decals sit in the same tables in some states.
            if not_passenger(image):
                continue
            desc_raw, desc_inherited, desc_owner = get(c_desc)
            desc = clean(desc_raw)
            if not (dates or desc or image):
                continue                      # spacer or note row, not a design
            if ELSEWHERE.search(desc) or NOT_GENERAL_ISSUE.search(desc) \
                    or OPENS_NON_GENERAL.match(desc):
                continue                      # an optional plate, not a baseplate
            parsed.append([image, dates, desc, desc_inherited, desc_owner,
                           img_inherited, ""])

        # Wikipedia says "same design as above" by spanning the Design cell. Where it
        # does, and the row's own picture is missing or the blank placeholder, the
        # picture from the row that owns that Design cell is the right one to show —
        # that is the encyclopedia's own statement, not an inference.
        #
        # California is the case that exposed this. Its 2026 row is a serial-format
        # change inside a Design cell spanning six rows back to 1993, so the plate is
        # the 2011 one; with no picture of its own it read as a gap, and a DMV sample
        # image of the 1982 sunset plate got merged in to fill it.
        for i, r in enumerate(parsed):
            if r[0] and not r[0].lower().startswith(PLACEHOLDER):
                continue
            donor, why = None, ""
            if r[3] and r[4] >= 0:
                donor = next((d for d in reversed(parsed[:i])
                              if d[4] == r[4] and owns_image(d)), None)
                why = "Wikipedia spans one Design cell across both rows"
            # The other way these articles say "same design": a description that opens
            # "As above, but with …". That is a variant — new dies, a screened serial, a
            # moved sticker box — on the plate directly above, so the picture above is
            # the right one to show. Only ever the row *immediately* above: Idaho's
            # current design is the fourth "As above" in a chain, and walking the chain
            # to the end lands on the 1987 green-on-white plate, which is a different
            # plate entirely.
            elif AS_ABOVE.match(r[2]) and i and owns_image(parsed[i - 1]):
                donor = parsed[i - 1]
                why = 'the row describes itself as "as above, but …"'
            if donor:
                r[0], r[5] = donor[0], True
                r[6] = f"shows the {donor[1] or 'preceding'} plate — {why}"

        for image, dates, desc, _, _, inherited, note in parsed:
            y = YEAR.search(dates or "")
            if not y and image and not JUNK_FILENAME.search(image):
                y = YEAR.search(image)
            rows.append((image, dates, y.group(1) if y else "",
                         1 if re.search(r"present", dates, re.I) else 0,
                         desc[:180], inherited, note))
    return rows


def scan_table(table):
    """The old positional scanner, kept for the handful of tables with no header row."""
    rows = []
    for block in table.split("|-")[1:]:
        if block.lstrip().startswith("!"):
            continue
        f = FILE.search(block)
        image = f.group(1).replace("_", " ") if f else ""
        if not_passenger(image):
            continue
        cells = [c for c in (clean(c) for c in re.split(r"\|\||\n\s*\|", block)) if c]
        head = cells[1] if len(cells) > 1 else ""
        ok_head = len(head) <= 60 and DATES.search(head) and not SERIALISH.search(head)
        dates = head if ok_head else next(
            (c for c in cells if len(c) <= 40 and DATES.search(c)
             and not SERIALISH.search(c)), "")
        # The description is "the first long cell that is not the dates", so the
        # comparison has to be against the cell as it appeared. Normalising the dates
        # first stopped the guard matching, and Virginia's design column became
        # "July 1, 2002 – early; 2003" — the date cell, described as itself.
        desc = next((c for c in cells if len(c) > 24 and c != dates), "")
        dates = clean_dates(dates)
        if not (dates or desc or image) or ELSEWHERE.search(desc) \
                or NOT_GENERAL_ISSUE.search(desc) or OPENS_NON_GENERAL.match(desc):
            continue
        y = YEAR.search(dates or "")
        if not y and image and not JUNK_FILENAME.search(image):
            y = YEAR.search(image)
        rows.append((image, dates, y.group(1) if y else "",
                     1 if re.search(r"present", dates, re.I) else 0,
                     desc[:180], False, ""))
    return rows


def meta(extmetadata, key, default):
    """One field out of `extmetadata`, defensively.

    The documented shape is {"LicenseShortName": {"value": ...}}, and for a handful of
    files out of 3,245 it is not: `extmetadata` itself can arrive as a list, and so can
    an individual field's value. Both variants crashed a full run at the very end,
    twice, so every level is now unwrapped rather than trusted.
    """
    if isinstance(extmetadata, list):
        extmetadata = next((e for e in extmetadata if isinstance(e, dict)), {})
    if not isinstance(extmetadata, dict):
        return default
    v = extmetadata.get(key)
    if isinstance(v, list):
        v = v[0] if v else None
    if isinstance(v, dict):
        v = v.get("value")
    return default if v in (None, "") else str(v)


def licences(files):
    """File name -> (url, licence, artist). Batched; Commons falls back to en.wiki.

    Written to disk after every batch, so a crash or an interrupt costs one batch
    rather than the whole pass.
    """
    cache = json.loads(LIC_CACHE.read_text()) if LIC_CACHE.exists() else {}
    out = {k: tuple(v) for k, v in cache.items()}
    titles = ["File:" + f for f in files]
    for host in ("commons.wikimedia.org", "en.wikipedia.org"):
        todo = [t for t in titles if t[5:] not in out]
        for i in range(0, len(todo), 25):
            d = api(host, action="query", titles="|".join(todo[i:i + 25]),
                    prop="imageinfo", iiprop="url|extmetadata",
                    iiextmetadatafilter="LicenseShortName|Artist")
            for p in d.get("query", {}).get("pages", []):
                if not isinstance(p, dict) or "missing" in p or not p.get("imageinfo"):
                    continue
                info = p["imageinfo"][0]
                em = info.get("extmetadata", {})
                out[p["title"][5:]] = (
                    info.get("url", ""),
                    meta(em, "LicenseShortName", "(none stated)"),
                    clean(meta(em, "Artist", ""))[:60],
                )
            LIC_CACHE.write_text(json.dumps({k: list(v) for k, v in out.items()}))
            time.sleep(PAUSE)
    return out


def main():
    writer = csv.writer(sys.stdout)
    writer.writerow(["code", "dates_issued", "first_issued", "is_current",
                     "description", "image_file", "image_url", "licence", "credit",
                     "source_page", "image_note"])

    found = {}
    for code, name in STATES.items():
        page = f"Vehicle registration plates of {name}"
        cached = CACHE / f"{code}.wikitext"
        if cached.exists():
            d = {"parse": {"wikitext": cached.read_text()}}
        else:
            d = api("en.wikipedia.org", action="parse", page=page, prop="wikitext",
                    redirects=1)
            if "error" in d:
                print(f"{code}: NO ARTICLE ({page})", file=sys.stderr)
                time.sleep(PAUSE)
                continue
            cached.write_text(d["parse"]["wikitext"])

        wt = d["parse"]["wikitext"]
        if re.search(r"\{\{\s*(disambig|set index article)", wt, re.I):
            print(f"{code}: DISAMBIGUATION PAGE ({page}) — needs a qualified title",
                  file=sys.stderr)
            time.sleep(PAUSE)
            continue

        # A named "Passenger baseplates" section is the article saying outright which
        # tables are the general issue, so it is taken first and taken whole —
        # subsections and all, because inside it they are date ranges.
        rows = []
        for heading, body in level2_sections(wt):
            if WANTED_SECTION.search(heading) and is_baseplate_section([heading]):
                rows += parse_tables(body)

        # Failing that, walk every section and take the ones nothing in their path
        # disqualifies. Reading the whole article instead — which is what this used to
        # do — is how Alberta ended up with its specialty and non-passenger tables in
        # the baseplate history.
        if not rows:
            for path, body in sections(wt):
                if is_baseplate_section(path):
                    rows += parse_tables(body)

        if not rows:                      # some articles are one flat table, no headings
            rows = parse_tables(wt)

        # De-duplicate on the image, but never collapse rows that have no *distinct*
        # image — each is a separate design that happens to lack a picture.
        #
        # The placeholder counts as no image. It is one file, reused across every gap in
        # an article, so keying de-duplication on the filename silently threw away every
        # placeholder row after the first — including Alaska's, Idaho's, Missouri's and
        # Utah's current designs, all of which are "– present" rows illustrated with it.
        seen, unique = set(), []
        for r in rows:
            # Never de-duplicate a row that has no distinct image of its own: an empty
            # cell, the shared placeholder, or an image inherited from a rowspan above.
            # Inherited rows legitimately repeat their parent's filename, and keying on
            # the filename deleted them the moment inheritance was added.
            if not r[0] or r[0].lower().startswith(PLACEHOLDER) or r[5]:
                unique.append(r)
            elif r[0] not in seen:
                seen.add(r[0])
                unique.append(r)

        # And then again on the whole row. Where one Design cell spans several serial
        # formats, the rowspan expansion emits the design once per format — Colorado's
        # 1956 plate three times, Massachusetts' current plate eight. Those are real
        # separate serial series, but this file has no serial column, so the rows come
        # out byte-identical: same dates, same description, same photograph. Nothing
        # downstream can tell them apart, which is another way of saying they carry no
        # information, and 243 of them were reading as designs overlapping themselves.
        # And then again on the design itself, ignoring which photograph illustrates
        # it. Alberta's 1921 plate is three rows because the article has three
        # photographs of it — a 3-digit serial, a 4-digit, a 5-digit — sharing one
        # Design cell by rowspan. That is a photo archive's distinction, not a design
        # history's, and on the Historical plates screen it comes out as the same
        # 1921 plate listed three times in a row.
        #
        # Only where the description is non-empty, because an empty one is not
        # evidence that two rows describe the same plate.
        # Collapsing keeps the first row but takes the best picture any of them had.
        # New Hampshire's current plate arrives as four identical rows, the first two
        # with an empty image cell and the last two carrying the photograph; keeping
        # the first and discarding the rest threw the only photograph of a plate still
        # on the road out of the file.
        def has_picture(r):
            return bool(r[0]) and not r[0].lower().startswith(PLACEHOLDER)

        identical, once = {}, []
        for r in unique:
            key = (r[1], r[4]) if r[4] else (r[0], r[1], r[4])
            kept = identical.get(key)
            if kept is None:
                identical[key] = r = list(r)
                once.append(r)
            elif not has_picture(kept) and has_picture(r):
                kept[0], kept[5], kept[6] = r[0], r[5], r[6]
        unique = [tuple(r) for r in once]
        # Apply the reviewed override: mark the chronologically last row current.
        if code in LAST_ROW_IS_CURRENT and not any(r[3] for r in unique):
            dated = [r for r in unique if r[2]]
            if dated:
                latest = max(dated, key=lambda r: r[2])
                unique = [(r[0], r[1], r[2], 1 if r is latest else r[3], r[4], r[5],
                           r[6]) for r in unique]

        found[code] = (page, unique)
        print(f"{code}: {len(unique)} designs", file=sys.stderr)
        time.sleep(PAUSE)

    every = sorted({r[0] for _, rows in found.values() for r in rows if r[0]})
    print(f"resolving licences for {len(every)} images...", file=sys.stderr)
    lic = licences(every)

    total = 0
    for code, (page, rows) in found.items():
        for image, dates, year, current, desc, _, note in sorted(
                rows, key=lambda r: r[2] or "0000"):
            url, name, credit = lic.get(image, ("", "", "")) if image else ("", "", "")
            if image and not url:
                name = "(unresolved)"
            writer.writerow([code, dates, year, current, desc, image, url, name, credit,
                             "https://en.wikipedia.org/wiki/" +
                             urllib.parse.quote(page.replace(" ", "_")), note])
            total += 1
    print(f"{total} designs across {len(found)} jurisdictions", file=sys.stderr)


if __name__ == "__main__":
    main()
