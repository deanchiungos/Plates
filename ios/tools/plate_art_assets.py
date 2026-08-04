#!/usr/bin/env python3
"""Turn the generated plate art into shippable app assets.

Three jobs, because they are three separate kinds of wrong when they go wrong:

  ink     — what colour is the serial on the real plate? Sampled from the
            photograph in research/images/primary, because the tile's text is
            meant to read as the serial and "navy" is not a hex value.
  assets  — crop each generated PNG to the plate body, squash to the tile's
            5:3, quantise, and write it into the asset catalogue.
  audit   — the generated art is a raster, so the DEBUG ContrastAudit in
            PlateGallery.swift cannot see it. Check ink against the colour
            actually behind the text and report anything below WCAG AA.

`build` runs all three and regenerates PlateArtwork.swift.

    python3 ios/tools/plate_art_assets.py build
"""
import csv
import json
import os
import re
import shutil
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The generated masters, 1536x1024. Kept in the repo rather than regenerated on
# demand: producing them cost 97 image-model calls against a key that no longer
# exists, so these files are the only copy there is.
ART_SRC = os.environ.get("PLATE_ART_SRC",
                         os.path.join(REPO, "research", "images", "art"))
PRIMARY_CSV = os.path.join(REPO, "research", "plate-primary.csv")
PRIMARY_IMG = os.path.join(REPO, "research", "images", "primary")
CATALOG = os.path.join(REPO, "ios", "Plates", "Assets.xcassets", "PlateArt")
SWIFT_OUT = os.path.join(REPO, "ios", "Plates", "Design", "PlateArtwork.swift")
INK_CSV = os.path.join(REPO, "research", "plate-ink.csv")
PLATE_SWIFT = os.path.join(REPO, "ios", "Plates", "Domain", "Plate.swift")
REVIEW_JSON = os.path.join(REPO, "research", "plate-review.json")
FLAGS_MD = os.path.join(REPO, "research", "plate-flags.md")

# The tile is 5:3 (Theme.tileAspect). The art is 3:2. Rather than crop 5% off
# the top and bottom — which is exactly where every generated design puts its
# graphics — the plate body is squashed vertically. At tile size a 10% squash
# is invisible; a clipped border band is not.
#
# 300x180 declared @3x, i.e. 100x60 POINTS. That matters more than it looks:
# an imageset with no scale key is treated as 1x, so the old 375x225 asset was
# 375 points wide and every one of the 65 tiles was resampling it down by ~5x
# on every draw. Sized to just over the widest tile it renders at (the adaptive
# grid's minimum is 78pt), the image lands near 1:1 and the system's own
# scaled-image cache does the work instead.
OUT_W, OUT_H = 300, 180
OUT_SCALE = 3


# ---------------------------------------------------------------- ink sampling

# Colour names as they appear in plate-primary.csv's serial_colour column.
NAMED = {
    "red": (190, 30, 40), "deep red": (150, 25, 35), "tomato red": (210, 60, 45),
    "navy": (20, 35, 80), "deep blue": (20, 40, 140), "blue": (20, 60, 160),
    "black": (20, 20, 20), "dark grey": (70, 75, 85), "grey": (120, 120, 120),
    "teal": (40, 100, 120), "dark green": (15, 60, 45), "green": (25, 120, 70),
    "gold": (200, 165, 70), "yellow": (230, 200, 60), "white": (250, 250, 250),
    "orange": (230, 120, 40), "purple": (90, 50, 130), "brown": (110, 70, 45),
}

