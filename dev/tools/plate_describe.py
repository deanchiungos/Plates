#!/usr/bin/env python3
"""Re-caption every street-legal plate design, written for retrieval.

The first pass caption was written to be *read* — good prose, accurate, and the
wrong shape for search. It said "ridgeline" where a person types "mountains",
and it left things out: nothing in 268 descriptions mentioned a moose, a loon or
a fish, so no amount of ranking could ever find them. Measured against a labelled
query set, the ranking was already at 100% top-1; every remaining failure was the
corpus, not the retrieval.

So this pass asks for two different things at once:

  the prose fields   what a curious player enjoys reading, kept from the old pass
  the index fields   an exhaustive inventory in the words an ordinary person
                     would actually type, including the broader category for
                     anything specific — a loon is also a bird, also a duck

`search_terms` is the one that matters. It is not a summary; it is the answer to
"what might somebody call this?", and it is weighted highest when the index is
built.

    python3 ios/tools/plate_describe.py models   --key-file PATH
    python3 ios/tools/plate_describe.py test     --key-file PATH --limit 5
    python3 ios/tools/plate_describe.py run      --key-file PATH
    python3 ios/tools/plate_describe.py ingest   --answers answers.json

Resumable: `run` skips any key already present in the output, so an interrupted
batch continues where it stopped. Every call records its own token usage, because
an unmetered loop over a few hundred photographs is exactly the sort of thing
that quietly costs real money.
"""
import argparse
import base64
import csv
import json
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESEARCH = os.path.join(ROOT, "dev", "research")
CACHE = os.path.join(RESEARCH, "images", "cache")
SOURCE = os.path.join(RESEARCH, "plate-descriptions.csv")
OUT = os.path.join(RESEARCH, "plate-descriptions-v2.csv")

DEFAULT_MODEL = "gpt-5-mini"

# USD per 1M tokens, from developers.openai.com/api/docs/pricing (checked
# 2026-08-01). Only used to print an estimate — if a model is missing here the
# run still works, it just cannot cost itself.
PRICING = {                      # model: (input, output)
    "gpt-5":         (1.25, 10.00),
    "gpt-5-mini":    (0.25,  2.00),
    "gpt-5-nano":    (0.05,  0.40),
    "gpt-5.4":       (2.50, 15.00),
    "gpt-5.4-mini":  (0.75,  4.50),
    "gpt-4o":        (2.50, 10.00),
    "gpt-4o-mini":   (0.15,  0.60),
    "gpt-4.1-mini":  (0.40,  1.60),
}


def cost(model, tin, tout):
    """(usd, rate_note) — None when the model's price is not known here.

    Longest prefix wins. Matching in dictionary order instead priced
    "gpt-5-mini" as "gpt-5" — a 5x overstatement, and silently.
    """
    for name in sorted(PRICING, key=len, reverse=True):
        if model.startswith(name):
            pin, pout = PRICING[name]
            usd = tin / 1e6 * pin + tout / 1e6 * pout
            return usd, f"${pin}/M in, ${pout}/M out"
    return None, "unknown pricing"

FIELDS = ["key", "url", "codes", "rows",
          "caption", "base", "serial_color", "finish", "typeface",
          "top_legend", "bottom_legend", "graphics", "separator", "border",
          "objects", "colors", "scene", "search_terms",
          "confidence", "caveat",
          "model", "input_tokens", "output_tokens", "generated_at"]

