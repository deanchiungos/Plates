#!/usr/bin/env python3
"""Whittles Jon Keegan's 8,331-row plate catalogue down to the designs a spotter
would actually recognise from a moving car.

    curl -sSLO https://raw.githubusercontent.com/jonkeegan/us-license-plates/main/us-license-plates.csv
    python3 plate_designs.py us-license-plates.csv > ../../research/plate-designs.csv

WHAT THE SOURCE ACTUALLY IS, because it changes what can be built from it: a
snapshot of every plate you could *order* from a state agency in July 2023. That is
overwhelmingly specialty stock — 2,163 military, 1,342 charity and club, 964
university, 141 sports team. It is not a design history, and it is not even a
complete set of standard plates: fourteen agencies never list theirs, because the
standard plate is not something you order. Maryland publishes 989 plates and not one
of them is the plate on most Maryland cars.

So this script produces three kinds of row and no others:

  base     the current standard design — what most cars in that state wear
  variant  another standard design in concurrent issue, different enough to be a
           separate sighting (California alone has six, and they are all legal)
  retro    an older design still orderable today: reissues and long-running
           commemoratives

Every pattern is asserted against the source. A title that stops matching after an
upstream update fails the run rather than silently dropping a state.
"""

import csv
import re
import sys

# (code, kind, human name, pattern matched against plate_title)
#
# Patterns are deliberately anchored. Loose ones matched things like "Ohio State
# University Alumni" for Georgia and "Chesapeake Yacht Club" for Maryland.
CURATION = [
    # --- current standard designs -------------------------------------------
    ("AL", "base", "Sweet Home Alabama", r"^Standard Passenger$"),
    ("AK", "base", "Gold Rush", r"^Standard Gold$"),
    ("AZ", "base", "Cactus", r"^Standard$"),
    ("CA", "base", "Sun", r"^Standard - Sun$"),
    ("CO", "base", "Green Mountains", r"^Passenger License Plate$"),
    ("FL", "base", "Sunshine State", r"^Standard\s+- Sunshine$"),
    ("GA", "base", "Peach", r"^Standard$"),
    ("HI", "base", "Rainbow", r"^Standard$"),
    ("ID", "base", "Famous Potatoes", r"^FAMOUS POTATOES$"),
    ("IL", "base", "Lincoln", r"^Passenger$"),
    ("IN", "base", "Crossroads", r"^Standard Passenger$"),
    ("IA", "base", "County", r"^Regular County Design$"),
    ("KS", "base", "Sunflower", r"^Standard current issue$"),
    ("KY", "base", "Unbridled Spirit", r"^Standard Vehicle$"),
    ("ME", "base", "Chickadee", r"^Passenger$"),
    ("MA", "base", "Spirit of America", r"^PASSENGER NORMAL"),
    ("MI", "base", "Pure Michigan", r"^Pure Michigan$"),
    ("MS", "base", "Magnolia", r"^Passenger$"),
    ("MO", "base", "Bluebird", r"^Standard$"),
    ("NH", "base", "Old Man of the Mountain", r"^Passenger$"),
    ("NJ", "base", "Garden State", r"^Standard$"),
    ("NM", "base", "Turquoise Centennial", r"^Standard Centennial License Plate$"),
    ("NY", "base", "Excelsior", r"^Excelsior$"),
    ("ND", "base", "Bison", r"^Standard$"),
    ("NV", "base", "Home Means Nevada", r"^Home Means Nevada$"),
    ("OH", "base", "Sunrise in Ohio", r"^ohio$"),
    ("OR", "base", "Douglas Fir", r"^Standard Tree$"),
    # Titled "Sample" upstream: the standard design, shot as a sample plate.
    ("PA", "base", "Keystone", r"Standard Issue Registration Plate$"),
    ("RI", "base", "Wave", r"^Passenger Plates$"),
    ("SC", "base", "In God We Trust", r"^In God We Trust$"),
    ("SD", "base", "Mount Rushmore", r"^Standard South Dakota"),
    # Upstream title is the doubled "Automobile Automobile & Motorcycle".
    ("TN", "base", "Tri-Star", r"^Automobile\s+Automobile & Motorcycle$"),
    ("UT", "base", "Arches", r"^Utah$"),
    ("VA", "base", "Standard Issue", r"^Passenger Standard Issue$"),
    ("WV", "base", "Mountain State", r"^Standard$"),
    ("WI", "base", "America's Dairyland", r"^Regular automobile$"),
    ("WY", "base", "Bucking Horse", r"^Standard$"),

    # --- other standard designs in concurrent issue --------------------------
    # California is the whole argument for this category: five earlier standards
    # are still on the road alongside the current one, and they look nothing alike.
    ("CA", "variant", "Script", r"^Standard - Script$"),
    ("CA", "variant", "Block", r"^Standard - Block$"),
    ("CA", "variant", "Blue and Gold", r"^Standard - Bue \+ Gold 1$"),
    ("CA", "variant", "Blue and Gold, later", r"^Standard - Bue \+ Gold 2$"),
    ("CA", "variant", "Black and Gold", r"^Standard - Black \+ Gold$"),
    ("FL", "variant", "County name", r"^Standard\s+- County$"),
    ("FL", "variant", "In God We Trust", r"^Standard\s+- In God We Trust$"),
    ("GA", "variant", "Standard alternate", r"^Standard Alternate$"),
    ("KY", "variant", "In God We Trust", r"^Standard Vehicle - In God We Trust$"),
    ("KY", "variant", "Team Kentucky", r"^Team Kentucky Standard Vehicle$"),
    ("NM", "variant", "Red and Yellow", r"^Standard Red and Yellow License Plate$"),
    ("TN", "variant", "In God We Trust", r"^Automobile - In God We Trust"),

    # --- older designs still orderable ---------------------------------------
    ("CA", "retro", "Legacy black and gold", r"^LEGACY$"),
    ("CO", "retro", "Historical black", r"^Historical - Black$"),
    ("CO", "retro", "Historical blue", r"^Historical - Blue$"),
    ("CO", "retro", "Historical green", r"^Historical - Green$"),
    ("CO", "retro", "Historical red", r"^Historical - Red$"),
    ("AL", "retro", "Bicentennial", r"^Alabama Bicentennial$"),
    ("AZ", "retro", "Centennial", r"^Arizona Centennial$"),
    ("ID", "retro", "Centennial", r"^CENTENNIAL$"),
    ("MT", "retro", "Centennial", r"^Montana Centennial$"),
    ("UT", "retro", "Centennial", r"^Utah Centennial$"),
    ("OK", "retro", "Statehood Centennial", r"^Oklahoma Statehood Centennial$"),
    ("DE", "retro", "Caesar Rodney Centennial", r"^Caesar Rodney Centennial$"),
]

