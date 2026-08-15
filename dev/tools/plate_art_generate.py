#!/usr/bin/env python3
"""Draws the plate-face masters that `plate_art_assets.py` turns into tile art.

    python3 ios/tools/plate_art_generate.py plan  --codes WY KS SC
    python3 ios/tools/plate_art_generate.py run   --codes WY KS SC --key-file PATH

The 63 existing masters were produced by an earlier run whose key is long gone, and
for a while this script did not exist at all — which meant a jurisdiction whose plate
had been redesigned was stuck showing the old one, and a jurisdiction with no master
fell back to a hand-drawn vector style forever. This is the missing half.

WHAT A MASTER IS, because it is not what anyone expects. It is the *blank plate face*
and nothing else: no serial, no state name, no slogan, no registration sticker. The
app draws all the lettering itself, in its own typeface, over the top — see
`PlateLettering`. A master with a word in it puts that word permanently behind the
app's own text at a slightly wrong angle, which reads as a printing fault. Every
prompt below therefore spends more effort forbidding text than describing artwork.

NEVER OVERWRITES. An existing master is moved into `art/.superseded/` with a counter
before the new one lands, because these files are the only copy of themselves and a
bad generation is otherwise unrecoverable. Run `plan` first: it prints the exact
prompt and costs nothing.

The key is read from a file so it never appears in a command line, a shell history or
a log, matching `plate_describe.py`.
"""

import argparse
import base64
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESEARCH = os.path.join(REPO, "dev", "research")
PRIMARY_CSV = os.path.join(RESEARCH, "plate-primary.csv")
ART = os.path.join(RESEARCH, "images", "art")
SUPERSEDED = os.path.join(ART, ".superseded")

# 3:2, matching every existing master. `plate_art_assets.py` squashes this to the
# tile's 5:3 rather than cropping, because cropping would take 5% off the top and
# bottom, which is exactly where these designs put their graphics.
SIZE = "1536x1024"
MODEL = "gpt-image-2"

# What makes these look like one set rather than sixty-five separate pictures.
# Read off the masters that already exist: flat color, a little paper grain, the
# graphic held to the edges and the middle left clear enough to carry a serial.
STYLE = """\
Style: a flat, screen-printed illustration in the manner of a real licence plate's
reflective sheeting. Clean vector-like shapes with soft airbrushed gradients and a
faint paper grain. Not photorealistic, not 3D, no drop shadows, no perspective — the
plate is seen square on and fills the whole frame.

Leave the central band across the middle of the plate visually calm and uncluttered:
that is where the registration characters sit, and they are added later.

No mounting holes, bolt slots, screw holes, rivets or fixing points, and no frame
around the plate. None of the existing masters have them, and the two that would sit
at top and bottom centre land exactly where the app draws the jurisdiction's name.

ABSOLUTELY NO TEXT. No letters, no numbers, no words, no state name, no slogan, no
web address, no signature, no watermark. Any lettering visible in the reference
description must be omitted entirely and its space left as plain background. This is
the single most important instruction: a plate face with text in it is unusable.
"""