PROMPT = """\
You are cataloguing the DESIGN of a vehicle registration plate so that people can
FIND it later by describing it from memory. Describe only what is fixed for every
plate issued to this design.

NEVER transcribe the serial — the registration number itself. It is arbitrary:
sample and collector plates carry invented serials, so repeating one would record
a fact about a single plate as though it were a fact about the design. Describe its
TYPOGRAPHY instead — color, finish, weight, width, terminals, distinctive glyph
shapes — but never the characters.

Ignore these. They vary from vehicle to vehicle and are not part of the design:
  - registration stickers and any month or year inside them
  - county, city or dealer names
  - the frame, the bumper, or the vehicle behind the plate
  - photographic artefacts: glare, shadow, angle, wear, rust, mounting bolts

Fixed legends ARE design. Quote them exactly: the jurisdiction name, any slogan,
"USA", and any web address printed by the issuing agency. If text is too small,
angled or worn to read with confidence, say so in "caveat" rather than guessing.

Note whether the serial is EMBOSSED (raised metal, a highlight along one edge of
each stroke and a shadow along the other) or SCREENED (printed flat onto the
sheeting). That single distinction separates designs that are otherwise identical.

=== THE PART THAT MAKES SEARCH WORK ===

Somebody saw this plate through a car window and is now trying to find it again.
They will type ordinary words. Your job is to make sure the words they would
plausibly reach for are present.

Be EXHAUSTIVE. Name every distinct thing visible in the artwork, however small —
every animal, plant, building, vehicle, landform, celestial body, emblem, symbol,
device, pattern. If you can see it, it goes in. A detail you leave out is a
search that will fail.

Use EVERYDAY words, not curatorial ones. "mountains", not "ridgeline". "bird",
not "avian silhouette". If a shape is stylised or abstract, still say what it
most looks like.

For anything specific, ALSO give the general category it belongs to, because
people search at whatever level they happen to remember:
  a loon        -> also bird, also duck, also waterbird
  a palmetto    -> also palm, also tree
  a saguaro     -> also cactus, also desert
  Mount Rushmore-> also mountain, also faces, also monument, also carving
  a schooner    -> also boat, also ship, also sailboat
Do the same for colors: "teal" is also "blue" and "green"; "maroon" is also
"red"; "gold" is also "yellow".

Reply with JSON only, no prose around it:
{
  "caption":       "2-4 sentences. What a curious player would enjoy reading. Lead with the overall impression, then the distinguishing detail.",
  "base":          "background color and finish, including any gradient and its direction",
  "serial_color": "color of the serial characters",
  "finish":        "embossed" | "screened" | "unclear",
  "typeface":      "character of the letterforms; name a distinctive glyph if one stands out",
  "top_legend":    "exact text across the top, or \\"\\" if none",
  "bottom_legend": "exact text across the bottom, or \\"\\" if none",
  "graphics":      "pictorial elements and where they sit; \\"\\" if the plate is plain",
  "separator":     "what divides the serial groups (dash, dot, symbol, space), or \\"\\"",
  "border":        "edge treatment: keyline, band, none",

  "objects":       ["every distinct thing visible, everyday singular nouns, most prominent first"],
  "colors":       ["every color present, plain words: red, dark blue, pale green"],
  "scene":         ["setting and mood words if the art depicts a place: beach, mountains, farm, city, night, sunset. [] if the plate is plain"],
  "search_terms":  ["THE IMPORTANT ONE. 15-35 lowercase single words. Build it MECHANICALLY, do not summarise: (1) every entry in objects; (2) for EACH of those, the broader everyday word it also is — canoe ALSO boat; palmetto ALSO palm ALSO tree; loon ALSO bird ALSO duck; saguaro ALSO cactus; schooner ALSO boat ALSO ship; Rushmore ALSO mountain ALSO faces; (3) every entry in colors and scene; (4) distinctive words from the legends; (5) the jurisdiction name. Single words, lowercase, no duplicates. OMIT words true of nearly every plate — plate, license, licence, registration, serial, number, wordmark, slogan, legend, font, typeface, serif, sheeting, reflective, border. They match everything and so distinguish nothing."],

  "confidence":    "high" | "medium" | "low",
  "caveat":        "only if the photograph limits the reading — angle, crop, resolution. Otherwise \\"\\"."
}"""


