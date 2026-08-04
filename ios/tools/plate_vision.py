#!/usr/bin/env python3
"""Vision-to-text design captions for the plates that could actually be on a road.

    python3 ios/tools/plate_vision.py plan      # what it would cost, no network
    python3 ios/tools/plate_vision.py fetch     # download + normalise into a cache
    python3 ios/tools/plate_vision.py batch     # emit work units for an in-session model
    python3 ios/tools/plate_vision.py ingest F  # merge answers back, with a token ledger
    python3 ios/tools/plate_vision.py describe  # run it via the API (ANTHROPIC_API_KEY)

Scope is deliberately not "every image in the dataset". It is the street-legal set —
the plates a spotter can still meet — which `plate_browser.street_legal` already
decides. That is 363 rows, and because Wikipedia reuses one photograph across rows
that share a design, only 269 distinct images. Describing per-image rather than
per-row is a 26% saving for free, and it also keeps two rows that share a picture
from acquiring two subtly different captions.

Two engines, one prompt. `describe` needs an API key; `batch`/`ingest` route the same
work through whatever model is already reading this repo, which needs no key at all.
Both write the same CSV and both record tokens per call, because an unmetered loop
over a few hundred images is exactly the kind of thing that quietly costs real money.
"""

import base64
import csv
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plate_browser as pb

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESEARCH = os.path.join(ROOT, "research")
HISTORY = os.path.join(RESEARCH, "plate-history.csv")
CUTOFFS = os.path.join(RESEARCH, "plate-validity-cutoffs.csv")
CACHE = os.path.join(RESEARCH, "images", "cache")
OUT = os.path.join(RESEARCH, "plate-descriptions.csv")

# Wikimedia asks for a real contact in the User-Agent and throttles anonymous bulk
# fetches that do not carry one.
UA = "PlatesResearch/0.1 (https://github.com/EGG-GIT/Plates; eggeppel34@gmail.com)"

# Normalising every image to one width makes the token cost per call a constant
# instead of a function of whatever the photographer uploaded. 960 was chosen by
# looking: at 500 the embossing and the mountain silhouette survive but the letter
# terminals are mush, and the step up costs ~445 extra input tokens per image —
# about $0.36 across the whole run, which is not worth trading detail for.
WIDTH = 960

# Anthropic bills an image at roughly (w x h)/750 tokens.
PX_PER_TOKEN = 750

MODEL = os.environ.get("PLATE_VISION_MODEL", "claude-sonnet-5")

# Per million tokens. Only used to turn the token ledger into a number a human can
# react to; wrong prices make the estimate wrong, not the run.
PRICES = {
    "claude-opus-5":   (15.0, 75.0),
    "claude-sonnet-5": (3.0, 15.0),
    "claude-haiku-4-5-20251001": (1.0, 5.0),
}

PROMPT = """\
You are cataloguing the DESIGN of a vehicle registration plate for a plate-spotting
game. Describe only what is fixed for every plate issued to this design.

NEVER transcribe the serial — the registration number itself. It is arbitrary: sample
and collector plates carry invented serials, so repeating one would record a fact
about a single plate as though it were a fact about the design. Describe its
TYPOGRAPHY instead — colour, finish, weight, width, terminals, and any distinctive
glyph shapes — but never the characters.

Ignore these too. They vary from vehicle to vehicle and are not part of the design:
  - registration stickers and any month or year inside them
  - county, city or dealer names
  - the frame, the bumper, or the vehicle behind the plate
  - photographic artefacts: glare, shadow, angle, wear, rust, mounting bolts

Fixed legends ARE design. Quote them exactly: the jurisdiction name, any slogan,
"USA", and any web address printed by the issuing agency. A slogan is the single most
identifying thing about many designs — do not paraphrase it as "the script slogan" or
"a legend along the bottom". The caption sentence itself must include the exact quoted
words, not only the top_legend/bottom_legend fields below. If any text on the plate is
too small, angled or worn to read with confidence, say so in "caveat" rather than
guessing at it or silently dropping it.

Note especially whether the serial is EMBOSSED (raised metal, with a highlight along
one edge of each stroke and a shadow along the other) or SCREENED (printed flat onto
the sheeting). That single distinction separates designs that are otherwise identical.

Reply with JSON only, no prose around it:
{
  "caption":       "2-4 sentences. The description a curious player would enjoy reading. Lead with the overall impression, then the distinguishing detail.",
  "base":          "background colour and finish, including any gradient and its direction",
  "serial_colour": "colour of the serial characters",
  "finish":        "embossed" | "screened" | "unclear",
  "typeface":      "character of the letterforms; name a distinctive glyph if one stands out",
  "top_legend":    "exact text across the top, or \\"\\" if none",
  "bottom_legend": "exact text across the bottom, or \\"\\" if none",
  "graphics":      "pictorial elements and where they sit; \\"\\" if the plate is plain",
  "separator":     "what divides the serial groups (dash, dot, symbol, space), or \\"\\"",
  "border":        "edge treatment: keyline, band, none",
  "confidence":    "high" | "medium" | "low",
  "caveat":        "only if the photograph limits the reading — angle, crop, resolution. Otherwise \\"\\"."
}"""


