#!/usr/bin/env python3
"""Draws Yukon's current (1990–present) plate as original artwork.

    python3 plate_yt_draw.py ../../research/images/YT-1990-standard.png

Yukon is the last jurisdiction whose current design the app could not show. Commons
has Yukon plates only up to 1979 and en.wikipedia's newest is a 1993 trailer plate,
so unlike the other 60 there is nothing to link and nothing freely licensed to
bundle — the same hole that left `PlateArtwork` falling back to a vector motif for YT
alone.

NOT the same thing as the four images beside it, despite sitting in the same folder.
KS, NE, SC and WY are the jurisdictions' *own* published artwork, saved locally
because each is served from a bare path or a CMS id rather than a stable URL — their
credit fields say so, and their licence is "none stated". Yukon publishes no such
artwork, so this one is drawn: shapes laid down from the row's description in
`research/plate-history.csv` —

    "Black on reflective white with border line; screened prospector at left;
     screened red 'Yukon' centred on sky blue band at bottom"

The prospector is a simplified two-tone panner, not a trace of Yukon's own figure,
and nothing here is measured off a photograph. That makes it the safest image in the
set and also the least faithful — it is an illustration of the design, not the
design. The card credits it as such.
"""

import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 720                      # 5:3, matching the other current-plate images
S = W / 1200.0                        # so the numbers below read as 1200-wide units

WHITE   = (247, 248, 248)
BLACK   = (26, 26, 26)
RED     = (183, 28, 34)
ORANGE  = (223, 122, 32)
SKY     = (77, 177, 226)
SKY_TOP = (150, 208, 236)
GREY    = (172, 176, 180)


def font(name, size):
    for path in (f"/System/Library/Fonts/Supplemental/{name}",
                 f"/Library/Fonts/{name}"):
        try:
            return ImageFont.truetype(path, int(size))
        except OSError:
            continue
    return ImageFont.load_default()


def centred(d, text, fnt, cx, cy, fill):
    l, t, r, b = d.textbbox((0, 0), text, font=fnt)
    d.text((cx - (r - l) / 2 - l, cy - (b - t) / 2 - t), text, font=fnt, fill=fill)


def prospector(d, x, y, w, h):
    """A crouching panner, facing left over his pan.

    Limbs are drawn as stroked lines rather than polygons: at this size a limb is a
    tapering bar, and four polygons per arm was how the first attempt turned into an
    unreadable blob. Orange fill with a black keyline is how the figure reads on the
    road — the plate screens it in two colours, and flat black loses the shape.
    """
    def P(px, py):
        return (x + px * w, y + py * h)

    def limb(a, b, width, colour):
        d.line([P(*a), P(*b)], fill=colour, width=int(width * w), joint="curve")

    def blob(pts, fill):
        d.polygon([P(*p) for p in pts], fill=fill)

    # --- back leg, laid down behind everything (he is kneeling on it)
    limb((0.58, 0.62), (0.86, 0.72), 0.15, BLACK)
    limb((0.58, 0.62), (0.86, 0.72), 0.11, ORANGE)

    # --- torso, hunched forward over the pan
    blob([(0.40, 0.30), (0.74, 0.33), (0.80, 0.64), (0.46, 0.66)], BLACK)
    blob([(0.44, 0.33), (0.71, 0.36), (0.76, 0.61), (0.49, 0.63)], ORANGE)

    # --- forward leg: thigh out to the knee, then the shin dropping to a boot
    limb((0.66, 0.58), (0.92, 0.66), 0.16, BLACK)
    limb((0.66, 0.58), (0.92, 0.66), 0.12, ORANGE)
    limb((0.90, 0.66), (0.88, 0.86), 0.15, BLACK)
    limb((0.90, 0.66), (0.88, 0.86), 0.11, ORANGE)
    blob([(0.74, 0.84), (0.98, 0.84), (0.99, 0.93), (0.72, 0.93)], BLACK)

    # --- arm reaching down and forward to the rim of the pan
    limb((0.48, 0.38), (0.30, 0.56), 0.13, BLACK)
    limb((0.48, 0.38), (0.30, 0.56), 0.09, ORANGE)
    limb((0.30, 0.56), (0.20, 0.70), 0.12, BLACK)
    limb((0.30, 0.56), (0.20, 0.70), 0.08, ORANGE)

    # --- head: beard first so the face sits over it
    blob([(0.44, 0.24), (0.70, 0.24), (0.64, 0.44), (0.48, 0.42)], BLACK)
    d.ellipse([P(0.46, 0.14)[0], P(0.46, 0.14)[1], P(0.70, 0.32)[0], P(0.70, 0.32)[1]],
              fill=ORANGE, outline=BLACK, width=int(0.022 * w))

    # --- hat: a wide flat brim and a low crown, the one silhouette that says
    #     "prospector" at 150 points wide
    d.ellipse([P(0.30, 0.11)[0], P(0.30, 0.11)[1], P(0.86, 0.21)[0], P(0.86, 0.21)[1]],
              fill=BLACK)
    d.ellipse([P(0.33, 0.125)[0], P(0.33, 0.125)[1], P(0.83, 0.195)[0], P(0.83, 0.195)[1]],
              fill=ORANGE)
    blob([(0.46, 0.00), (0.72, 0.00), (0.76, 0.14), (0.42, 0.14)], BLACK)
    blob([(0.49, 0.03), (0.69, 0.03), (0.72, 0.13), (0.45, 0.13)], ORANGE)

    # --- the pan, over the near hand so he is holding it rather than behind it
    d.ellipse([P(0.02, 0.62)[0], P(0.02, 0.62)[1], P(0.60, 0.84)[0], P(0.60, 0.84)[1]],
              fill=BLACK)
    d.ellipse([P(0.06, 0.645)[0], P(0.06, 0.645)[1], P(0.56, 0.815)[0], P(0.56, 0.815)[1]],
              fill=ORANGE)
    # a wash of gravel across the bottom of the pan
    d.chord([P(0.06, 0.645)[0], P(0.06, 0.645)[1], P(0.56, 0.815)[0], P(0.56, 0.815)[1]],
            start=20, end=160, fill=BLACK)


