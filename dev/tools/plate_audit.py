#!/usr/bin/env python3
"""Flags what is wrong with the plate database, without fixing any of it.

    python3 ios/tools/plate_audit.py > dev/research/plate-audit.md

Three classes of fault, all of which show up on screen as something a reader can
tell is wrong even without knowing anything about plates:

  TIMELINE   A jurisdiction's designs are supposed to tile its history — one after
             another, no overlap, no hole. Instead you get 2008-2010, 2010-present
             and 2009-present all in the same list, which cannot all be true, or a
             decade with nothing in it at all.

  COVERAGE   A jurisdiction the app knows about but has nothing to show for.
             Wyoming and Yukon are in the plate list and in the history, and in the
             lookup index they simply do not exist.

  STALE      A design flagged as the one currently on the road, dated 1990. Some of
             these are honest — Delaware really has been issuing the same gold-on-navy
             since 1969 — and some are a specialty plate that got scraped as though it
             were the general issue. Either way a "current" plate from before 2010 is
             worth a human looking at, and one from before 2000 is worth looking at
             first.

FLAGGING, NOT FIXING. Every fault here is a claim about the world, and the fix for
"Ontario's current plate says 1997-20202020-present" is to find out what Ontario
actually issues, not to make the string parse. The script is deterministic and its
output is diffable, so the way to work through this is to fix sources, re-scrape,
re-run, and watch the report shrink.

The timeline audit runs over every row in the research CSV by default, because the
database is the thing being audited. `--scope shipped` narrows it to the rows that
have a photograph — the ones the Historical plates screen actually draws — which
answers a different question: not "is the data right" but "does the list on screen
read as continuous". Gaps under that scope mostly mean nobody photographed that
year, which is a hole in the archive rather than a fault in the data.
"""

import argparse
import csv
import json
import os
import re
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HISTORY = os.path.join(REPO, "dev", "research", "plate-history.csv")
PLATE_SWIFT = os.path.join(REPO, "ios", "Plates", "Domain", "Plate.swift")
LOOKUP_JSON = os.path.join(REPO, "ios", "Plates", "Resources", "PlateLookup.json")
HISTORY_JSON = os.path.join(REPO, "ios", "Plates", "Resources", "PlateHistory.json")
# Flags a person has looked at and found to be right about the world. Delaware really
# has issued the same plate since 1969; saying so once should stop it being reported
# forever. Without this the report cannot shrink: the genuinely-correct oddities sit
# in it at the same volume as the faults, and after two passes nobody reads either.
ACCEPTED = os.path.join(REPO, "dev", "research", "plate-audit-accepted.csv")

PLACEHOLDER = "blank license plate shape"

# A design still being issued has to have started recently enough to be plausible.
# Two thresholds rather than one: below the first is "check this", below the second
# is "this is almost certainly a specialty plate or a scraping error".
STALE_YEAR = 2010
VERY_STALE_YEAR = 2000

# A jurisdiction whose newest photograph predates this cannot illustrate anything
# currently on the road, however many historical pictures it has.
ARCHIVE_YEAR = 2000

# How many members of an overlapping cluster to name before saying "and N more".
MAX_CLUSTER = 6

# Wikipedia's way of writing "same plate, one detail different" \u2014 a county-name
# variant, a smaller logo, screened rather than embossed. These are *supposed* to run
# alongside the design they refer to, so a cluster made of one design plus its own
# variants is not a conflict; it is the table working as intended.
VARIANT = re.compile(r"^\s*(as|same as)\s+above\b", re.I)

YEAR = re.compile(r"(?<![0-9])(1[89][0-9]{2}|20[0-9]{2})(?![0-9])")
# `1978–82`, where the second half drops the century.
SHORT_RANGE = re.compile(r"(1[89]|20)([0-9]{2})\s*[-–—]\s*([0-9]{2})(?![0-9])")
OPEN_ENDED = re.compile(r"present|current|now|to date", re.I)
# Five or more digits in a row is not a date anybody wrote. It is two cells that
# got concatenated — "1997–2020" and "2020–present" becoming "1997–20202020–present"
# — and the year regex silently reads straight past it.
DIGIT_RUN = re.compile(r"[0-9]{5,}")

