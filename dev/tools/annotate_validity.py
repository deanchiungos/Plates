#!/usr/bin/env python3
"""Adds a street-legal column to the scraped plate history.

    python3 annotate_validity.py ../research/plate-history.csv \\
                                 ../research/plate-validity.csv \\
                                 ../research/plate-validity-cutoffs.csv \\
        > annotated.csv

"When was it issued" and "could I see it today" are different questions, and for a
spotting game only the second one matters. A 1911 Alabama plate is a museum piece. A
1980 California plate is on the freeway right now, because California never made anyone
give them back. Sorted by year the two look identical.

Three sources of truth, applied in this order:

1. `is_current` from the per-jurisdiction table — the design being issued today.
2. A **blanket rule** in the article prose, e.g. California's "All plates from 1963
   until present are still valid". These cover far more rows than anything else and are
   listed below with the sentence that justifies them, because each is a human reading
   of one sentence and should be re-readable.
3. The per-design **Status** column from "Plate types no longer issued but still valid",
   joined on jurisdiction and start year.

Anything none of the three reaches is `unknown` — *not* `expired`. Absence of a validity
statement is absence of evidence. Only an explicit "no longer valid" earns `expired`.
"""

import csv
import re
import sys

# Cutoffs live in dev/research/plate-validity-cutoffs.csv, hand-curated, with the evidence
# for each in its own column. Two bases, and the distinction matters:
#
#   stated    an explicit sentence in the article — "All plates from 1963 until present
#             are still valid". Seven of these.
#   inferred  the earliest design the "still valid" table lists for that jurisdiction,
#             filled forward. Twenty-two of these. This assumes the still-valid range is
#             contiguous from that year, which is how states generally work but is an
#             assumption, not a quotation. Rows resolved this way are marked `likely`,
#             never `valid`.
YEAR = re.compile(r"\b(1[89]\d{2}|20[0-4]\d)\b")


def start_year(text):
    m = YEAR.search(text or "")
    return int(m.group(1)) if m else None


def main(history_path, validity_path, cutoff_path):
    validity = {}
    for r in csv.DictReader(open(validity_path)):
        y = start_year(r["dates_issued"])
        if r["code"] and y:
            validity.setdefault((r["code"], y), r)

    cutoffs = {}
    for r in csv.DictReader(open(cutoff_path)):
        cutoffs[r["code"]] = (int(r["cutoff_year"]), r["basis"], r["evidence"])

    rows = list(csv.DictReader(open(history_path)))
    fields = list(rows[0].keys()) + ["street_legal", "validity_note"]
    out = csv.DictWriter(sys.stdout, fieldnames=fields)
    out.writeheader()

    tally = {}
    for r in rows:
        y = start_year(r["dates_issued"] or r["first_issued"])
        legal, note = "unknown", ""

        if r["is_current"] == "1":
            legal, note = "current", "currently issued"
        elif y and (r["code"], y) in validity:
            # This exact design is named in the still-valid table.
            hit = validity[(r["code"], y)]
            legal, note = hit["status_class"], hit["status"]
        elif r["code"] in cutoffs and y and y >= cutoffs[r["code"]][0]:
            cut, basis, evidence = cutoffs[r["code"]]
            legal = "valid" if basis == "stated" else "likely"
            note = f"{basis} cutoff {cut}: {evidence}"

        r["street_legal"], r["validity_note"] = legal, note
        tally[legal] = tally.get(legal, 0) + 1
        out.writerow(r)

    print(f"{len(rows)} rows: " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())),
          file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
