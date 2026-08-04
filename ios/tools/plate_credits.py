#!/usr/bin/env python3
"""Fill the attribution gaps `plate-history.csv` cannot cover.

Most photographs in the description corpus came in through the history scrape,
which carries a licence and a photographer for each one. Some did not — they were
added later, or from a different pass — and those arrive with no licence recorded
at all. That is not a cosmetic gap: the great majority of these are Wikimedia
Commons uploads under CC BY or CC BY-SA, where naming the photographer is a
condition of using the picture, and "we could not find it" is not one of the
permitted exceptions.

So this asks the wikis directly, for exactly the files nothing else knows about,
and writes what they say to research/plate-image-credits.csv. plate_lookup_build.py
reads that alongside the history sheet. Rerunning is cheap and idempotent: files
already resolved are skipped unless --refresh is passed.

Queries are batched 40 titles at a time. One request per file earns an HTTP 429
about ten files in, which is fair enough — it is the same answer asked thirty ways.

    python3 ios/tools/plate_credits.py [--refresh]
"""
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DESCRIPTIONS = os.path.join(REPO, "research", "plate-descriptions.csv")
HISTORY = os.path.join(REPO, "research", "plate-history.csv")
OUT = os.path.join(REPO, "research", "plate-image-credits.csv")

ENDPOINTS = {
    "commons": "https://commons.wikimedia.org/w/api.php",
    "en": "https://en.wikipedia.org/w/api.php",
}
BATCH = 40
USER_AGENT = "PlatesApp/1.0 (offline licence-plate reference; attribution lookup)"

FIELDS = ["file", "credit", "licence", "attribution_required", "source"]


def strip_markup(html):
    """Commons returns the author as a link. The name is the part that matters."""
    text = re.sub(r"<[^>]+>", "", html or "")
    return " ".join(text.split()).strip()


def image_name(url):
    """The filename, decoded and normalised the way MediaWiki normalises titles.

    Underscores and spaces are the same character to a wiki title, and the API
    hands responses back with spaces however the request was spelled. Keying on
    the raw filename meant every single answer looked like a miss.
    """
    return urllib.parse.unquote(os.path.basename(url)).replace("_", " ").strip()


def known_files():
    """Filenames the history sheet already has a licence for."""
    out = set()
    if not os.path.exists(HISTORY):
        return out
    for row in csv.DictReader(open(HISTORY)):
        url = (row.get("image_url") or "").strip()
        if url and (row.get("licence") or "").strip():
            out.add(image_name(url))
    return out


def load_existing():
    if not os.path.exists(OUT):
        return {}
    return {r["file"]: r for r in csv.DictReader(open(OUT))}


def query(site, titles):
    params = {
        "action": "query",
        "prop": "imageinfo",
        "iiprop": "extmetadata",
        "titles": "|".join("File:" + t for t in titles),
        "format": "json",
        "formatversion": "2",
    }
    request = urllib.request.Request(
        ENDPOINTS[site] + "?" + urllib.parse.urlencode(params),
        headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=40) as response:
        return json.load(response)


def rows_from(site, titles):
    """One batched request -> a row per file the wiki actually knows."""
    try:
        data = query(site, titles)
    except urllib.error.HTTPError as error:
        print(f"  {site}: HTTP {error.code} on a batch of {len(titles)}")
        return {}
    out = {}
    for page in data.get("query", {}).get("pages", []):
        title = page.get("title", "")
        name = (title.split(":", 1)[1] if ":" in title else title).replace("_", " ").strip()
        info = page.get("imageinfo")
        if not info:
            continue
        meta = info[0].get("extmetadata", {})
        credit = strip_markup(meta.get("Artist", {}).get("value", ""))
        # A broken author template renders as the literal placeholder. A wrong
        # credit is worse than a missing one, so it is dropped and the Flickr
        # source line below stands in where there is one.
        if credit in {"{{{1}}}", "", "-"} or len(credit) > 70:
            source = strip_markup(meta.get("Credit", {}).get("value", ""))
            credit = source if source.lower().startswith("flickr") else ""
        out[name] = {
            "file": name,
            "credit": credit,
            "licence": strip_markup(meta.get("LicenseShortName", {}).get("value", "")),
            "attribution_required":
                strip_markup(meta.get("AttributionRequired", {}).get("value", "")),
            "source": site,
        }
    return out


def main():
    refresh = "--refresh" in sys.argv

    covered = known_files()
    existing = {} if refresh else load_existing()

    wanted = {}          # filename -> site to ask
    for row in csv.DictReader(open(DESCRIPTIONS)):
        url = (row.get("url") or "").strip()
        if not url or not url.startswith("http"):
            continue
        name = image_name(url)
        if name in covered or name in existing:
            continue
        wanted[name] = "en" if "/wikipedia/en/" in url else "commons"

    if not wanted:
        print(f"nothing to look up — {len(existing)} already in {os.path.basename(OUT)}")
        return

    print(f"{len(wanted)} photos with no licence anywhere; asking the wikis")

    found = dict(existing)
    for site in ("commons", "en"):
        titles = [n for n, s in wanted.items() if s == site]
        # A file linked from en.wikipedia is very often hosted on Commons, so
        # anything en cannot answer gets a second pass there.
        for start in range(0, len(titles), BATCH):
            chunk = titles[start:start + BATCH]
            found.update(rows_from(site, chunk))
            time.sleep(1.0)

    retry = [n for n in wanted if n not in found and wanted[n] == "en"]
    for start in range(0, len(retry), BATCH):
        found.update(rows_from("commons", retry[start:start + BATCH]))
        time.sleep(1.0)

    with open(OUT, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDS)
        writer.writeheader()
        for name in sorted(found):
            writer.writerow(found[name])

    unresolved = [n for n in wanted if n not in found]
    print(f"resolved {len(found) - len(existing)} of {len(wanted)} -> {OUT}")
    if unresolved:
        print(f"  {len(unresolved)} still unknown (hosted nowhere the API can see):")
        for name in unresolved:
            print(f"    {name}")


if __name__ == "__main__":
    main()