# Everything is measured in months, not years. Maryland ran one design through
# November 2006 and its replacement from December 2006, and at year resolution that
# is an overlap and a false alarm. Roughly a third of these strings name a month, so
# throwing that away costs real precision.
MONTHS = {m: i for i, m in enumerate(
    ["january", "february", "march", "april", "may", "june", "july",
     "august", "september", "october", "november", "december"], start=1)}
MONTH_RE = re.compile("|".join(MONTHS), re.I)
# Editors write these as often as they write a month name.
VAGUE = {"early": 2, "mid": 6, "late": 11, "spring": 4, "summer": 7,
         "fall": 10, "autumn": 10, "winter": 12}
VAGUE_RE = re.compile("|".join(VAGUE), re.I)

# The dash between the two halves of a range. Not the one inside "40-000".
SPLIT = re.compile(r"\s*[–—]\s*|\s+-\s+|(?<=[a-z0-9])-(?=[A-Za-z])")

OPEN = 9999 * 12


def year_of(index):
    """The calendar year a month index falls in.

    Months run 1-12, so a year occupies `y*12+1` through `y*12+12` and December of
    one year shares an index with "month zero" of the next. Subtracting one before
    dividing is what keeps December in the year it belongs to.
    """
    return (index - 1) // 12


def month_of(text, default):
    """The month a half of a range names, or `default` if it names none."""
    m = MONTH_RE.search(text)
    if m:
        return MONTHS[m.group(0).lower()]
    v = VAGUE_RE.search(text)
    return VAGUE[v.group(0).lower()] if v else default


# ---------------------------------------------------------------- date parsing

