#!/usr/bin/env python3
"""Build the offline "what plate was that?" index.

Takes the 268 captioned street-legal designs in research/plate-descriptions.csv
— every one of which has a real photograph and a written description of what it
looks like — and turns them into two things the app ships:

  Resources/PlateShots/<key>.jpg   the photo, sized for a phone
  Resources/PlateLookup.json       a TF-IDF vector per design, plus the IDF
                                   table and a synonym map

Matching is a vector space model: each design is a sparse, L2-normalised vector
over weighted terms, the query becomes a vector the same way, and the score is
the cosine between them. Classic IR rather than a neural embedding, and that is
a deliberate choice — it runs offline in microseconds, it is deterministic, and
when it returns something odd you can see exactly which term did it. A sentence
embedding would be better at paraphrase and worse at "green", "lighthouse",
"1970s", which is most of what anyone actually types about a licence plate.

The tokeniser here and the one in PlateLookup.swift must stay identical or the
query lands in a different space from the documents. It is deliberately trivial
for exactly that reason.

    python3 ios/tools/plate_lookup_build.py
"""
import csv
import json
import math
import os
import re
import shutil
import urllib.parse
from collections import Counter, defaultdict

from PIL import Image, ImageOps

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The retrieval-oriented re-caption if it exists, the original prose pass if it
# does not. Same keys either way, so the two are drop-in interchangeable and a
# half-finished v2 run still builds — it just falls back for the rest.
DESCRIPTIONS_V2 = os.path.join(REPO, "research", "plate-descriptions-v2.csv")
DESCRIPTIONS_V1 = os.path.join(REPO, "research", "plate-descriptions.csv")
PRIMARY = os.path.join(REPO, "research", "plate-primary.csv")
# Who took each photograph and under what licence. Most of these are Wikimedia
# Commons uploads under CC BY or CC BY-SA, which require the photographer to be
# named wherever the picture is shown. Shipping the credit in the index is the
# only way the app can honour that offline.
HISTORY = os.path.join(REPO, "research", "plate-history.csv")
# The gaps the history sheet does not cover, looked up from the wikis themselves by
# plate_credits.py. Photos keep arriving through passes that carry no licence with
# them, so this is a file that gets regenerated rather than a list kept by hand.
CREDITS = os.path.join(REPO, "research", "plate-image-credits.csv")
CACHE = os.path.join(REPO, "research", "images", "cache")
PLATE_SWIFT = os.path.join(REPO, "ios", "Plates", "Domain", "Plate.swift")
RESOURCES = os.path.join(REPO, "ios", "Plates", "Resources")
SHOTS = os.path.join(RESOURCES, "PlateShots")
INDEX_OUT = os.path.join(RESOURCES, "PlateLookup.json")

SHOT_WIDTH = 480
SHOT_QUALITY = 78
TOP_TERMS = 48           # per design; the tail contributes almost nothing to cosine

# Words that carry no signal about what a plate looks like. Kept short on
# purpose — "blue" and "white" are the whole point, so only true stopwords go.
STOP = set("""
a an the and or but of to in on at for with from by is are was were be been being
it its this that these those as into over under above below through across
which who whom whose what when where why how than then there here
plate plates licence license number numbers registration vehicle
has have had having very quite rather somewhat also both each either neither
one two three four five six seven eight nine ten
""".split())