# One entry per master to draw. Written by hand against the reference photograph in
# dev/research/images/primary, because the CSV's prose is written for search rather than
# for an illustrator — it names things without saying where they sit or how big.
PROMPTS = {
    "WY": """\
A US licence plate face for Wyoming, 2024 design, based on the state flag.

The plate is a deep navy blue field. Around the outside runs a red border about a
twentieth of the plate's width, and inside that a narrower white band separating the
red from the navy — the flag's colors, in the flag's order.

Centred on the navy field, filling most of the middle of the plate, is a large pale
grey silhouette of an American bison facing left, rendered as a soft watermark at low
contrast so it reads as texture rather than as a picture. Sitting on the bison's
flank, a paler grey circular state seal, also low contrast.

Over the left third, a crisp white silhouette of a bucking horse and rider — a cowboy
on a rearing bronco, hat in his raised hand. This one is bright white and fully
opaque, the sharpest thing on the plate.

The upper and lower edges of the navy field are clear.""",

    # THE ONE PROMPT NOT WRITTEN AGAINST A PHOTOGRAPH. There is no
    # dev/research/images/primary/YT.jpg: Commons has no Yukon plate newer than 1979, which
    # is the same hole that left YT falling back to a vector motif while the other 64
    # got masters. This is written from the design description in
    # dev/research/plate-history.csv instead —
    #
    #   "Black on reflective white with border line; screened prospector at left;
    #    screened red 'Yukon' centred on sky blue band at bottom"
    #
    # The souvenir photograph in Resources/CurrentPlates is a novelty reproduction
    # carrying an invented serial, and it is not a source for this: copying its
    # proportions would be tracing a product shot rather than illustrating a design.
    "YT": """\
A Canadian licence plate face for Yukon, the 1990-to-present design.

The field is flat reflective off-white, very slightly cool rather than pure white. A
single thin black line runs around the whole plate a short distance inside its edge,
following the rounded corners.

Over the left third, a screen-printed gold prospector, kneeling on one knee and
tilting a shallow pan toward the viewer. He is drawn as flat two-tone shapes with no
shading at all: burnt orange for his broad-brimmed hat, coat and boots, solid black
for the shadowed side of the figure and for his beard, and a small dull-gold ellipse
of gravel in the pan. Printed directly onto the white with no outline box around him.

Along the bottom edge, a sky-blue horizontal band spanning the full width of the
plate, about a sixth of its height, with one fine white pinstripe running through it
lengthwise. This band is completely empty.

Near the top, two thin horizontal rules in red over orange — one reaching in from the
left edge, one from the right — each stopping well short of the middle and ending in
a small red diamond. The wide gap between the two diamonds is plain white.

The whole centre of the plate, between the prospector and the right edge, is clear
off-white.""",

    "KS": """\
A US licence plate face for Kansas, 2024 "To the Stars" design.

The field is a smooth vertical gradient: a dusty desaturated blue along the top,
through off-white across the middle, into a warm wheat gold along the bottom.

Around the outside runs a dark charcoal-grey border of even thickness, but instead of
following the rectangle it is cut to the silhouette of the state of Kansas — square
along the left, bottom and top, with the characteristic notch and slanted step in the
upper right corner where the Missouri River runs. The border meets the plate's own
rounded corners.

Rising from the bottom left corner, a dark charcoal-grey silhouette of a domed
capitol building, with a small statue of a standing archer drawing a bow on top of
the dome, in the same flat grey.

Two small white rounded squares sit in the top left and top right corners, the blank
boxes a registration sticker is applied to.""",

    # SC IS DELIBERATELY NOT THE CURRENT DESIGN. South Carolina's January 2026
    # "Where the Revolutionary War Was Won" plate is politically contested, and the
    # Game tab is a grid you look at fifty times a trip rather than a reference. So
    # the tile keeps the palmetto-and-crescent base it replaced, while the lookup,
    # the photograph and the history all stay current. The 2026 drawing exists — it
    # is in art/.superseded/SC-2.png — and this prompt describes the older plate on
    # purpose, so that re-running the generator does not undo the decision.
    "SC": """\
A US licence plate face for South Carolina, the design issued before 2026.

The field is a soft off-white, almost cream. A wide navy blue band runs across the
top of the plate, its lower edge fading softly into the cream rather than ending in a
hard line. A second navy band, solid this time, runs across the bottom.

Just below the upper band, slightly left of centre, a small navy crescent moon.

In the right third, standing on the cream field, a single navy palmetto tree in
silhouette — a slim trunk with a fan of fronds at the top.

The middle of the plate is otherwise empty cream.""",

    # ON REPLACES A DRAWING OF THE WRONG PLATE. The first master was the blue 2020
    # "A Place to Grow" design, which Ontario withdrew within months of launching it
    # over night-visibility failures — the white plate with the crown is what is
    # actually on the road, and what `plate-primary.csv` now points at.
    #
    # The crown sits dead centre on the real plate, dividing the serial. It cannot
    # sit there here: the middle is where the app prints the jurisdiction's own
    # characters, so the crown moves to the top edge, the way Quebec's fleur-de-lis
    # and Nova Scotia's schooner already do. This plate is nearly empty by nature,
    # so the crown is doing all the work and its placement is the whole design.
    "ON": """\
A Canadian licence plate face for Ontario, the white design that has been on the
road since 1997.

The field is plain reflective silver-white — a cool, very slightly grey off-white
with the fine sparkle of reflective sheeting. It is completely flat: no gradient,
no scene, no landscape, no watermark, no colored bands, and no border or keyline
of any kind around the edge.

Centred along the top of the plate, a single small royal blue heraldic crown: a
coronet with a jewelled band, three visible arches meeting at the top and a small
cross above them. It is about a seventh of the plate's height, and it is the only
graphic anywhere on the plate.

A small blank white rounded square sits in the top right corner, the box a
registration sticker is applied to. It is empty.

Everything else — the whole middle and the entire lower half — is plain, empty
silver-white.""",
}

