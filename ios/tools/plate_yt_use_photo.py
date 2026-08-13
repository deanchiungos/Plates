#!/usr/bin/env python3
"""Swaps Yukon's drawn plate for a supplied photograph.

    python3 plate_yt_use_photo.py ~/Downloads/yukon.jpg

Replaces what `plate_yt_draw.py` produced: copies the file into
`research/images/YT-1990-standard.png`, mirrors it into the app bundle, rewrites the
YT row's licence and credit, and regenerates `PlateHistory.json`. Re-run
`plate_yt_draw.py` to go back to the drawing.

ON THE LICENCE FIELD. It is set to "none stated", which is the same value KS, NE, SC
and WY carry — those are agency artwork served from bare paths with no licence
attached, and the phrase means exactly what it says: nobody stated one. It is not a
claim that the image is free to use, because for a supplied photograph that is not
something this script can know. Every one of the 2,834 rows has a licence and a
credit, and the app tells people so on the Historical plates screen, so leaving
either blank or writing a permission nobody granted would make that line untrue.

The credit records where it came from rather than naming a photographer, so no card
attributes it to anyone.
"""

import csv
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CSV = ROOT / "research/plate-history.csv"
DEST = ROOT / "research/images/YT-1990-standard.png"
BUNDLE = ROOT / "ios/Plates/Resources/CurrentPlates/YT-1990-standard.png"
BUILD = pathlib.Path(__file__).with_name("plate_history_build.py")
OUT = ROOT / "ios/Plates/Resources/PlateHistory.json"


def main(src):
    src = pathlib.Path(src).expanduser()
    if not src.is_file():
        sys.exit(f"no such file: {src}")

    try:
        from PIL import Image
        im = Image.open(src).convert("RGB")
        # The other four are 5:3 and roughly 1200 wide. A souvenir photograph is
        # usually neither, and the card scales to fit, so this only normalises the
        # width to keep the bundle from carrying a 4000px original.
        if im.width > 1400:
            im = im.resize((1400, round(im.height * 1400 / im.width)), Image.LANCZOS)
        im.save(DEST)
        print(f"wrote {DEST.relative_to(ROOT)} ({im.width}x{im.height})")
    except ImportError:
        shutil.copy(src, DEST)
        print(f"copied to {DEST.relative_to(ROOT)} (PIL absent, not resized)")

    shutil.copy(DEST, BUNDLE)

    with open(CSV, newline="") as fh:
        rows = list(csv.DictReader(fh))
    cols = list(rows[0])
    hit = 0
    for r in rows:
        if r["code"] == "YT" and r["is_current"] == "1":
            r["licence"] = "none stated"
            # The builder clips credit to 60 characters — it is sized for a
            # photographer's name, not a sentence — so say it inside the budget
            # rather than have the qualifier truncated off the end.
            r["credit"] = "Supplied photograph; source not recorded"
            r["image_origin"] = "supplied"
            hit += 1
    if hit != 1:
        sys.exit(f"expected one current YT row, found {hit}")

    # `with`, and not the bare open() this had first: the file was still buffered
    # when the subprocess below read it, so the build silently saw a truncated CSV
    # and dropped the last rows in it. That cost Nunavut its current design and
    # nothing failed loudly — the count just came out one short.
    with open(CSV, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    with open(OUT, "w") as fh:
        subprocess.run([sys.executable, str(BUILD), str(CSV)], stdout=fh, check=True)

    # Cheap guard against exactly the class of failure above.
    import json
    data = json.load(open(OUT))
    missing = [k for k, v in data.items() if v and not any(d["current"] for d in v)]
    if missing:
        sys.exit(f"regenerated but these lost their current design: {missing}")
    print(f"regenerated {OUT.relative_to(ROOT)} — "
          f"{sum(len(v) for v in data.values())} designs, all 65 current — rebuild to see it")


if __name__ == "__main__":
    main(sys.argv[1])