class Span:
    """A design's life, as a half-open interval of months, [start, end).

    Half-open is the whole reason the arithmetic works. Consecutive designs share
    their changeover date — 2000–2018 is followed by 2018–present — so the end has
    to be exclusive, or every well-formed handover in the database reports as an
    overlap.

    Which leaves one ambiguity, and it is not resolvable from the string alone.
    "1919–20" on an early annual plate means *issued in 1919 and again in 1920*;
    "2000–2018" on a modern one means *replaced during 2018*. Same punctuation,
    answer off by a year. `resolve_ends` settles it by asking the neighbours.
    """

    __slots__ = ("start", "end", "closed_end", "open", "malformed", "raw",
                 "start_year", "end_year")

    def __init__(self, raw):
        self.raw = raw
        self.malformed = bool(DIGIT_RUN.search(raw))
        self.open = bool(OPEN_ENDED.search(raw))
        self.closed_end = None               # end year, before the neighbour check
        self.end_year = None

        # A plate can be withdrawn and reissued, and the scraper records that as
        # several periods in one cell: Florida's white plate ran November 2009 to May
        # 2021, came back for four months in 2024, twice more in 2025. For an overlap
        # check what matters is the outer bounds — first issue to last withdrawal —
        # so the periods are folded into one interval rather than each being its own
        # design. The gaps between them are the plate's own history, not holes in the
        # jurisdiction's.
        periods = [p.strip() for p in raw.split(";") if p.strip()]
        if len(periods) > 1:
            parts = [Span(p) for p in periods]
            usable = [p for p in parts if p.usable]
            self.malformed = self.malformed or not usable
            if usable:
                first, last = usable[0], max(usable, key=lambda p: p.end)
                self.start_year, self.start = first.start_year, first.start
                self.end, self.end_year = last.end, last.end_year
                self.closed_end = last.closed_end
            else:
                self.start = self.end = self.start_year = None
            return

        years = [int(y) for y in YEAR.findall(raw)]
        if len(years) > 2:
            self.malformed = True

        halves = SPLIT.split(raw, maxsplit=1)
        left, right = halves[0], (halves[1] if len(halves) > 1 else None)

        self.start_year = self._year_in(left, years)
        if self.start_year is None:
            self.start = self.end = None
            return

        self.start = self.start_year * 12 + month_of(left, 1)

        if self.open:
            self.end = OPEN
            return

        short = SHORT_RANGE.search(raw)
        if short:
            # "1978–82" — carry the century down, roll it forward for "1998–02".
            century = int(short.group(1)) * 100
            first, second = int(short.group(2)), int(short.group(3))
            self.end_year = century + second + (100 if second < first else 0)
        elif right is not None:
            self.end_year = self._year_in(right, years[1:]) or self.start_year
        else:
            # One date and no range: on the road for that year and no longer.
            self.end = (self.start_year + 1) * 12 + 1
            self._check()
            return

        # A named month is a real handover date and is taken at face value. A bare
        # year is all anybody recorded, and `resolve_ends` decides whether the design
        # is off the road at the start of that year or at the end of it.
        month = month_of(right or "", None)
        if month is None:
            self.closed_end = self.end_year
            self.end = self.end_year * 12 + 1
        else:
            self.end = self.end_year * 12 + month
        self._check()

    @staticmethod
    def _year_in(text, fallback):
        """The year this half of the range names, or the next one the string had.

        The fallback is for "November – December 2006", where the opening month
        carries no year of its own and means the same year as the closing one.
        """
        found = YEAR.findall(text or "")
        if found:
            return int(found[0])
        return int(fallback[0]) if fallback else None

    def _check(self):
        if self.start is not None and self.end is not None and self.end <= self.start:
            self.malformed = True

    @property
    def usable(self):
        return self.start is not None and self.end is not None and not self.malformed

    def overlaps(self, other):
        return max(self.start, other.start) < min(self.end, other.end)

    def label(self):
        if self.start_year is None:
            return "?"
        if self.end == OPEN:
            return f"{self.start_year}–present"
        last = year_of(self.end - 1)      # end is exclusive; this is the last month lived
        if last <= self.start_year:
            return str(self.start_year)
        return f"{self.start_year}–{last}"


def resolve_ends(spans):
    """Decide whether a bare end year belongs to this design or to its successor.

    See `Span`. If something else in the same jurisdiction starts in the year this
    one ends, that year is the handover and the range stops at the start of it. If
    nothing does, the plate was on the road for that year and the range runs to the
    end of it — otherwise every annual plate of the 1910s reports a hole after
    itself, and 1978–82 followed by 1983 reads as a missing year.
    """
    start_years = {s.start_year for s in spans if s.start_year is not None}
    for s in spans:
        if s.closed_end is not None and s.closed_end not in start_years:
            s.end = (s.closed_end + 1) * 12 + 1
        s._check()


def cluster(entries):
    """Groups of designs that all claim overlapping years.

    Clusters rather than pairs, on purpose. Alberta's specialty plates \u2014
    ANTIQUE, CONSULAR CORPS and a dozen others all running 1984 to the present
    alongside the general issue \u2014 make 389 overlapping *pairs* out of about
    four actual problems, and a pairwise list of that is not something anybody
    reads to the end.
    """
    entries = sorted(entries, key=lambda e: (e[0].start, e[0].end))
    out, group, reach = [], [], None
    for entry in entries:
        if group and entry[0].start < reach:
            group.append(entry)
            reach = max(reach, entry[0].end)
        else:
            if len(group) > 1:
                out.append(group)
            group, reach = [entry], entry[0].end
    if len(group) > 1:
        out.append(group)
    return out


# ---------------------------------------------------------------- loading