# Query-time expansion. A person describing a plate says "mountains" where the
# caption says "ridgeline", or "beach" where it says "shoreline". Expanding the
# query rather than the index keeps the document vectors honest — a design does
# not become more about mountains because someone might call it that.
SYNONYMS = {
    "mountain": ["ridgeline", "ridge", "peak", "range", "summit", "alpine"],
    "hill": ["ridgeline", "ridge", "rolling"],
    "beach": ["shore", "shoreline", "coast", "coastal", "sand", "dune", "surf"],
    "ocean": ["sea", "water", "wave", "coastal", "shore"],
    "lake": ["water", "shore", "loon"],
    "river": ["water", "riverbank"],
    "tree": ["pine", "palm", "palmetto", "forest", "evergreen", "conifer", "spruce"],
    "forest": ["pine", "tree", "evergreen", "woodland"],
    "sun": ["sunset", "sunrise", "sunburst", "rays", "dawn", "dusk"],
    "sunset": ["sunrise", "sun", "dusk", "glow"],
    "sky": ["cloud", "blue", "horizon"],
    "cloud": ["sky", "cumulus"],
    "bird": ["eagle", "gull", "pelican", "cardinal", "loon", "goose", "falcon"],
    "flower": ["rose", "blossom", "magnolia", "bloom", "peach", "orange"],
    "farm": ["barn", "field", "wheat", "corn", "silo", "agricultural", "harvest"],
    "wheat": ["grain", "field", "harvest", "prairie"],
    "desert": ["cactus", "saguaro", "sand", "mesa", "arid"],
    "cactus": ["saguaro", "desert"],
    "bridge": ["span", "suspension", "arch"],
    "city": ["skyline", "skyscraper", "downtown", "urban"],
    "star": ["stars", "starburst"],
    "moon": ["crescent"],
    "flag": ["banner", "standard"],
    "crown": ["royal", "monarch"],
    "map": ["outline", "silhouette", "shape"],
    "outline": ["silhouette", "map", "shape"],
    "boat": ["ship", "sail", "schooner", "sailboat"],
    "lighthouse": ["beacon"],
    "horse": ["equine", "bronco"],
    "bison": ["buffalo"],
    "moose": ["elk"],
    "bear": ["grizzly", "polar"],
    "fish": ["trout", "bass", "salmon"],
    "shell": ["seashell", "scallop"],
    "peach": ["fruit"],
    "potato": ["spud"],
    "lobster": ["crustacean"],
    "arch": ["arches", "sandstone"],
    "aurora": ["northern", "lights"],
    "snow": ["snowy", "snowcapped", "winter"],
    "gradient": ["fade", "fading", "graduated", "ombre"],
    "rainbow": ["spectrum", "multicolour", "multicolor"],
    # Colour maps to colour ONLY, never to an object or a scene.
    # Colour words are a continuum, and two people looking at the same plate
    # will not pick the same one. New York's 2010 plate is amber; the captioner
    # called it "yellow" and "gold", so a search for the "orange and black" one
    # returned five Florida plates — because Florida grows oranges. Bridging
    # neighbouring colours is not a nicety, it is the difference between finding
    # the plate and not.
    "orange": ["amber", "gold", "tangerine", "rust", "copper"],
    "amber": ["orange", "gold", "yellow"],
    "gold": ["yellow", "amber", "orange", "tan"],
    "yellow": ["gold", "amber", "cream"],
    "brown": ["tan", "rust", "copper", "bronze"],
    "red": ["crimson", "scarlet", "maroon", "burgundy"],
    "pink": ["rose", "magenta"],
    "blue": ["navy", "azure", "cobalt"],
    "black": ["charcoal", "dark"],
    "white": ["ivory", "cream", "off"],
    "green": ["emerald", "olive", "lime"],
    "grey": ["gray", "silver", "slate", "charcoal"],
    "gray": ["grey", "silver", "slate", "charcoal"],
    "silver": ["grey", "gray", "chrome", "metallic"],
    "navy": ["blue", "dark"],
    "maroon": ["burgundy", "red", "wine"],
    "tan": ["beige", "cream", "buff", "brown"],
    "cream": ["ivory", "off", "beige", "tan"],
    "turquoise": ["teal", "cyan", "aqua"],
    "teal": ["turquoise", "cyan", "green", "blue"],
    "purple": ["violet", "lavender", "magenta"],
    "embossed": ["raised", "stamped"],
    "flat": ["screened", "printed", "digital"],
    "border": ["frame", "edge", "band", "rim"],
    "slogan": ["legend", "motto", "wordmark"],
}