# Hand-set, with the reason. Two kinds of failure:
#
#   no serial   — the "photograph" is a blank agency template. There is no
#                 serial in the image to sample, so the prose is all there is.
#   blended     — an embossed serial photographed in flat light picks up so
#                 much of the base colour in its own shadow that median-cut
#                 returns the blend rather than the paint. Checked by eye
#                 against the photo; the direction is always "less muddy".
OVERRIDE = {
    # DELIBERATE DIVERGENCE, not an oversight. Everywhere else in the app South
    # Carolina is the January 2026 "Where the Revolutionary War Was Won" design —
    # the lookup index, the photograph, the history are all current and stay that
    # way. The Game tab keeps the palmetto-and-crescent base it replaced, because
    # the 2026 design is politically contested and a tile you look at fifty times a
    # trip is not the place to plant that.
    #
    # So the art and the reference photograph describe different plates on purpose,
    # and the ink has to be pinned or the next build samples the 2026 plate and
    # paints it onto the palmetto one. Both are black, so nothing looks wrong today
    # — which is exactly why this is written down rather than left to be noticed.
    "SC": (0x0F1414, "pinned — the tile keeps the pre-2026 palmetto base; see the note above"),
    "QC": (0x16277A, "no serial — blank template, colour taken from the wordmark"),
    "TN": (0xFFFFFF, "no serial — blank template; white on navy"),
    "OH": (0xC1272D, "no serial — template shows the wordmark only; serial is red"),
    "FL": (0x1F5C3E, "blended — embossed green read as grey-green"),
    "IL": (0x8C1F2E, "blended — red glyph over the blue gradient read as plum"),
    "IA": (0x1E1E1E, "blended — read as olive-grey"),
    "MS": (0x26365E, "blended — read as slate"),
    "NU": (0x1C1C1C, "blended — read as mid grey"),
    "NY": (0x1F2A45, "blended — read as near-black; the plate is navy"),
    "OR": (0x24304C, "blended — read as charcoal; the plate is navy"),
    # The artwork inverted the plate: real Vermont is white on green, and the
    # generated version kept green only as edge bands over a white field. A
    # white serial on a white field is not a contrast problem to be softened,
    # it is invisible — so the serial inverts with the field it now sits on.
    "VT": (0x0B6647, "inverted — art is green-on-white, so the serial is green"),
}


def named_ref(prose):
    """First colour mentioned wins: "red with a white outline" is a red serial."""
    p = prose.lower()
    hits = sorted((p.index(k), -len(k), v) for k, v in NAMED.items() if k in p)
    return hits[0][2] if hits else None


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def sample_ink(code, prose):
    """The serial's colour, from the middle band of the real photograph.

    Quantise the band, then pick the cluster nearest the colour the caption
    named. Picking by contrast instead does not work: on half these plates the
    serial covers more of the band than the background does, so "the dominant
    colour is the background" is simply false.
    """
    im = Image.open(os.path.join(PRIMARY_IMG, f"{code}.jpg")).convert("RGB")
    w, h = im.size
    band = im.crop((int(w * .12), int(h * .36), int(w * .88), int(h * .70)))
    q = band.quantize(colors=32, method=Image.MEDIANCUT, dither=Image.NONE)
    pal, counts = q.getpalette(), q.getcolors()
    total = sum(c for c, _ in counts)
    cols = [(c / total, tuple(pal[i * 3:i * 3 + 3])) for c, i in counts
            if c / total >= 0.012]
    ref = named_ref(prose)
    if ref is None or not cols:
        return None
    return min(cols, key=lambda fc: dist(fc[1], ref))[1]


def inks():
    """code -> (hex, source).

    Only for jurisdictions that HAVE a generated art master. The ink is sampled from
    the photograph in research/images/primary and then painted over the art, so the
    two have to be describing the same plate. Where there is no art the tile falls
    back to a hand-drawn vector style carrying its own ink, and handing it a sampled
    value is worse than silence: Wyoming's new plate has a white serial, so sampling
    it produced #F0EEE5 with nothing dark behind it — the Vermont failure the
    overrides below already document, arrived at from the other direction.
    """
    out = {}
    for r in csv.DictReader(open(PRIMARY_CSV)):
        code = r["code"]
        if not os.path.exists(os.path.join(ART_SRC, f"{code}.png")):
            print(f"  -- {code}: no art master, leaving the ink to the vector style")
            continue
        if code in OVERRIDE:
            out[code] = OVERRIDE[code]
            continue
        rgb = sample_ink(code, r["serial_colour"])
        if rgb is None:
            print(f"  !! {code}: could not sample ink ({r['serial_colour']!r})")
            continue
        out[code] = ((rgb[0] << 16) | (rgb[1] << 8) | rgb[2],
                     f"sampled — {r['serial_colour']}")
    return out


# ------------------------------------------------------------------- cropping