def street_legal_images():
    """The work list: one entry per distinct image, carrying every row it serves."""
    cutoffs = pb.load_cutoffs(CUTOFFS)
    by_url = {}
    for r in csv.DictReader(open(HISTORY)):
        if not pb.street_legal(r, cutoffs)[0]:
            continue
        url = r["image_url"].strip()
        if not url:
            continue
        # A placeholder outline is a picture of nothing. Describing it would produce a
        # confident caption for a design the dataset does not actually have.
        if "blank license plate shape" in r["image_file"].lower():
            continue
        e = by_url.setdefault(url, {
            "key": hashlib.sha1(url.encode()).hexdigest()[:12],
            "url": url,
            "file": r["image_file"],
            "codes": [],
            "rows": [],
        })
        if r["code"] not in e["codes"]:
            e["codes"].append(r["code"])
        e["rows"].append(f'{r["code"]} {r["dates_issued"]}'.strip())
    return sorted(by_url.values(), key=lambda e: (e["codes"][0], e["key"]))


def cache_path(entry):
    return os.path.join(CACHE, f'{entry["key"]}.jpg')


def get(url, tries=4):
    """Plain CDN GET, with backoff on the codes that mean "slow down".

    Take the original from upload.wikimedia.org and resize locally. The tempting
    alternative — Special:FilePath?width=N, which serves any width you ask for — runs
    through MediaWiki's application servers rather than the image CDN, and they
    rate-limit far more aggressively: a run at 0.4s intervals got 84 images before
    429ing and lost the remaining 184. upload.wikimedia.org is a cache and tolerates a
    steady pull.

    Requesting a specific thumbnail width off the CDN is not a way out either. Only the
    sizes MediaWiki has already rendered exist there — 330, 500 and 1280 resolve for a
    given file while 400, 640, 800 and 1024 return an error page — and which ones those
    are varies per file. Downscaling here is the only route that yields exactly WIDTH
    for every image, which is what keeps the per-call token cost a constant.
    """
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and i < tries - 1:
                time.sleep(3 * 2 ** i)
                continue
            raise


def fetch_one(entry):
    """Download the original, then resize locally to exactly WIDTH."""
    from PIL import Image

    dest = cache_path(entry)
    if os.path.exists(dest):
        return "cached"
    # Not everything in `image_url` is a URL. Nebraska's standard plate was extracted
    # from the agency's own PDF and lives in the repo as a relative path, which is the
    # better provenance of the two and should not be the one row this skips.
    url = entry["url"]
    if "://" not in url:
        blob = open(os.path.join(RESEARCH, url), "rb").read()
    else:
        blob = get(url)

    tmp = dest + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(blob)
    im = Image.open(tmp)
    # Palette and RGBA sources (many PNGs here) have to lose their alpha before JPEG,
    # and compositing onto white matches how the plate would sit on the page.
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    else:
        im = im.convert("RGB")
    if im.width != WIDTH:
        im = im.resize((WIDTH, max(1, round(im.height * WIDTH / im.width))), Image.LANCZOS)
    im.save(dest, "JPEG", quality=88)
    os.remove(tmp)
    return "fetched"


def image_tokens(path):
    from PIL import Image
    w, h = Image.open(path).size
    return round(w * h / PX_PER_TOKEN)


def money(model, tin, tout):
    if model not in PRICES:
        return None
    pin, pout = PRICES[model]
    return tin / 1e6 * pin + tout / 1e6 * pout