def jurisdictions():
    """Code to name, read off the app's own catalog rather than off the CSV.

    Coverage has to be measured against what the app claims to know about. Counting
    distinct codes in the research file can only ever tell you the file is
    self-consistent, which is not the question.
    """
    src = open(PLATE_SWIFT).read()
    found = re.findall(r'\.init\(code:\s*"([A-Z]{2})",\s*name:\s*"([^"]+)"', src)
    return dict(found)


def newest_photo(rows):
    """The latest year among a jurisdiction's photographed designs."""
    years = [Span((r["dates_issued"] or r["first_issued"] or "").strip()).start_year
             for r in rows if shipped(r)]
    years = [y for y in years if y]
    return max(years) if years else None


def shipped(row):
    """Whether `plate_history_build.py` would put this row on screen."""
    return (row["image_url"].startswith("http")
            and PLACEHOLDER not in row["image_file"].lower())


def load(path, scope):
    rows = list(csv.DictReader(open(path)))
    if scope == "shipped":
        rows = [r for r in rows if shipped(r)]
        # Same dedupe key the build uses, so the report describes the list a person
        # is actually looking at rather than a longer one behind it.
        seen, unique = set(), []
        for r in rows:
            key = (r["code"], r["dates_issued"], r["image_url"])
            if key in seen:
                continue
            seen.add(key)
            unique.append(r)
        rows = unique

    by_code = defaultdict(list)
    for r in rows:
        by_code[r["code"]].append(r)
    return by_code


def accepted():
    """(code, kind, subject) that have been checked, with why."""
    if not os.path.exists(ACCEPTED):
        return {}
    return {(r["code"], r["kind"], r["subject"].strip()): r
            for r in csv.DictReader(open(ACCEPTED))}


def resource_codes(path, key=None):
    """Codes present in one of the app's shipped JSON resources, or None if absent."""
    if not os.path.exists(path):
        return None
    data = json.load(open(path))
    if key is None:
        return {c for c, v in data.items() if v}
    return {d[key] for d in data.get("designs", []) if d.get(key)}


# ---------------------------------------------------------------- the three audits

def timeline_faults(rows):
    """Overlaps, holes, repeats and unparseable date strings within one jurisdiction.

    Byte-identical rows come out first and are counted rather than analysed. They are
    an artefact of how the tables are read: where one Design cell spans several serial
    formats, the rowspan expansion emits the design once per format. Those really are
    separate serial series, so the rows are not wrong — but they are the same design
    with the same dates and the same photograph, and left in they would report as a
    pile of designs overlapping themselves.
    """
    seen, unique, duplicates = set(), [], 0
    for r in rows:
        key = (r["dates_issued"], r["description"], r["image_url"])
        if key in seen:
            duplicates += 1
            continue
        seen.add(key)
        unique.append(r)

    parsed = []
    for r in unique:
        raw = (r["dates_issued"] or r["first_issued"] or "").strip()
        parsed.append((Span(raw), r["description"][:60].replace("\n", " ")))

    resolve_ends([s for s, _ in parsed])

    spans = [e for e in parsed if e[0].usable]
    malformed = [e for e in parsed if e[0].malformed]
    undated = [e for e in parsed if not e[0].usable and not e[0].malformed]

    spans.sort(key=lambda e: (e[0].start, e[0].end))

    # A hole is measured against the furthest point reached so far, not against the
    # previous row — otherwise a long series that swallows several short ones reports
    # a fake gap after every one of them.
    #
    # Only holes of a year or more. A month or two between a design ending and the
    # next one starting is how these were actually written, not a missing plate.
    gaps, reach = [], None
    for s, desc in spans:
        if reach is not None and s.start - reach >= 12:
            gaps.append((year_of(reach), year_of(s.start), desc))
        reach = max(reach or 0, s.end)

    return cluster(spans), gaps, malformed, undated, duplicates


