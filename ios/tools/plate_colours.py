#!/usr/bin/env python3
"""Measure what colour a plate actually is, from its pixels.

The captions name colours, and naming is where they fall down: New York's 2010
plate is plainly amber, the captioner wrote "yellow" and "gold", and a search for
the orange one returned five Florida plates because Florida grows oranges. No
prompt fixes that reliably — two people looking at the same plate genuinely
disagree about where yellow ends and orange begins.

Pixels do not disagree. This buckets every pixel of the photograph by hue and
returns the fraction of the plate each colour covers, which is also the thing a
person remembers: not "amber", but "mostly orange with dark writing".

Two details that matter:

  soft edges   a hue near a boundary counts, partially, for both neighbours, so
               a plate the eye reads as "orange or maybe yellow" is findable
               under either word rather than filed under exactly one
  coverage     a plate that is 60% orange should beat one with an orange dot,
               so the score is area, not presence

    python3 ios/tools/plate_colours.py           # write research/plate-colours.csv
    python3 ios/tools/plate_colours.py NY        # inspect one jurisdiction
"""
import colorsys
import csv
import os
import sys
from collections import defaultdict

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESEARCH = os.path.join(REPO, "research")
CACHE = os.path.join(RESEARCH, "images", "cache")
SOURCE = os.path.join(RESEARCH, "plate-descriptions.csv")
OUT = os.path.join(RESEARCH, "plate-colours.csv")

# Where each colour word starts and stops, in degrees. Ranges rather than
# centres: the middle of a band is unambiguous and only the edges are shared.
BANDS = [
    ("red", 345, 375),        # wraps
    ("orange", 15, 45),
    ("yellow", 45, 70),
    ("green", 70, 165),
    ("teal", 165, 195),
    ("blue", 195, 255),
    ("purple", 255, 292),
    ("pink", 292, 345),
]
BLEND = 10.0                  # degrees either side of a boundary that count for both


def bucket(r, g, b):
    """[(colour, weight)] for one pixel. Weights sum to 1."""
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    hue = h * 360
    chroma = (max(r, g, b) - min(r, g, b)) / 255.0

    # Neutral test on CHROMA, not saturation, and the threshold rises with
    # lightness. HLS saturation is misleading at the ends of the scale: cream is
    # only a few points of chroma but reports high saturation, which filed New
    # York's cream plate as 72% orange.
    floor = 0.10 + 0.22 * max(0.0, l - 0.62) / 0.38
    if chroma < floor:
        if l > 0.72:
            return [("white", 1.0)]
        if l < 0.25:
            return [("black", 1.0)]
        return [("grey", 1.0)]

    # Brown is not a hue, it is a dark orange, and people do call it brown.
    if 15 <= hue <= 50 and l < 0.38:
        return [("brown", 0.7), ("orange", 0.3)]

    hue360 = hue + 360 if hue < 15 else hue
    for i, (name, lo, hi) in enumerate(BANDS):
        if lo <= hue360 < hi:
            # Neighbours wrap: red spans 345-375, so the band "after" it is
            # orange. Index arithmetic rather than looking up a boundary value,
            # which cannot find a band starting at 375.
            prev = BANDS[(i - 1) % len(BANDS)][0]
            nxt = BANDS[(i + 1) % len(BANDS)][0]
            if hue360 - lo < BLEND and prev != name:
                t = 0.5 - 0.5 * (hue360 - lo) / BLEND
                return [(name, 1 - t), (prev, t)]
            if hi - hue360 < BLEND and nxt != name:
                t = 0.5 - 0.5 * (hi - hue360) / BLEND
                return [(name, 1 - t), (nxt, t)]
            return [(name, 1.0)]
    return [("grey", 1.0)]


def colours_of(path, step=3):
    """colour -> fraction of the plate, biggest first."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # Inset: the photographs carry a little of whatever the plate was screwed to,
    # plus the bolt holes and rim, none of which is the design.
    im = im.crop((int(w * .05), int(h * .07), int(w * .95), int(h * .93)))
    px = im.load()
    W, H = im.size

    tally = defaultdict(float)
    total = 0.0
    for y in range(0, H, step):
        for x in range(0, W, step):
            for name, weight in bucket(*px[x, y]):
                tally[name] += weight
            total += 1
    if not total:
        return {}
    return {k: v / total for k, v in
            sorted(tally.items(), key=lambda kv: -kv[1]) if v / total >= 0.02}


def main():
    rows = list(csv.DictReader(open(SOURCE)))
    if len(sys.argv) > 1:
        want = sys.argv[1].upper()
        for r in rows:
            if r["codes"] == want:
                c = colours_of(os.path.join(CACHE, f"{r['key']}.jpg"))
                pretty = ", ".join(f"{k} {v:.0%}" for k, v in c.items())
                print(f"  {r['rows'][:30]:32} {pretty}")
        return

    with open(OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["key", "codes", "colours"])
        for i, r in enumerate(rows, 1):
            path = os.path.join(CACHE, f"{r['key']}.jpg")
            if not os.path.exists(path):
                continue
            c = colours_of(path)
            w.writerow([r["key"], r["codes"],
                        "|".join(f"{k}:{v:.4f}" for k, v in c.items())])
            if i % 50 == 0:
                print(f"  {i}/{len(rows)}")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