def margin(im):
    """Thickness of the blank border the generator drew *around* the plate.

    Some outputs are full-bleed and some drew the plate as an object floating
    on a page. The second kind has to be cropped or the tile gets a fake white
    frame inside its own rounded corners.

    A run of near-uniform rows matching the corner colour is a candidate
    margin. The guard is that a real margin exists on all four sides: Colorado
    opens with a uniform dark-green band across the top, but its left and right
    edges are mountains, so its top band is design and is kept.
    """
    px = im.load()
    w, h = im.size
    corner = px[2, 2]

    def run(count, at, limit):
        n = 0
        while n < limit:
            line = [at(n, i) for i in range(0, count, max(1, count // 64))]
            mean = tuple(sum(c[k] for c in line) / len(line) for k in range(3))
            spread = max(dist(c, mean) for c in line)
            if spread > 26 or dist(mean, corner) > 26:
                break
            n += 1
        return n

    cap_v, cap_h = int(h * 0.12), int(w * 0.12)
    top = run(w, lambda n, i: px[i, n], cap_v)
    bot = run(w, lambda n, i: px[i, h - 1 - n], cap_v)
    left = run(h, lambda n, i: px[n, i], cap_h)
    right = run(h, lambda n, i: px[w - 1 - n, i], cap_h)

    sides = [top, bot, left, right]
    if min(sides) < 4 or max(sides) > 4 * max(min(sides), 1):
        return (0, 0, 0, 0)          # not a frame — leave the art alone
    return (left, top, right, bot)


def build_assets(ink_table):
    if os.path.isdir(CATALOG):
        shutil.rmtree(CATALOG)
    os.makedirs(CATALOG)
    # Namespaced, so "CO.png" cannot collide with anything else in the catalogue.
    json.dump({"info": {"author": "xcode", "version": 1},
               "properties": {"provides-namespace": True}},
              open(os.path.join(CATALOG, "Contents.json"), "w"), indent=2)

    rows = []
    for name in sorted(os.listdir(ART_SRC)):
        if not name.endswith(".png"):
            continue
        code = name.split(".")[0]
        im = Image.open(os.path.join(ART_SRC, name)).convert("RGB")
        l, t, r, b = margin(im)
        if l or t:
            im = im.crop((l, t, im.size[0] - r, im.size[1] - b))
        im = im.resize((OUT_W, OUT_H), Image.LANCZOS)
        # Flat vector art palettises with no visible loss and a big size win.
        im = im.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE)

        d = os.path.join(CATALOG, f"{code}.imageset")
        os.makedirs(d)
        im.save(os.path.join(d, f"{code}.png"), optimize=True)
        json.dump({"images": [{"filename": f"{code}.png", "idiom": "universal",
                               "scale": f"{OUT_SCALE}x"}],
                   "info": {"author": "xcode", "version": 1}},
                  open(os.path.join(d, "Contents.json"), "w"), indent=2)

        field = field_colour(im.convert("RGB"))
        rows.append((code, ink_table.get(code, (0x000000, "?")), field,
                     (l, t, r, b), os.path.getsize(os.path.join(d, f"{code}.png"))))
    return rows


def field_colour(im):
    """The colour actually behind the tile's text.

    Not a mean — a mean of navy and white is grey, and grey is legible against
    nothing. Take the quantised colours under the text box and return the one
    that contrasts *least* with everything, i.e. the worst case the text has to
    survive.
    """
    w, h = im.size
    box = im.crop((int(w * .22), int(h * .28), int(w * .78), int(h * .74)))
    q = box.quantize(colors=8, method=Image.MEDIANCUT, dither=Image.NONE)
    pal, counts = q.getpalette(), q.getcolors()
    total = sum(c for c, _ in counts)
    return [(c / total, tuple(pal[i * 3:i * 3 + 3])) for c, i in
            sorted(counts, reverse=True) if c / total >= 0.04]


# -------------------------------------------------------------------- contrast

def luminance(rgb):
    def ch(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def ratio(a, b):
    l1, l2 = luminance(a), luminance(b)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def unhex(v):
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


THRESHOLD = 4.5


# ------------------------------------------------------------ review.json intake
#
# ios/tools/plate_review_server.py is where a human actually looks at these 63
# tiles and decides three things: is the tile label wrong, does this design
# need more work, is the text hard to read. This is where those decisions get
# folded back in — into Plate.swift, into the generated Swift, into a report.

def load_review():
    if not os.path.exists(REVIEW_JSON):
        return {}
    return json.load(open(REVIEW_JSON))


def plate_names():
    """code -> full name, read straight from Plate.swift."""
    src = open(PLATE_SWIFT).read()
    return {m.group(1): m.group(2) for m in
            re.finditer(r'code: "(\w+)".*?name: "([^"]*)"', src)}


def apply_short_overrides(review):
    """Rewrite the `short:` value on each affected .init(...) line in Plate.swift.

    One targeted substitution per code rather than regenerating the file: the
    surrounding column spacing is hand-tuned and unrelated codes must not move.
    """
    edits = {code: v["short"] for code, v in review.items() if v.get("short")}
    if not edits:
        return []
    src = open(PLATE_SWIFT).read()
    changed = []
    for code, new_short in edits.items():
        pattern = re.compile(rf'(code: "{code}".*?short: ")([^"]*)(")')
        m = pattern.search(src)
        if not m:
            print(f"  !! {code}: no matching line in Plate.swift, skipped")
            continue
        if m.group(2) != new_short:
            changed.append((code, m.group(2), new_short))
        src = pattern.sub(lambda mm: mm.group(1) + new_short + mm.group(3), src, count=1)
    if changed:
        open(PLATE_SWIFT, "w").write(src)
    return changed


def write_flags_report(review, plate_names):
    flagged = {code: v for code, v in review.items() if v.get("flagged")}
    lines = ["# Plate art — flagged for rework", "",
             "Generated by `plate_art_assets.py build` from "
             "`research/plate-review.json`. Re-run after clearing a flag in "
             "the review tool to drop it from this list.", ""]
    if not flagged:
        lines.append("Nothing flagged.")
    for code in sorted(flagged):
        v = flagged[code]
        name = plate_names.get(code, code)
        lines.append(f"- **{code}** — {name}")
        if v.get("note"):
            lines.append(f"  {v['note']}")
    open(FLAGS_MD, "w").write("\n".join(lines) + "\n")
    return len(flagged)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    if cmd != "build":
        print(__doc__)
        return

    print("sampling ink from the reference photographs...")
    ink_table = inks()
    with open(INK_CSV, "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["code", "ink", "source"])
        for code in sorted(ink_table):
            hexv, src = ink_table[code]
            wr.writerow([code, f"#{hexv:06X}", src])
    print(f"  wrote {INK_CSV} ({len(ink_table)} entries, "
          f"{len(OVERRIDE)} hand-set)")

    print("building assets...")
    rows = build_assets(ink_table)
    cropped = sum(1 for r in rows if any(r[3]))
    total_kb = sum(r[4] for r in rows) / 1024
    print(f"  {len(rows)} imagesets, {cropped} needed a frame crop, "
          f"{total_kb:.0f} KB total")

    print("contrast audit (ink vs. the colour behind the text):")
    halo = {}
    for code, (hexv, _), field, _, _ in rows:
        ink = unhex(hexv)
        worst = min((ratio(ink, c), frac, c) for frac, c in field)
        if worst[0] < THRESHOLD:
            halo[code] = worst
    for code, (r, frac, c) in sorted(halo.items(), key=lambda x: x[1][0]):
        print(f"  {code}  {r:4.2f}:1  against #{c[0]:02X}{c[1]:02X}{c[2]:02X} "
              f"({frac * 100:.0f}% of the text box) — halo")
    print(f"  {len(rows) - len(halo)}/{len(rows)} pass {THRESHOLD}:1 unaided")

    review = load_review()
    if review:
        print(f"applying {REVIEW_JSON}...")
        changed = apply_short_overrides(review)
        for code, old, new in changed:
            print(f'  {code}: "{old}" -> "{new}"')
        if changed:
            print(f"  wrote {PLATE_SWIFT}")
        n_flagged = write_flags_report(review, plate_names())
        dimmed = sum(1 for v in review.values() if v.get("scrim", 0) > 0)
        moved = sum(1 for v in review.values()
                    if v.get("offsetX", 0) or v.get("offsetY", 0))
        print(f"  {n_flagged} flagged -> {FLAGS_MD}, {dimmed} with a scrim set, "
              f"{moved} repositioned")

    emit_swift(rows, halo, review)
    print(f"wrote {SWIFT_OUT}")


def emit_swift(rows, halo, review):
    lines = [
        "import SwiftUI",
        "",
        "// GENERATED by ios/tools/plate_art_assets.py — do not edit by hand.",
        "//",
        "// Each entry is a jurisdiction whose tile is drawn from photo-grounded",
        "// artwork in Assets.xcassets/PlateArt rather than from PlateStyle's vector",
        "// motifs. `ink` is the serial colour sampled off the real plate, because",
        "// the code and state name on a tile stand in for the serial and should be",
        "// painted the same colour the plate paints it. `field` is the colour the",
        "// artwork actually puts behind that text — the raster bypasses the vector",
        "// catalogue entirely, so it is the only thing left to audit against.",
        "//",
        "// `halo` marks the handful where the two do not clear WCAG AA. Mostly",
        "// these are honest: New Mexico really is yellow on turquoise and Ontario",
        "// really is white on blue. Rather than repaint a plate into a colour it",
        "// does not have, the tile draws those with a soft opposite-luminance ring",
        "// behind the text — which is roughly what the emboss does in daylight.",
        "//",
        "// `scrim` and `offset` are set by hand in the review tool",
        "// (ios/tools/plate_review_server.py), not measured — a human judging the",
        "// art busy enough to dim, or the text sitting somewhere wrong, not a formula.",
        "// `offset` is a fraction of the tile's own width/height, not points, so it",
        "// holds at every size the tile renders at — the Game grid, the trail map pin.",
        "//",
        "// Wyoming and Yukon are absent: no free photograph of either exists, so",
        "// they keep PlateStyle's vector art and PlateStyle's ink.",
        "enum PlateArtwork {",
        "    struct Entry {",
        "        let ink: UInt32",
        "        let field: UInt32",
        "        let halo: Bool",
        "        let scrim: Double",
        "        let offsetX: Double",
        "        let offsetY: Double",
        "        /// Opposite luminance to the ink. Precomputed — working it out at",
        "        /// runtime meant three pow() calls per tile per frame.",
        "        let embossHex: UInt32",
        "        /// Interned once here rather than interpolated per body evaluation.",
        "        let asset: String",
        "    }",
        "",
        "    static let table: [String: Entry] = [",
    ]
    for code, (hexv, src), field, _, _ in sorted(rows):
        f = field[0][1]
        fh = (f[0] << 16) | (f[1] << 8) | f[2]
        h = "true " if code in halo else "false"
        ov = review.get(code, {})
        s = ov.get("scrim", 0.0)
        ox, oy = ov.get("offsetX", 0.0), ov.get("offsetY", 0.0)
        emb = 0x000000 if luminance(unhex(hexv)) > 0.4 else 0xFFFFFF
        lines.append(f'        "{code}": Entry(ink: 0x{hexv:06X}, '
                     f"field: 0x{fh:06X}, halo: {h}, scrim: {s}, "
                     f"offsetX: {ox}, offsetY: {oy}, embossHex: 0x{emb:06X}, "
                     f'asset: "PlateArt/{code}"),   // {src}')
    lines += [
        "    ]",
        "",
        "    static func has(_ code: String) -> Bool { table[code] != nil }",
        "",
        "    /// The asset name. Namespaced by the PlateArt folder in the catalogue.",
        "    static func imageName(_ code: String) -> String {",
        "        table[code]?.asset ?? \"PlateArt/\\(code)\"",
        "    }",
        "",
        "    /// The serial colour, when this plate has artwork.",
        "    static func ink(_ code: String) -> Color? {",
        "        table[code].map { Color(hex: $0.ink) }",
        "    }",
        "",
        "    /// The ring drawn behind the text, on the four plates whose own two",
        "    /// colours do not clear WCAG AA.",
        "    ///",
        "    /// Every plate used to get a faint one too, on the theory that two lines",
        "    /// of type could not fit inside the artwork's clear band. The review pass",
        "    /// then moved the block by hand on 60 of the 63, which is the real fix —",
        "    /// and a blurred shadow is an offscreen render pass per tile per frame,",
        "    /// which at 65 tiles is what made the grid stutter. So it is now only",
        "    /// where it is doing load-bearing work.",
        "    static func halo(_ code: String) -> Color? {",
        "        guard let e = table[code], e.halo else { return nil }",
        "        return Color(hex: e.embossHex)",
        "    }",
        "",
        "    /// The scrim's colour — the same opposite-luminance value the halo uses,",
        "    /// so turning the dim up deepens one effect rather than adding a second.",
        "    static func scrimColor(_ code: String) -> Color? {",
        "        guard let e = table[code], e.scrim > 0 else { return nil }",
        "        return Color(hex: e.embossHex)",
        "    }",
        "",
        "    /// How much to dim the art behind the text, 0...0.8. Set per-plate in",
        "    /// the review tool for designs busy enough that the emboss alone isn't",
        "    /// enough — South Dakota's Rushmore photo, Nunavut's aurora.",
        "    static func scrim(_ code: String) -> Double {",
        "        table[code]?.scrim ?? 0",
        "    }",
        "",
        "    /// Where to place the code/name block, as a fraction of the tile's own",
        "    /// width (x) and height (y) from centre — (0, 0) is dead centre, matching",
        "    /// what every plate does until the review tool moves it.",
        "    static func offset(_ code: String) -> (x: Double, y: Double) {",
        "        guard let e = table[code] else { return (0, 0) }",
        "        return (e.offsetX, e.offsetY)",
        "    }",
        "}",
        "",
    ]
    open(SWIFT_OUT, "w").write("\n".join(lines))


if __name__ == "__main__":
    main()