def load_key(args):
    if args.key_file:
        with open(os.path.expanduser(args.key_file)) as f:
            return f.read().strip()
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("No key. Pass --key-file PATH or set OPENAI_API_KEY.")
    return key


def api(path, key, body=None, method="GET"):
    req = urllib.request.Request(
        "https://api.openai.com/v1" + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read())


def describe(key, model, image_path):
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    body = {
        "model": model,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": PROMPT},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ],
        }],
        "response_format": {"type": "json_object"},
    }
    # GPT-5 models bill hidden reasoning as output tokens. Left at the default,
    # one caption spent ~2,600 tokens thinking to produce ~500 of JSON. This is
    # a describe-what-you-see task, not a reasoning one, so the deliberation buys
    # nothing and costs 5x. Silently ignored by non-reasoning models.
    if model.startswith(("gpt-5", "o3", "o4")):
        body["reasoning_effort"] = "low"
    for attempt in range(4):
        try:
            r = api("/chat/completions", key, body, method="POST")
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:300]
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(4 * 2 ** attempt)
                continue
            raise SystemExit(f"HTTP {e.code}: {detail}")
    text = r["choices"][0]["message"]["content"]
    usage = r.get("usage", {})
    return json.loads(text), usage.get("prompt_tokens", 0), usage.get("completion_tokens", 0)


def worklist():
    return list(csv.DictReader(open(SOURCE)))


def done_keys():
    if not os.path.exists(OUT):
        return set()
    return {r["key"] for r in csv.DictReader(open(OUT))}


def flatten(v):
    """Lists become pipe-joined strings; the CSV stays one row per design.

    Deduplicated on the way in. Asked for Arizona's terms the model once
    emitted "cactus" twenty-two times, which would have handed that one
    document a term frequency no other plate could approach and skewed every
    query containing it. Cheaper to make the ingest robust than to trust the
    instruction.
    """
    if isinstance(v, list):
        seen, out = set(), []
        for x in v:
            s = str(x).strip()
            if s and s.lower() not in seen:
                seen.add(s.lower())
                out.append(s)
        return " | ".join(out)
    return str(v or "").strip()


def cmd_ingest(path):
    """Merge answers written by whatever model is already reading this repo.

    The same escape hatch `plate_vision.py` has, and for the same reason: `run`
    needs an OpenAI key, and a two-image top-up should not be blocked on having
    one. The prompt above is the contract either way — a caller using this path
    is expected to have followed it, including the mechanical construction of
    `search_terms`, which is the field the whole index leans on.

        python3 ios/tools/plate_describe.py ingest answers.json

    Takes a list of objects carrying "key", or {"key": {...}}. Tokens are the
    caller's to declare; left out, the row still records which model wrote it,
    so the ledger never silently reads as free.
    """
    blob = json.load(open(path))
    items = list(blob.values()) if isinstance(blob, dict) else blob
    work = {r["key"]: r for r in worklist()}
    already = done_keys()

    new_file = not os.path.exists(OUT)
    f = open(OUT, "a", newline="")
    w = csv.DictWriter(f, fieldnames=FIELDS)
    if new_file:
        w.writeheader()

    added = 0
    for it in items:
        key = it.get("key")
        src = work.get(key)
        if not src:
            sys.stderr.write(f"  skip {key}: not in {os.path.basename(SOURCE)}\n")
            continue
        if key in already:
            sys.stderr.write(f"  skip {key}: already described\n")
            continue
        if not it.get("caption") or not it.get("search_terms"):
            sys.stderr.write(f"  skip {key}: needs both caption and search_terms\n")
            continue
        row = {"key": key, "url": src["url"], "codes": src["codes"],
               "rows": src["rows"],
               "model": it.get("model", "unrecorded"),
               "input_tokens": it.get("input_tokens", ""),
               "output_tokens": it.get("output_tokens", ""),
               "generated_at": it.get("generated_at") or time.strftime("%Y-%m-%d")}
        for field in FIELDS:
            if field not in row:
                row[field] = flatten(it.get(field))
        w.writerow(row)
        added += 1
    f.close()
    print(f"ingested {added} -> {OUT}")