# A colour word someone types, mapped onto the buckets the pixels were measured
# into. Weights below 1 where the word straddles two — "gold" is genuinely
# between orange and yellow, which is the whole reason this exists.
COLOUR_QUERY = {
    "orange": [("orange", 1.0)],
    "amber": [("orange", 0.8), ("yellow", 0.5)],
    "gold": [("orange", 0.6), ("yellow", 0.8)],
    "golden": [("orange", 0.6), ("yellow", 0.8)],
    "yellow": [("yellow", 1.0)],
    "red": [("red", 1.0)],
    "crimson": [("red", 1.0)], "scarlet": [("red", 1.0)],
    "maroon": [("red", 0.8), ("brown", 0.4)],
    "burgundy": [("red", 0.8), ("brown", 0.4)],
    "pink": [("pink", 1.0)], "magenta": [("pink", 1.0)],
    "brown": [("brown", 1.0)],
    "tan": [("brown", 0.6), ("white", 0.4)],
    "beige": [("brown", 0.4), ("white", 0.7)],
    "green": [("green", 1.0)],
    "emerald": [("green", 1.0)], "olive": [("green", 1.0)], "lime": [("green", 1.0)],
    "teal": [("teal", 1.0)], "turquoise": [("teal", 1.0)],
    "cyan": [("teal", 1.0)], "aqua": [("teal", 1.0)],
    "blue": [("blue", 1.0)],
    "navy": [("blue", 1.0)], "azure": [("blue", 1.0)], "cobalt": [("blue", 1.0)],
    "purple": [("purple", 1.0)], "violet": [("purple", 1.0)],
    "lavender": [("purple", 1.0)],
    "black": [("black", 1.0)], "charcoal": [("black", 0.8), ("grey", 0.5)],
    "white": [("white", 1.0)], "cream": [("white", 0.9)], "ivory": [("white", 0.9)],
    "grey": [("grey", 1.0)], "gray": [("grey", 1.0)],
    "silver": [("grey", 1.0)], "chrome": [("grey", 1.0)],
}


# Licence strings as hundreds of Wikipedia editors typed them, reduced to the
# handful of things they actually mean. Anything not in here is passed through
# unchanged rather than dropped — a licence we do not recognise is exactly the
# one worth showing verbatim.
LICENCE_ALIASES = {
    "CC-BY-SA-4.0": "CC BY-SA 4.0",
    "CC-BY-SA-3.0": "CC BY-SA 3.0",
    "CC-BY-SA-2.0": "CC BY-SA 2.0",
    "PD": "Public domain",
    "No restrictions": "Public domain",
    "(none stated)": "",
    "none stated": "",
    "unknown": "",
}

# Eight photographs are in the description set but not in the history sheet, so
# the join finds nothing for them. Filled in by hand rather than left blank: two
# are CC BY-SA uploads whose authors are owed a name (checked against the Commons
# API), and the other six come from the issuing agency itself, where the state is
# the credit and there is no open licence to quote.
MANUAL_ATTRIBUTION = {
    "Montana_2010–2016_standard_license_plate_(old_font).png":
        ("Broz1014", "CC BY-SA 4.0"),
    "MontanaCentennialNewFormat.webp": ("Cmhudda", "CC BY-SA 4.0"),
    "2022-passenger-sample-image-scaled.jpg":
        ("Alabama Department of Revenue", ""),
    "ID-plates_image-040.jpg": ("Idaho Transportation Department", ""),
    "plate-placeholder.jpg": ("Indiana Bureau of Motor Vehicles", ""),
    "NE-2023-standard.png": ("Nebraska Department of Motor Vehicles", ""),
    "FirstFlightNorthCarolina.png": ("State of North Carolina", "Fair use"),
    "1973HistoricUtah.jpg": ("State of Utah", "Fair use"),
    # Two more the sheet lists under a licence that requires a name but records
    # none. Both looked up on Commons; the Nevada one has a broken author
    # template there, so the Flickr account it came from is the best name there
    # is, and an account ID that resolves is worth more than a blank.
    "2018_North_Carolina_license_plate_PFT-7753.jpg": ("Dickelbers", "CC BY-SA 4.0"),
    "Penn_Jillette's_Pink_Mini_Cooper_with_Nevada_Atheist_vanity_plates.jpg":
        ("Flickr user 75814942@N00", "CC BY 2.0"),
    # Local copies of the issuing agency's own sample artwork, with no licence
    # stated anywhere. The state is the credit; there is nothing else to say.
    "KS-2024-standard.png": ("Kansas Department of Revenue", ""),
    "SC-2026-standard.png": ("South Carolina Department of Motor Vehicles", ""),
    "WY-2025-standard.png": ("Wyoming Department of Transportation", ""),
}

# Keyed the same way `image_name` normalises, so a filename written with
# underscores here still matches a title the wikis hand back with spaces.
MANUAL_ATTRIBUTION = {k.replace("_", " "): v for k, v in MANUAL_ATTRIBUTION.items()}

# Wikimedia usernames arrive with the wiki's own furniture attached.
CREDIT_NOISE = re.compile(r"\s*\((?:talk|Uploads|talk\s*\|\s*contribs)\)", re.I)