# Agencies that publish only orderable specialty plates, so their standard design is
# absent from the source entirely. Listed rather than quietly skipped — a game that
# is missing Texas is missing Texas, and it should be obvious from the output.
NO_BASE_IN_SOURCE = {
    "AR": "The Natural State",
    "CT": "Charter Oak",
    "DC": "Taxation Without Representation",
    "DE": "Delaware, The First State",
    "LA": "Louisiana Pelican",
    # All 989 Maryland rows are organisational plates.
    "MD": "Maryland Proud",
    "MT": "Big Sky",
    "MN": "10,000 Lakes",
    "NC": "First in Flight",
    # Nebraska's 2023 standard is absent; the only "Sandhill Crane" row in the source
    # is a wildlife-conservation specialty plate, which is a different design.
    "NE": "Nebraska (2023)",
    "OK": "Explore Oklahoma",
    "TX": "Texas Classic",
    "VT": "Green Mountains",
    "WA": "Mount Rainier",
}


REPO = "https://raw.githubusercontent.com/jonkeegan/us-license-plates/main/plates"


def repo_img(code, filename):
    """The cropped copy in Keegan's repo.

    Worth carrying alongside `source_img` because 1,044 source rows have no image URL
    at all: those agencies published their plates only inside a PDF, and the cropped
    page is the sole place the design can be seen. `MISSING.png` is his marker for a
    plate he could not find an image of.
    """
    if not filename or filename == "MISSING.png":
        return ""
    return f"{REPO}/{code}/{filename}"


def main(path):
    rows = list(csv.DictReader(open(path)))
    by_state = {}
    for r in rows:
        by_state.setdefault(r["state"], []).append(r)

    out = csv.writer(sys.stdout)
    out.writerow(["code", "kind", "design", "source_title",
                  "source_img", "repo_img", "source_page"])

    unmatched = []
    for code, kind, name, pattern in CURATION:
        hits = [r for r in by_state.get(code, [])
                if re.search(pattern, r["plate_title"], re.I)]
        if not hits:
            unmatched.append(f"{code} {kind} {name!r} /{pattern}/")
            continue
        if len(hits) > 1:
            unmatched.append(f"{code} {kind} {name!r} matched {len(hits)}: "
                             + ", ".join(h["plate_title"] for h in hits[:4]))
            continue
        r = hits[0]
        title = " ".join(r["plate_title"].split())
        out.writerow([code, kind, name, title, r["source_img"],
                      repo_img(code, r["plate_img"]), r["source"]])

    for code, name in sorted(NO_BASE_IN_SOURCE.items()):
        out.writerow([code, "base", name, "", "", "",
                      "NOT IN SOURCE — agency lists specialty plates only"])

    if unmatched:
        print("\n".join(["", "PATTERNS THAT DID NOT RESOLVE:"] + unmatched), file=sys.stderr)
        sys.exit(1)

    kinds = {}
    for code, kind, *_ in CURATION:
        kinds[kind] = kinds.get(kind, 0) + 1
    print(f"{len(rows)} source rows -> {len(CURATION) + len(NO_BASE_IN_SOURCE)} designs "
          f"({kinds}, plus {len(NO_BASE_IN_SOURCE)} bases missing from source)",
          file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "us-license-plates.csv")
