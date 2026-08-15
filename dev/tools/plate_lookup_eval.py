#!/usr/bin/env python3
"""Score the plate lookup against queries with known right answers.

Retrieval quality is the kind of thing that feels fine and is not. This is the
harness that caught the real problems: that TF-IDF cosine was losing to BM25,
that Apple's on-device embeddings were losing to both, and — most usefully —
that several apparent failures were correct answers to a badly written label.

Gold sets are jurisdictions, not individual designs, because a plate's look
usually persists across several issues and any of them is a right answer.

    python3 ios/tools/plate_lookup_eval.py
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plate_lookup_build import tokenize  # the one true tokeniser

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INDEX = os.path.join(REPO, "ios", "Plates", "Resources", "PlateLookup.json")

# How much measured color counts against the text score. Tuned on the query
# that prompted it: at 0 New York's amber plate sat 18th of 60 for "orange and
# black"; at 10 it is 6th, behind five plates that genuinely are more orange
# and black than it is. Higher changes nothing further.
COLOR_WEIGHT = 10.0

# Things a person would actually type, with the jurisdictions that genuinely
# have them. Verified against the source photographs, not assumed — an earlier
# version of this file marked Nova Scotia wrong for "boat" when its schooner is
# obviously a boat.
GOLD = {
    "covered bridge": {"IN"},
    "cactus": {"AZ"},
    "peach": {"GA"},
    "land of lincoln": {"IL"},
    "plate that says vacationland": {"ME"},
    "palm tree and a crescent moon": {"SC"},
    "something with the ocean": {"RI", "NS", "AL", "FL", "NB", "PE", "NL"},
    "has a boat on it": {"NL", "NS", "NB", "VA"},
    "plate with a big red barn": {"IA", "OH", "WI"},
    "looks like a sunrise": {"TN", "OH", "NM"},
    # MS belongs here: its 2019 issue carries an eagle. Left out of the first
    # version of this label, which then scored a correct answer as a failure.
    "a blue plate with a bird on it": {"LA", "MO", "OK", "WI", "AK", "MS"},
    "yellow with a bison": {"ND", "MB"},
    "green plate with a lighthouse": {"MS", "AL"},
    "red white and blue with a potato": {"ID"},
    "blue plate with a crown": {"ON"},
    "wheat": {"SK", "KS", "ND"},
    "sandstone arch": {"UT"},
    "mount rushmore": {"SD"},
    "statue of liberty": {"NY"},
    "orange sunset in the desert": {"AZ", "UT", "NM"},
    "covered wagon": {"NE"},
    "magnolia": {"MS"},
    "canoe": {"MN"},
    "state outline in the middle": {"MN", "NJ", "MO", "FL", "WV", "KY"},
    "mountains with snow": {"CO", "MT", "WA", "AK", "ID", "UT", "NV", "WY"},
    "a bridge": {"IN", "NY", "MI", "SD"},
    "farm scene": {"IA", "OH", "WI", "SK", "MB"},
    "peaches": {"GA"},
}

# Queries whose right answer is "nothing". Checked against the corpus: not one
# of the 268 descriptions mentions any of these, so an empty result is correct
# and anything confident is worse than useless. "space shuttle" used to sit in
# GOLD above pointing at Florida, which was simply wrong — Florida's standard
# plate is oranges — and it scored a correct empty result as a failure.
#
# "space shuttle" was here and is not a fair test: "space" is a real indexed
# term, so matching on it is correct behaviour rather than a false positive.
# "loon" is not here either — with fuzzy matching on it reaches "loop" and
# "look", which is the accepted cost of tolerating typos on short words.
EMPTY_EXPECTED = ["moose", "fish", "dinosaur", "antlers", "lobster", "xyzzy"]


def load():
    with open(INDEX) as f:
        return json.load(f)


def within(a, b, maxd):
    """Levenshtein distance <= maxd, bailing early."""
    if abs(len(a) - len(b)) > maxd:
        return False
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        if min(cur) > maxd:
            return False
        prev = cur
    return prev[-1] <= maxd


def nearest(term, vocab):
    """Vocabulary terms close enough to be what someone meant.

    People misspell. Without this, one wrong letter drops the word entirely and
    "pensylvania" matches nothing at all — while "new yok" is worse than nothing,
    because "yok" vanishes and the surviving "new" confidently returns New Jersey.
    Weighted below a typed word so a real match always wins.
    """
    # 3, not 4. "yok" for "york" is a one-character slip and the commonest kind
    # there is; a 4-character floor let exactly that case through unhelped.
    if len(term) < 3:
        return []
    # The first letter must survive. Typos are transpositions, doubles and
    # dropped letters in the middle of a word — almost never the opening
    # character. Without this constraint "loon" matches "moon" and Sourh
    # Carolina is returned for a bird that appears on no plate at all, which is
    # worse than saying nothing: it looks like an answer.
    # Short words need two matching leading letters, not one. On a four-letter
    # word a single edit is a quarter of it, and "loon" -> "lion" put Prince
    # Edward Island's crest in front of someone looking for a bird. "yok" ->
    # "york" survives because both keep "yo".
    keep = 2 if len(term) < 5 else 1
    near = [v for v in vocab if v[:keep] == term[:keep]]
    hits = [(v, 0.75) for v in near if v.startswith(term) or term.startswith(v)]
    if not hits:
        hits = [(v, 0.7) for v in near if within(term, v, 1)]
    # Two edits only on genuinely long words. At seven characters it matched
    # "shuttle" to "subtle", which is not a spelling mistake, it is a different
    # word.
    if not hits and len(term) >= 9:
        hits = [(v, 0.45) for v in near if within(term, v, 2)]
    return sorted(hits, key=lambda vw: (-vw[1], len(vw[0])))[:3]


def search(d, query, k1=1.4, b=0.55):
    idf, syn, designs = d["idf"], d["synonyms"], d["designs"]
    avgdl = sum(x["dl"] for x in designs) / len(designs)
    codes = {x["c"] for x in designs}

    # A two-letter code is the most precise thing anyone can type, and the
    # tokeniser's 3-character floor threw it away — "ny" matched nothing.
    typed_codes = {w.upper() for w in query.replace(",", " ").split()
                   if w.upper() in codes}

    weights = {}
    for t in tokenize(query):
        # Synonyms fire whether or not the typed word is itself indexed. Gating
        # them on "is it in the vocabulary" meant "amber" could never reach
        # "gold" — the one case the bridge exists for. Fuzzy matching is the
        # last resort, only when neither the word nor any synonym lands.
        hit = False
        if t in idf:
            weights[t] = weights.get(t, 0) + 1.0
            hit = True
        for s in syn.get(t, []):
            if s in idf:
                weights[s] = max(weights.get(s, 0), 0.55)
                hit = True
        if not hit:
            for v, w in nearest(t, idf):
                weights[v] = max(weights.get(v, 0), w)

    q = [(t, w * idf[t]) for t, w in weights.items() if t in idf]
    if not q and not typed_codes:
        return []
    # Color, measured from the photograph rather than read out of a caption.
    # Scored by how much of the plate it covers, because that is what a person
    # remembers from a car going past: not the word, the area.
    cq, cidf = d.get("colorQuery", {}), d.get("colorIdf", {})
    wanted = {}
    words = query.lower().replace(",", " ").split()
    for raw in words:
        # A map, not a list of pairs: the builder switched to emitting
        # dictionaries so Swift could decode it, and this kept iterating it as
        # pairs — which unpacks the *keys* and throws on any query with a color
        # word in it.
        for name, weight in cq.get(raw, {}).items():
            wanted[name] = max(wanted.get(name, 0), weight)

    # How much color is allowed to matter depends on what else was typed.
    # "orange and black" is all a person has, so color decides it; "green plate
    # with a lighthouse" names a thing, and a lighthouse is far more identifying
    # than green. Letting color weigh the same in both put Colorado above
    # Mississippi for the lighthouse and cost 10 points of top-1 accuracy.
    content = [tokenize(w)[0] for w in words
               if w not in cq and tokenize(w)]
    distinct = max((idf.get(t, 0) for t in content), default=0.0)
    color_k = COLOR_WEIGHT / (1.0 + 1.6 * distinct)

    out = []
    for doc in designs:
        s = 0.0
        for t, w in q:
            f = doc["v"].get(t)
            if f:
                s += w * (f * (k1 + 1)) / (f + k1 * (1 - b + b * doc["dl"] / avgdl))
        for name, weight in wanted.items():
            cover = doc.get("col", {}).get(name, 0.0)
            if cover:
                s += color_k * weight * cover * cidf.get(name, 1.0)
        if doc["c"] in typed_codes:
            s += 10.0
        if s > 0:
            out.append((s, doc))
    return sorted(out, key=lambda x: -x[0])


def main():
    d = load()
    has_v2 = any("search_terms" for _ in [1]) and len(d["idf"])
    top1 = top3 = mrr = 0.0
    misses = []
    for query, gold in GOLD.items():
        ranked = search(d, query)
        codes = [doc["c"] for _, doc in ranked]
        if codes[:1] and codes[0] in gold:
            top1 += 1
        else:
            misses.append((query, codes[:3] or ["NONE"], sorted(gold)))
        if any(c in gold for c in codes[:3]):
            top3 += 1
        for i, c in enumerate(codes[:10], 1):
            if c in gold:
                mrr += 1 / i
                break
    n = len(GOLD)
    print(f"queries: {n}   terms in index: {len(d['idf'])}")
    print(f"  top-1 {top1 / n:.0%}   top-3 {top3 / n:.0%}   MRR {mrr / n:.3f}")
    if misses:
        print(f"\n  {len(misses)} not first:")
        for q, got, gold in misses:
            print(f"    {q!r:34} got {got} want {gold}")

    # Restraint counts too: a search that confidently answers a question the
    # corpus cannot answer is worse than one that says so.
    bad = [(q, search(d, q)[0][1]["c"]) for q in EMPTY_EXPECTED if search(d, q)]
    print(f"\n  should return nothing: {len(EMPTY_EXPECTED) - len(bad)}"
          f"/{len(EMPTY_EXPECTED)} correct")
    for q, got in bad:
        print(f"    {q!r} wrongly returned {got}")


if __name__ == "__main__":
    main()