def clean_credit(raw):
    """The photographer's name, or nothing.

    The column is hand-maintained and a few rows have something else in it
    entirely — one holds a whole verification note, another the literal string
    "{}". A wrong credit is worse than no credit, so anything that does not look
    like a name is dropped.
    """
    name = CREDIT_NOISE.sub("", (raw or "").strip()).strip(" .,;")
    if name in {"", "{}", "unknown", "Unknown", "-"} or len(name) > 70:
        return ""
    return name


def image_name(url):
    """The bare filename, percent-decoded.

    Wikimedia writes the same file two ways depending on where the link was
    copied from — `Montana_2010%E2%80%932016...` in one sheet and the literal
    en-dash in the other — so matching on the whole URL loses rows that are
    plainly the same picture.
    """
    # Underscores and spaces are the same character in a wiki title, so they are
    # flattened here too — plate_credits.py keys its output the same way.
    return urllib.parse.unquote(os.path.basename(url)).replace("_", " ").strip()


def load_attribution():
    """image URL -> (credit, licence, source page), from the history sheet.

    Keyed twice, by URL and by filename, because the URL is exact when it works
    and the filename catches the encoding mismatches when it does not.
    """
    if not os.path.exists(HISTORY):
        return {}
    by_url, by_file = {}, {}
    for r in csv.DictReader(open(HISTORY)):
        url = (r.get("image_url") or "").strip()
        if not url or url in by_url:
            continue
        licence = (r.get("licence") or "").strip()
        entry = {
            "cred": clean_credit(r.get("credit")),
            "lic": LICENCE_ALIASES.get(licence, licence),
            "src": (r.get("source_page") or "").strip(),
        }
        by_url[url] = entry
        by_file.setdefault(image_name(url), entry)

    # Layered under, not over: the history sheet stays the first authority, and
    # this only answers for files it has never heard of.
    if os.path.exists(CREDITS):
        for r in csv.DictReader(open(CREDITS)):
            name = (r.get("file") or "").strip()
            licence = (r.get("licence") or "").strip()
            if not name or name in by_file:
                continue
            by_file[name] = {
                "cred": clean_credit(r.get("credit")),
                "lic": LICENCE_ALIASES.get(licence, licence),
                "src": "",
            }
    return by_url, by_file


def attribution_for(url, tables):
    by_url, by_file = tables
    name = image_name(url)
    found = by_url.get(url) or by_file.get(name)
    # The hand-written table also repairs rows the sheet has but got wrong: a
    # couple hold a verification note where the photographer's name should be,
    # and `clean_credit` correctly throws those away.
    if name in MANUAL_ATTRIBUTION and not (found or {}).get("cred"):
        cred, lic = MANUAL_ATTRIBUTION[name]
        return {"cred": cred, "lic": lic, "src": (found or {}).get("src", "")}
    return found or {"cred": "", "lic": "", "src": ""}


def parse_names():
    """code -> full jurisdiction name, from the app's own catalogue."""
    src = open(PLATE_SWIFT).read()
    return {m.group(1): m.group(2) for m in
            re.finditer(r'code: "(\w+)".*?name: "([^"]*)"', src)}


TOKEN_RE = re.compile(r"[^a-z0-9]+")


def stem(word):
    """Crude and deliberately mirrored in Swift. Not linguistics — just enough
    that "mountains" and "mountain" land on the same term."""
    if len(word) > 5 and word.endswith("ing"):
        return word[:-3]
    if len(word) > 5 and word.endswith("ed"):
        return word[:-2]
    if len(word) > 4 and word.endswith("es"):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def tokenize(text):
    out = []
    for raw in TOKEN_RE.split(text.lower()):
        if len(raw) < 3 or raw in STOP:
            continue
        out.append(stem(raw))
    return out


def years_of(rows, code):
    """"AK January 1, 2010 – December 2022 ; AK January 2023 – present" ->
    a compact human span plus decade tokens so "1970s" is searchable."""
    parts = [p.strip() for p in rows.split(";") if p.strip()]
    cleaned = []
    for p in parts:
        p = re.sub(rf"^{re.escape(code)}\s*", "", p).strip()
        cleaned.append(p)
    label = " ; ".join(cleaned)
    decades = set()
    for y in re.findall(r"(1[89]\d{2}|20\d{2})", rows):
        decades.add(f"{int(y) // 10 * 10}s")
    return label, sorted(decades)