def run(args, limit=None):
    key = load_key(args)
    rows = worklist()
    already = done_keys()
    todo = [r for r in rows if r["key"] not in already]
    if limit:
        todo = todo[:limit]
    if not todo:
        print("nothing to do — every design already described")
        return

    new_file = not os.path.exists(OUT)
    f = open(OUT, "a", newline="")
    w = csv.DictWriter(f, fieldnames=FIELDS)
    if new_file:
        w.writeheader()

    # Concurrent, because this is 268 round trips of ~15s each and almost all of
    # that is waiting on the network. Serial it is an hour; eight at a time is
    # about ten minutes. The lock covers the shared writer and the counters —
    # the CSV is appended to as results land, so an interrupted run still keeps
    # everything it finished.
    lock = threading.Lock()
    state = {"tin": 0, "tout": 0, "done": 0}

    def work(src):
        path = os.path.join(CACHE, f"{src['key']}.jpg")
        if not os.path.exists(path):
            print(f"  !! {src['key']} ({src['codes']}): no cached image, skipped")
            return
        try:
            data, ti, to = describe(key, args.model, path)
        except Exception as e:
            print(f"  !! {src['key']} ({src['codes']}): {type(e).__name__}: {e}")
            return
        row = {k: "" for k in FIELDS}
        row.update({
            "key": src["key"], "url": src["url"],
            "codes": src["codes"], "rows": src["rows"],
            "model": args.model, "input_tokens": ti, "output_tokens": to,
            "generated_at": time.strftime("%Y-%m-%d"),
        })
        for field in ("caption", "base", "serial_color", "finish", "typeface",
                      "top_legend", "bottom_legend", "graphics", "separator",
                      "border", "objects", "colors", "scene", "search_terms",
                      "confidence", "caveat"):
            row[field] = flatten(data.get(field))
        with lock:
            w.writerow(row)
            f.flush()
            state["tin"] += ti
            state["tout"] += to
            state["done"] += 1
            n_terms = len(row["search_terms"].split("|")) if row["search_terms"] else 0
            print(f"  [{state['done']}/{len(todo)}] {src['codes']:5} {n_terms:2} terms  "
                  f"({ti}+{to} tok)  {row['objects'][:52]}", flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(work, todo))
    tin, tout = state["tin"], state["tout"]
    f.close()
    n = max(1, len(todo))
    print(f"\ntokens: {tin:,} in / {tout:,} out over {len(todo)} images")
    print(f"  per image: {tin // n:,} in / {tout // n:,} out")
    usd, note = cost(args.model, tin, tout)
    if usd is None:
        print(f"  cost: {note} for {args.model}")
        return
    print(f"  cost: ${usd:.4f} so far  ({note})")
    remaining = len(worklist()) - len(done_keys())
    if remaining > 0:
        print(f"  projected for the remaining {remaining}: "
              f"${usd / n * remaining:.2f}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["models", "test", "run", "ingest"])
    p.add_argument("--answers", help="JSON file for `ingest`")
    p.add_argument("--key-file", help="file containing the API key, so it never "
                                      "appears in a command line or a log")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--limit", type=int, default=5)
    p.add_argument("--workers", type=int, default=8)
    args = p.parse_args()

    if args.command == "models":
        key = load_key(args)
        ids = sorted(m["id"] for m in api("/models", key)["data"])
        print("\n".join(i for i in ids if any(
            t in i for t in ("gpt-5", "gpt-4o", "gpt-4.1", "o4", "vision"))))
    elif args.command == "ingest":
        if not args.answers:
            sys.exit("usage: plate_describe.py ingest --answers answers.json")
        cmd_ingest(args.answers)
    elif args.command == "test":
        run(args, limit=args.limit)
    else:
        run(args)


if __name__ == "__main__":
    main()