def stale_current(rows):
    """Designs flagged as still being issued whose start year is implausibly old."""
    out = []
    for r in rows:
        if r["is_current"] != "1":
            continue
        s = Span((r["dates_issued"] or r["first_issued"] or "").strip())
        if s.start_year is None:
            out.append((0, s, r))
        elif s.start_year < STALE_YEAR:
            out.append((s.start_year, s, r))
    return sorted(out, key=lambda e: e[0])


# ---------------------------------------------------------------- report

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv", default=HISTORY)
    ap.add_argument("--scope", choices=("all", "shipped"), default="all")
    args = ap.parse_args()

    names = jurisdictions()
    signed_off = accepted()
    by_code = load(args.csv, args.scope)
    everything = load(args.csv, "all")

    print(f"# Plate database audit\n")
    print(f"`{os.path.relpath(args.csv, REPO)}`, scope `{args.scope}` "
          f"\u2014 {sum(len(v) for v in by_code.values())} rows across "
          f"{len(by_code)} jurisdictions.\n")
    print("Nothing here is fixed automatically. Every line is a claim about the "
          "world that wants a person to check it.\n")

    totals = defaultdict(int)

    # ---- 1. timelines
    print("## 1. Timeline conflicts\n")
    print("A jurisdiction's designs should tile its history: each one picking up "
          "where the last left off. An **OVERLAP** means two designs claim the same "
          "months and at most one of them can be the general issue; a **GAP** means "
          "a stretch of road with nothing on it.\n")
    print("Two softer labels keep those from drowning. **VARIANTS** is a design plus "
          "rows Wikipedia describes as \u201cas above, but\u2026\u201d, which are "
          "meant to run alongside it. **REPEATED SPAN** is the same years listed "
          "twice from different rows.\n")
    print("The backticked range is what the parser understood; the quoted string "
          "beside it is what Wikipedia actually wrote.\n")

    any_timeline, accepted_overlaps = False, []
    for code in sorted(by_code):
        overlaps, gaps, malformed, undated, duplicates = timeline_faults(by_code[code])
        totals["duplicate"] += duplicates
        if not (overlaps or gaps or malformed or duplicates):
            continue
        any_timeline = True
        print(f"### {names.get(code, code)} ({code})\n")

        for group in overlaps:
            lo = year_of(min(s.start for s, _ in group))
            hi = max(s.end for s, _ in group)
            years = "present" if hi == OPEN else str(year_of(hi - 1))
            # Two different faults wear the same shape. Every member covering the
            # identical range is one design reached by two routes \u2014 usually a year
            # that appears in both the serial-format table and the design table of
            # the same article. Members covering *different* ranges is the real
            # conflict: 2008-2010, 2010-present and 2009-present cannot all be true.
            subject = f"{lo}-{years}"
            ok = signed_off.get((code, "overlap", subject))
            if ok:
                accepted_overlaps.append((code, subject, ok))
                continue
            same = len({(s.start, s.end) for s, _ in group}) == 1
            variants = sum(1 for _, desc in group if VARIANT.match(desc))
            if same:
                kind, key = "REPEATED SPAN", "repeat"
            elif variants >= len(group) - 1:
                kind, key = "VARIANTS", "variant"
            else:
                kind, key = "OVERLAP", "overlap"
            totals[key] += 1
            print(f"- **{kind}** {len(group)} designs all claim years within "
                  f"`{lo}`\u2013`{years}`:")
            for s, desc in group[:MAX_CLUSTER]:
                mark = " _(variant)_" if VARIANT.match(desc) else ""
                print(f"  - `{s.label()}` \u2014 {s.raw!r} \u2014 {desc}{mark}")
            if len(group) > MAX_CLUSTER:
                print(f"  - \u2026and {len(group) - MAX_CLUSTER} more")
        for start, end, desc in gaps:
            totals["gap"] += 1
            span = end - start
            print(f"- **GAP** {span} year{'s' if span != 1 else ''} with no design: "
                  f"`{start}`\u2013`{end}` (next is {desc})")
        for s, desc in malformed:
            totals["malformed"] += 1
            print(f"- **UNPARSEABLE** {s.raw!r} \u2014 {desc}")
        if duplicates:
            print(f"- **DUPLICATE** {duplicates} row(s) repeat an earlier row exactly")
        if undated:
            print(f"- {len(undated)} row(s) carry no year at all")
        print()

    if not any_timeline:
        print("None.\n")

    if accepted_overlaps:
        print("### Reviewed and accepted\n")
        print("Designs that really did run at the same time \u2014 a state issuing two "
              "standard bases at once, or an old one still going out while its "
              "replacement rolls in. Recorded in "
              "`dev/research/plate-audit-accepted.csv` with the reasoning.\n")
        for code, subject, ok in accepted_overlaps:
            totals["accepted"] += 1
            print(f"- **{names.get(code, code)} ({code}), {subject}** "
                  f"\u2014 checked {ok['checked']}. {ok['reason']}")
        print()

    # ---- 2. coverage
    print("## 2. Missing jurisdictions\n")
    print("A jurisdiction the app lists but has nothing to show for. The lookup "
          "screen is the one that hurts \u2014 typing a state's name and getting "
          "nothing reads as a broken search rather than a missing photograph.\n")

    in_history = resource_codes(HISTORY_JSON) or set()
    in_lookup = resource_codes(LOOKUP_JSON, key="c")
    lookup_known = in_lookup is not None

    print("| Jurisdiction | Rows | Photographed | Newest photo | Historical screen | Lookup |")
    print("|---|---:|---:|---:|---|---|")
    for code, name in sorted(names.items(), key=lambda kv: kv[1]):
        rows = everything.get(code, [])
        photos = sum(1 for r in rows if shipped(r))
        hist_ok = code in in_history
        look_ok = (code in in_lookup) if lookup_known else None
        if photos and hist_ok and (look_ok is not False):
            continue
        if not photos:
            totals["no_photos"] += 1
        if not hist_ok:
            totals["missing_history"] += 1
        if look_ok is False:
            totals["missing_lookup"] += 1
        newest = newest_photo(rows) or "none"
        print(f"| {name} ({code}) | {len(rows)} | {photos} | {newest} | "
              f"{'yes' if hist_ok else '**MISSING**'} | "
              f"{'yes' if look_ok else '**MISSING**' if lookup_known else '?'} |")
    print()

    # The column that explains the two above. A jurisdiction can carry sixty-five
    # photographs and still be invisible to the lookup, because the lookup indexes
    # designs that are on the road and every one of those photographs is of a plate
    # from the 1980s. That is a hole in the archive, not a fault in the builder, and
    # no amount of re-running the pipeline will close it.
    stops_early = []
    for code, name in sorted(names.items(), key=lambda kv: kv[1]):
        newest = newest_photo(everything.get(code, []))
        if newest is not None and newest < ARCHIVE_YEAR:
            stops_early.append(f"{name} ({code}), newest is {newest}")
            totals["archive_stops_early"] += 1
    print(f"### Archive stops before {ARCHIVE_YEAR}\n")
    print("Nothing photographed since. These cannot show a current plate on any "
          "screen until somebody finds a picture of one.\n")
    print(("\n".join(f"- {line}" for line in stops_early)
           if stops_early else "None.") + "\n")

    # Photographs of the design that is on the road right now. Separate from the
    # count above because a jurisdiction can have ninety historical photographs and
    # still show a blank where the current plate goes, which is the one everybody
    # looks for first.
    print("### No photograph of the current design\n")
    missing_current, local_only = [], []
    for code, name in sorted(names.items(), key=lambda kv: kv[1]):
        rows = [r for r in everything.get(code, []) if r["is_current"] == "1"]
        if not rows or any(shipped(r) for r in rows):
            continue
        # A picture committed to the repo rather than fetched counts as found, even
        # though the Historical screen cannot draw it — that screen only takes
        # remote URLs. Reporting these as "no photograph" would send somebody looking
        # for a picture that is already sitting in dev/research/images.
        if any(r["image_url"] and not r["image_url"].startswith("http") for r in rows):
            local_only.append(f"{name} ({code})")
            continue
        missing_current.append(f"{name} ({code})")
        totals["no_current_photo"] += 1
    print((", ".join(missing_current) if missing_current else "None.") + "\n")
    if local_only:
        print("Held in `dev/research/images` rather than at a URL, so present for the "
              "lookup but not drawable on the Historical screen: "
              + ", ".join(local_only) + ".\n")

    # ---- 3. stale current
    print("## 3. Current designs with an implausible start year\n")
    print(f"Flagged below {STALE_YEAR}; the ones below {VERY_STALE_YEAR} are marked "
          "louder. A genuinely long-lived design is not a bug \u2014 Delaware has "
          "been issuing gold on navy since 1969 \u2014 but most of these are a "
          "specialty plate that got scraped as though it were the general issue.\n")

    # Collapsed on the row's own content. Massachusetts files the same design under
    # eight serial formats and New Hampshire under four; printing each one is eight
    # lines saying one thing.
    rows_out, counts, cleared = {}, defaultdict(int), []
    for code in sorted(everything):
        for year, s, r in stale_current(everything[code]):
            ok = signed_off.get((code, "stale", str(year)))
            if ok:
                entry = (code, year, ok)
                if entry not in cleared:
                    cleared.append(entry)
                continue
            desc = (r["description"][:70] or "\u2014").replace("|", "\\|").replace("\n", " ")
            key = (year, code, s.raw, desc)
            counts[key] += 1
            rows_out.setdefault(key, s)

    if rows_out:
        print("| Jurisdiction | Start | Raw dates | Description |")
        print("|---|---|---|---|")
        for key in sorted(rows_out):
            year, code, raw, desc = key
            level = "**NO YEAR**" if not year else (
                f"**{year}**" if year < VERY_STALE_YEAR else str(year))
            totals["stale"] += 1
            if year and year < VERY_STALE_YEAR:
                totals["very_stale"] += 1
            times = f" \u00d7{counts[key]}" if counts[key] > 1 else ""
            print(f"| {names.get(code, code)} ({code}){times} | {level} | "
                  f"`{raw}` | {desc} |")
    else:
        print("None.")
    print()

    if cleared:
        print("### Reviewed and accepted\n")
        print("Checked against the sources and correct as written \u2014 a design that "
              "really has been in issue that long. Recorded in "
              "`dev/research/plate-audit-accepted.csv` so it stops being reported.\n")
        for code, year, ok in cleared:
            totals["accepted"] += 1
            print(f"- **{names.get(code, code)} ({code}), {year}** "
                  f"\u2014 checked {ok['checked']}. {ok['reason']}")
        print()

    # ---- summary
    print("## Summary\n")
    for label, key in [
        ("Genuinely conflicting timelines", "overlap"),
        ("Clusters that are a design plus its own variants", "variant"),
        ("Spans listed more than once", "repeat"),
        ("Holes in a timeline", "gap"),
        ("Rows that repeat an earlier row exactly", "duplicate"),
        ("Unparseable date strings", "malformed"),
        ("Jurisdictions with no photograph at all", "no_photos"),
        ("Jurisdictions missing from the Historical screen", "missing_history"),
        ("Jurisdictions missing from the lookup index", "missing_lookup"),
        ("Jurisdictions with no current-design photograph", "no_current_photo"),
        (f"Jurisdictions whose newest photograph predates {ARCHIVE_YEAR}", "archive_stops_early"),
        (f"Current designs starting before {STALE_YEAR}", "stale"),
        (f"  \u2026of those, before {VERY_STALE_YEAR}", "very_stale"),
        ("Flags reviewed and accepted as correct", "accepted"),
    ]:
        print(f"- {label}: **{totals[key]}**")

    return 1 if sum(totals.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