# Field weights. Someone describing a plate leads with what is drawn on it and
# what colour it is; the caption is prose around those facts, so it counts once.
#
# `search_terms` outranks everything because it is not a description at all — it
# is the captioner's answer to "what would somebody call this?", which is the
# only field written for the query side rather than the reading side.
FIELDS = [
    ("search_terms", 4),
    ("objects", 3), ("colours", 3), ("scene", 2),
    ("graphics", 3), ("base", 3), ("serial_colour", 3),
    ("top_legend", 2), ("bottom_legend", 2),
    ("caption", 1), ("typeface", 1), ("border", 1),
    ("finish", 1), ("separator", 1),
]


def load_rows():
    """v1 rows, with any v2 re-caption layered over the top by key."""
    rows = list(csv.DictReader(open(DESCRIPTIONS_V1)))
    if not os.path.exists(DESCRIPTIONS_V2):
        print("  (no v2 captions yet — using the original prose pass)")
        return rows
    v2 = {r["key"]: r for r in csv.DictReader(open(DESCRIPTIONS_V2))}
    merged = []
    for r in rows:
        if better := v2.get(r["key"]):
            # v2 carries the same identity columns plus the index fields.
            merged.append({**r, **{k: v for k, v in better.items() if v}})
        else:
            merged.append(r)
    print(f"  v2 captions: {len(v2)} of {len(rows)} designs")
    return merged