# Rough, and printed so a run cannot quietly cost more than expected. gpt-image bills
# per image at this size rather than per token; the number below is the published
# high-quality landscape rate at the time of writing and is only an estimate.
USD_PER_IMAGE = 0.25


def load_key(path):
    if path:
        with open(os.path.expanduser(path)) as f:
            return f.read().strip()
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("No key. Pass --key-file PATH or set OPENAI_API_KEY.")
    return key


def prompt_for(code, names):
    body = PROMPTS.get(code)
    if not body:
        return None
    return f"{body}\n\n{STYLE}"


def plate_names():
    src = open(os.path.join(REPO, "ios", "Plates", "Domain", "Plate.swift")).read()
    import re
    return dict(re.findall(r'\.init\(code:\s*"([A-Z]{2})",\s*name:\s*"([^"]+)"', src))


def supersede(code):
    """Move an existing master aside. These files are the only copy there is."""
    live = os.path.join(ART, f"{code}.png")
    if not os.path.exists(live):
        return None
    os.makedirs(SUPERSEDED, exist_ok=True)
    n = 1
    while os.path.exists(os.path.join(SUPERSEDED, f"{code}-{n}.png")):
        n += 1
    dest = os.path.join(SUPERSEDED, f"{code}-{n}.png")
    os.rename(live, dest)
    return dest


def generate(key, prompt):
    body = json.dumps({"model": MODEL, "prompt": prompt, "size": SIZE, "n": 1}).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations", data=body,
        headers={"Authorization": "Bearer " + key,
                 "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:400]
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(10 * (attempt + 1))
                continue
            sys.exit(f"HTTP {e.code}: {detail}")
        except Exception:
            if attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["plan", "run"])
    ap.add_argument("--codes", nargs="+", required=True)
    ap.add_argument("--key-file", help="file holding the API key, so it never appears "
                                       "in a command line or a log")
    args = ap.parse_args()

    names = plate_names()
    todo = []
    for code in args.codes:
        p = prompt_for(code, names)
        if not p:
            sys.exit(f"{code}: no prompt written. Add one to PROMPTS, against the "
                     f"reference photograph in dev/research/images/primary/{code}.jpg.")
        todo.append((code, p))

    if args.command == "plan":
        for code, p in todo:
            live = os.path.join(ART, f"{code}.png")
            state = "REPLACES existing master" if os.path.exists(live) else "new"
            print(f"===== {names.get(code, code)} ({code}) — {state}\n")
            print(p)
            print()
        print(f"{len(todo)} image(s) at {SIZE}, ~${len(todo) * USD_PER_IMAGE:.2f}")
        return

    key = load_key(args.key_file)
    os.makedirs(ART, exist_ok=True)
    for code, p in todo:
        print(f"{code}: drawing...", file=sys.stderr)
        d = generate(key, p)
        b64 = d["data"][0].get("b64_json")
        if not b64:
            sys.exit(f"{code}: no image in the response")
        moved = supersede(code)
        if moved:
            print(f"  previous master -> {os.path.relpath(moved, REPO)}", file=sys.stderr)
        out = os.path.join(ART, f"{code}.png")
        open(out, "wb").write(base64.b64decode(b64))
        usage = d.get("usage") or {}
        print(f"  wrote {os.path.relpath(out, REPO)}"
              + (f"  ({usage.get('total_tokens')} tokens)" if usage else ""),
              file=sys.stderr)
    print(f"{len(todo)} master(s) drawn. Now run: "
          f"python3 ios/tools/plate_art_assets.py build", file=sys.stderr)


if __name__ == "__main__":
    main()