def main(out):
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    # sky-blue band along the bottom, lighter at its top edge the way the real
    # sheeting catches light
    band_top = int(0.735 * H)
    d.rectangle([0, band_top, W, H], fill=SKY)
    d.rectangle([0, band_top, W, band_top + int(14 * S)], fill=SKY_TOP)

    # thin keyline just inside the edge
    d.rounded_rectangle([int(14 * S), int(14 * S), W - int(14 * S), H - int(14 * S)],
                        radius=int(34 * S), outline=BLACK, width=int(5 * S))

    # bolt slots first, so the artwork over them wins any overlap rather than the
    # other way round — the top pair sits above the legend, not through it
    for cx in (W * 0.27, W * 0.73):
        for cy in (H * 0.055, H * 0.945):
            d.rounded_rectangle([cx - 55 * S, cy - 13 * S, cx + 55 * S, cy + 13 * S],
                                radius=int(13 * S), fill=WHITE, outline=GREY,
                                width=int(3 * S))

    # "The Klondike", with the double rules and diamonds either side. The rules stop
    # well short of the text and the diamonds mark the gap, measured off the widest
    # the legend can get rather than guessed.
    klondike = font("Times New Roman Bold.ttf", 92 * S)
    cy = H * 0.165
    centred(d, "The Klondike", klondike, W * 0.5, cy, RED)
    l, t, r, b = d.textbbox((0, 0), "The Klondike", font=klondike)
    half = (r - l) / 2 + int(56 * S)
    for cx in (W * 0.5 - half, W * 0.5 + half):
        rad = int(15 * S)
        d.polygon([(cx, cy - rad), (cx + rad, cy), (cx, cy + rad), (cx - rad, cy)], fill=RED)
    for x0, x1 in ((int(58 * S), W * 0.5 - half - int(26 * S)),
                   (W * 0.5 + half + int(26 * S), W - int(58 * S))):
        for off, col in ((int(-9 * S), RED), (int(9 * S), ORANGE)):
            d.rectangle([x0, cy + off - int(3 * S), x1, cy + off + int(3 * S)], fill=col)

    prospector(d, int(78 * S), int(198 * S), int(238 * S), int(315 * S))

    # the serial, in the flat-terminal grotesque these plates use
    serial = font("Impact.ttf", 215 * S)
    centred(d, "KLD 867", serial, W * 0.615, H * 0.455, BLACK)

    # "Yukon" in red script on the band. Snell's descender runs long, so it is set
    # off-centre vertically to keep the tail clear of the lower bolt slots.
    script = ImageFont.truetype("/System/Library/Fonts/Supplemental/SnellRoundhand.ttc",
                                int(135 * S), index=2)
    centred(d, "Yukon", script, W * 0.5, H * 0.825, RED)

    img.save(out)
    print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main(sys.argv[1])