def main():
    names = parse_names()
    rows = load_rows()

    # ---- documents ----------------------------------------------------------
    docs = []
    for r in rows:
        code = r["codes"].split("|")[0].strip()
        counts = Counter()
        for field, weight in FIELDS:
            for t in tokenize(r.get(field, "") or ""):
                counts[t] += weight
        # The jurisdiction is searchable too, so "montana" narrows without a filter.
        for t in tokenize(names.get(code, "")):
            counts[t] += 3
        label, decades = years_of(r.get("rows", ""), code)
        for d in decades:
            counts[d] += 2

        docs.append({
            "key": r["key"], "code": code,
            "name": names.get(code, code), "years": label,
            "caption": r.get("caption", ""), "base": r.get("base", ""),
            "ink": r.get("serial_colour", ""), "gfx": r.get("graphics", ""),
            "top": r.get("top_legend", ""), "bot": r.get("bottom_legend", ""),
            "url": (r.get("url") or "").strip(),
            "counts": counts,
        })

    # ---- idf ----------------------------------------------------------------
    df = defaultdict(int)
    for d in docs:
        for t in d["counts"]:
            df[t] += 1
    n = len(docs)
    idf = {t: math.log((n + 1) / (c + 0.5)) for t, c in df.items()}

    # ---- vectors ------------------------------------------------------------
    #
    # Raw weighted term frequencies, not a normalised TF-IDF vector: the app
    # scores with BM25, which does its own length normalisation and needs the
    # counts intact. Measured against a labelled query set, BM25 beat cosine
    # 92% to 88% top-1 — it stops a long description outranking a short, exact
    # one just by having more words in it.
    attribution = load_attribution()
    credited = 0
    out_docs = []
    for d in docs:
        ranked = sorted(d["counts"].items(),
                        key=lambda kv: -(kv[1] * idf.get(kv[0], 0)))[:TOP_TERMS]
        credit = attribution_for(d["url"], attribution)
        if credit["cred"] or credit["lic"]:
            credited += 1
        out_docs.append({
            "k": d["key"], "c": d["code"], "j": d["name"], "y": d["years"],
            "cap": d["caption"], "base": d["base"], "ink": d["ink"],
            "gfx": d["gfx"], "top": d["top"], "bot": d["bot"],
            "v": {t: tf for t, tf in ranked},
            "dl": sum(tf for _, tf in ranked),
            "cur": False,          # set below, once the primary picks are read
            **credit,
        })
    print(f"  attribution: {credited} of {len(out_docs)} photos credited")

    # Measured colour coverage, from the photographs rather than from anyone's
    # choice of word for them. See plate_colours.py — this is what makes "orange
    # and black" reach New York's amber plate, which every caption called gold.
    COLOURS_CSV = os.path.join(REPO, "research", "plate-colours.csv")
    measured = {}
    if os.path.exists(COLOURS_CSV):
        for r in csv.DictReader(open(COLOURS_CSV)):
            parsed = {}
            for part in filter(None, r["colours"].split("|")):
                name, _, frac = part.partition(":")
                parsed[name] = round(float(frac), 4)
            measured[r["key"]] = parsed
        # A colour on nearly every plate says little; one on a handful says a lot.
        seen = defaultdict(int)
        for c in measured.values():
            for name, frac in c.items():
                if frac >= 0.08:
                    seen[name] += 1
        n_docs = max(1, len(measured))
        colour_idf = {name: round(math.log((n_docs + 1) / (c + 0.5)), 4)
                      for name, c in seen.items()}
        for doc in out_docs:
            doc["col"] = measured.get(doc["k"], {})
        print(f"  colours: {len(measured)} measured, "
              f"{len(colour_idf)} distinct")
    else:
        colour_idf = {}
        for doc in out_docs:
            doc["col"] = {}
        print("  (no plate-colours.csv — run plate_colours.py first)")

    # Only ship IDF for terms that survived into at least one vector.
    live = set()
    for d in out_docs:
        live.update(d["v"])

    # Terms belonging to each jurisdiction's *current* design, so the Game
    # screen's search bar can find a plate by what it looks like without
    # carrying the whole 268-design index into a per-keystroke path. Current
    # only: on the road today is what you are trying to spot.
    # `plate-primary.csv` is the curated one-design-per-jurisdiction pick made
    # for the tile artwork, so it is the authority on which design is current.
    # Falling back to "does the date range say present" alone missed nine —
    # South Carolina among them, whose current row carries an end date.
    primary_keys = {}
    if os.path.exists(PRIMARY):
        for r in csv.DictReader(open(PRIMARY)):
            primary_keys[r["key"]] = r["code"]

    current = defaultdict(set)
    for r, out in zip(rows, out_docs):
        if out["k"] in primary_keys or "present" in r.get("rows", "").lower():
            current[out["c"]].update(out["v"].keys())
        # The curated pick is the one on the road today, which the app labels
        # when it lists a jurisdiction's other designs beside it.
        out["cur"] = out["k"] in primary_keys

    payload = {
        "version": 1,
        "idf": {t: round(v, 4) for t, v in idf.items() if t in live},
        "synonyms": {stem(k): [stem(s) for s in v] for k, v in SYNONYMS.items()},
        # Shipped rather than duplicated in Swift. The app needs it to tell
        # "no design mentions a moose" from "you typed the word 'the'".
        "stop": sorted(STOP),
        "colourIdf": colour_idf,
        # Emitted as a map, not pairs: a heterogeneous [name, weight] array
        # decodes badly in Swift for no benefit here.
        "colourQuery": {k: dict(v) for k, v in COLOUR_QUERY.items()},
        "current": {c: sorted(t) for c, t in sorted(current.items())},
        "designs": out_docs,
    }
    os.makedirs(RESOURCES, exist_ok=True)
    with open(INDEX_OUT, "w") as f:
        json.dump(payload, f, separators=(",", ":"))
    print(f"index: {len(out_docs)} designs, {len(payload['idf'])} terms, "
          f"{os.path.getsize(INDEX_OUT) / 1024:.0f} KB")

    # ---- images -------------------------------------------------------------
    if os.path.isdir(SHOTS):
        shutil.rmtree(SHOTS)
    os.makedirs(SHOTS)
    total = 0
    missing = []
    for d in out_docs:
        src = os.path.join(CACHE, f"{d['k']}.jpg")
        if not os.path.exists(src):
            missing.append(d["k"])
            continue
        im = Image.open(src)
        im = ImageOps.exif_transpose(im).convert("RGB")
        w = SHOT_WIDTH
        im = im.resize((w, max(1, round(im.height * w / im.width))), Image.LANCZOS)
        dst = os.path.join(SHOTS, f"{d['k']}.jpg")
        im.save(dst, "JPEG", quality=SHOT_QUALITY, optimize=True, progressive=True)
        total += os.path.getsize(dst)
    print(f"shots: {len(out_docs) - len(missing)} images, {total / 1024 / 1024:.1f} MB")
    if missing:
        print(f"  !! no cached photo for {len(missing)}: {missing[:8]}")


if __name__ == "__main__":
    main()