FIELDS = ["key", "url", "codes", "rows", "caption", "base", "serial_colour", "finish",
          "typeface", "top_legend", "bottom_legend", "graphics", "separator", "border",
          "confidence", "caveat", "model", "input_tokens", "output_tokens", "generated_at"]


def load_done():
    if not os.path.exists(OUT):
        return {}
    return {r["key"]: r for r in csv.DictReader(open(OUT))}


def save(records):
    with open(OUT, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        for r in sorted(records.values(), key=lambda r: (r.get("codes", ""), r["key"])):
            w.writerow({k: r.get(k, "") for k in FIELDS})


def ledger(records, label="ledger"):
    tin = sum(int(r.get("input_tokens") or 0) for r in records.values())
    tout = sum(int(r.get("output_tokens") or 0) for r in records.values())
    n = len(records)
    line = (f"{label}: {n} images, {tin:,} in + {tout:,} out = {tin + tout:,} tokens")
    models = {r.get("model") for r in records.values() if r.get("model")}
    if len(models) == 1:
        c = money(models.pop(), tin, tout)
        if c is not None:
            line += f"  (~${c:.2f})"
    if n:
        line += f"\n  per call: {tin // n:,} in + {tout // n:,} out"
    return line


def cmd_plan(argv):
    work = street_legal_images()
    done = load_done()
    todo = [e for e in work if e["key"] not in done]
    rows = sum(len(e["rows"]) for e in work)
    est_in = round(WIDTH * (WIDTH / 2) / PX_PER_TOKEN) + 420   # image + prompt
    est_out = 320
    n = len(todo)
    print(f"street-legal rows with an image : {rows}")
    print(f"distinct images                 : {len(work)}"
          f"   ({rows - len(work)} rows ride on a shared photograph)")
    print(f"already described               : {len(done)}")
    print(f"to do                           : {n}")
    print()
    print(f"normalised to {WIDTH}px wide -> ~{est_in - 420} image tokens per call")
    print(f"estimate: ~{n * est_in:,} in + ~{n * est_out:,} out")
    for m in ("claude-haiku-4-5-20251001", "claude-sonnet-5", "claude-opus-5"):
        c = money(m, n * est_in, n * est_out)
        print(f"   {m:<28} ~${c:.2f}")
    if done:
        print()
        print(ledger(done, "actually spent so far"))


def cmd_fetch(argv):
    os.makedirs(CACHE, exist_ok=True)
    work = street_legal_images()
    limit = int(argv[0]) if argv else len(work)
    ok = miss = cached = 0
    for i, e in enumerate(work[:limit], 1):
        try:
            r = fetch_one(e)
            ok += r == "fetched"
            cached += r == "cached"
            if r == "fetched":
                time.sleep(0.25)     # politeness; the CDN is not the bottleneck
        except Exception as exc:
            miss += 1
            sys.stderr.write(f"  miss {e['codes'][0]:<4} {e['file'][:60]}: {exc}\n")
        if i % 25 == 0:
            sys.stderr.write(f"  {i}/{min(limit, len(work))}\n")
    print(f"{ok} fetched, {cached} already cached, {miss} failed -> {CACHE}")


def cmd_batch(argv):
    """Emit work units for a model that is already looking at this repo.

    Deliberately not a prompt dump: it hands over absolute paths and the exact token
    cost of each image, so the reader can decide how many to take in one pass.
    """
    work = street_legal_images()
    done = load_done()
    todo = [e for e in work if e["key"] not in done and os.path.exists(cache_path(e))]
    limit = int(argv[0]) if argv else 25
    units = []
    for e in todo[:limit]:
        p = cache_path(e)
        units.append({
            "key": e["key"], "codes": e["codes"], "rows": e["rows"][:4],
            "path": p, "image_tokens": image_tokens(p),
        })
    print(json.dumps({
        "prompt": PROMPT,
        "remaining": len(todo),
        "units": units,
        "ingest": f"python3 ios/tools/plate_vision.py ingest <file.json>",
    }, indent=2))


def cmd_ingest(argv):
    """Merge answers produced outside the API path.

    Accepts {"key": {...fields...}} or a list of objects carrying "key". Token counts
    are the caller's to supply; when they are missing we fill the image side from the
    cached file and mark the model so the ledger never silently reads as free.
    """
    if not argv:
        sys.exit("usage: plate_vision.py ingest answers.json")
    blob = json.load(open(argv[0]))
    items = blob.values() if isinstance(blob, dict) else blob
    if isinstance(blob, dict) and "key" in blob:
        items = [blob]

    work = {e["key"]: e for e in street_legal_images()}
    records = load_done()
    added = 0
    for it in items:
        key = it["key"]
        e = work.get(key)
        if not e:
            sys.stderr.write(f"  skip {key}: not in the street-legal set\n")
            continue
        p = cache_path(e)
        rec = {
            "key": key, "url": e["url"],
            "codes": "|".join(e["codes"]), "rows": " ; ".join(e["rows"]),
            "model": it.get("model", MODEL),
            "input_tokens": it.get("input_tokens")
                            or (image_tokens(p) + 420 if os.path.exists(p) else ""),
            "output_tokens": it.get("output_tokens")
                             or round(len(json.dumps(it)) / 3.6),
            "generated_at": it.get("generated_at") or time.strftime("%Y-%m-%d"),
        }
        for f in ("caption", "base", "serial_colour", "finish", "typeface",
                  "top_legend", "bottom_legend", "graphics", "separator",
                  "border", "confidence", "caveat"):
            rec[f] = (it.get(f) or "").strip()
        if not rec["caption"]:
            sys.stderr.write(f"  skip {key}: no caption\n")
            continue
        records[key] = rec
        added += 1
    save(records)
    print(f"ingested {added} -> {OUT}")
    print(ledger(records, "total"))


def call_api(path, model):
    """Raw Messages API over urllib, so this runs without the SDK installed."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("describe needs ANTHROPIC_API_KEY (or use batch/ingest instead)")
    with open(path, "rb") as fh:
        b64 = base64.standard_b64encode(fh.read()).decode()
    body = json.dumps({
        "model": model,
        "max_tokens": 900,
        "messages": [{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64",
                                         "media_type": "image/jpeg", "data": b64}},
            {"type": "text", "text": PROMPT},
        ]}],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"content-type": "application/json", "x-api-key": key,
                 "anthropic-version": "2023-06-01"})
    with urllib.request.urlopen(req, timeout=120) as r:
        out = json.load(r)
    text = "".join(b.get("text", "") for b in out.get("content", []))
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        raise ValueError("no JSON in reply")
    parsed = json.loads(m.group(0))
    u = out.get("usage", {})
    parsed["input_tokens"] = u.get("input_tokens")
    parsed["output_tokens"] = u.get("output_tokens")
    parsed["model"] = out.get("model", model)
    return parsed


def cmd_describe(argv):
    limit = int(argv[0]) if argv else 10**9
    model = MODEL
    work = street_legal_images()
    records = load_done()
    todo = [e for e in work
            if e["key"] not in records and os.path.exists(cache_path(e))][:limit]
    if not todo:
        print("nothing to do — run fetch first, or everything is described")
        return
    run_in = run_out = 0
    for i, e in enumerate(todo, 1):
        try:
            got = call_api(cache_path(e), model)
        except Exception as exc:
            sys.stderr.write(f"  fail {e['codes'][0]} {e['key']}: {exc}\n")
            continue
        rec = {"key": e["key"], "url": e["url"], "codes": "|".join(e["codes"]),
               "rows": " ; ".join(e["rows"]), "model": got["model"],
               "input_tokens": got["input_tokens"], "output_tokens": got["output_tokens"],
               "generated_at": time.strftime("%Y-%m-%d")}
        for f in ("caption", "base", "serial_colour", "finish", "typeface",
                  "top_legend", "bottom_legend", "graphics", "separator",
                  "border", "confidence", "caveat"):
            rec[f] = str(got.get(f, "")).strip()
        records[e["key"]] = rec
        run_in += got["input_tokens"] or 0
        run_out += got["output_tokens"] or 0
        # Per call, as asked: a run that is drifting over budget should be visible
        # while it is still running, not after it has finished spending.
        spent = money(model, run_in, run_out)
        sys.stderr.write(
            f"  [{i}/{len(todo)}] {'/'.join(e['codes']):<10} "
            f"{got['input_tokens']:>5} in {got['output_tokens']:>4} out"
            + (f"   running ${spent:.2f}\n" if spent is not None else "\n"))
        if i % 10 == 0:
            save(records)
    save(records)
    print(ledger(records, "total"))


def main():
    cmds = {"plan": cmd_plan, "fetch": cmd_fetch, "batch": cmd_batch,
            "ingest": cmd_ingest, "describe": cmd_describe}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
