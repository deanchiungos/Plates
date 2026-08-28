#!/usr/bin/env python3
"""Builds a browsable gallery of the scraped plate history.

    python3 plate_browser.py ../research/plate-history.csv > ../research/plate-history.html

Then just open the file. It is a single self-contained page: no server, no build step,
no dependencies.

Two things it does that a spreadsheet cannot. It shows the *plates*, which is the whole
point of the dataset, and it shows each one's licence as a color, so "what can I
actually ship" is answerable by looking rather than by filtering a column.

The data is inlined as JSON rather than fetched from the CSV at runtime: a page opened
over file:// cannot fetch a sibling file without tripping CORS.

Images come from Wikimedia's thumbnailer rather than the originals. A few of these
photographs are several megabytes, and 3,300 of them would make the page unusable.
"""

import csv
import json
import re
import sys
import urllib.parse


def thumb(url, width=330):
    """Original Wikimedia URL -> its thumbnailer equivalent.

    .../commons/d/d1/Foo.jpg  ->  .../commons/thumb/d/d1/Foo.jpg/330px-Foo.jpg

    The width is not arbitrary. Wikimedia serves only a fixed set of thumbnail sizes
    now and returns 400 for anything else — 320px, the obvious guess, is not one of
    them and every image on the page came back broken. 330 is what the API itself
    hands back when asked for 320, so it is the nearest real size.

    SVGs have no smaller original to serve, so the thumbnailer rasterises them and the
    output is always .png regardless of the source extension.
    """
    m = re.match(r"(https://upload\.wikimedia\.org/wikipedia/[^/]+)/([0-9a-f])/([0-9a-f]{2})/(.+)$", url)
    if not m:
        return url
    base, a, b, name = m.groups()
    out = f"{base}/thumb/{a}/{b}/{name}/{width}px-{name}"
    return out + ".png" if name.lower().endswith(".svg") else out


def licence_class(lic):
    low = lic.lower()
    if "fair use" in low:
        return "bad"
    if "unresolved" in low or "none stated" in low:
        return "unknown"
    if re.search(r"cc[- ]by[- ]sa", low):
        return "share"
    if re.search(r"cc[- ]by", low):
        return "attrib"
    if re.search(r"public domain|^pd|cc0|cc-zero|wtfpl|no restrictions", low):
        return "free"
    return "unknown"


NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
    "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
    "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
    "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
    "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
    "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
    "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
    "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
    "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
    "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
    "ON": "Ontario", "QC": "Quebec", "BC": "British Columbia", "AB": "Alberta",
    "MB": "Manitoba", "SK": "Saskatchewan", "NS": "Nova Scotia",
    "NB": "New Brunswick", "NL": "Newfoundland and Labrador",
    "PE": "Prince Edward Island", "NT": "Northwest Territories", "YT": "Yukon",
    "NU": "Nunavut",
}
CANADA = {"ON", "QC", "BC", "AB", "MB", "SK", "NS", "NB", "NL", "PE", "NT", "YT", "NU"}

# Residual non-passenger rows. Down from 279 to a handful once the scraper stopped
# matching the "Non-passenger plates" heading, so this is now a backstop rather than a
# real filter. Flagged rather than dropped.
NON_PASSENGER = re.compile(
    r"\b(trailer|motorcycle|moped|dealer|commercial|truck|bus|taxi|apportioned"
    r"|police|firefighter|amateur radio|government|official|temporary|antique"
    r"|vanity|personali[sz]ed|disab)\b", re.I)

# For jurisdictions with no documented cutoff, a design first issued from this year on
# is taken to be still valid.
#
# This is the one guess in the whole classification, and it is deliberate. The scraped
# `street_legal` column left 4,005 of 4,302 rows as `unknown`, which is epistemically
# honest and useless: the question a spotter asks is "could this be on the road", and
# "no evidence either way" is not an answer to it. So every row gets a verdict.
#
# 2000 is chosen because states that reissue do so every 10-25 years, and the inferred
# cutoffs we *do* have for reissuing states cluster in exactly that window — New York
# 2001, West Virginia 2002, Kentucky 2005, Montana 2006, South Carolina 2008, Texas
# 2009, Oklahoma 2017, Kansas 2018. States that instead grandfather old plates have
# much earlier cutoffs (California 1963, New Jersey 1959) and are already documented,
# so they never fall through to this rule.
#
# Blast radius, measured rather than estimated: it is the sole reason 107 of 4,302 rows
# are called legal. Everything else is settled by documentation, by a jurisdiction's
# cutoff, or by being old enough that it is not a close call.
ASSUMED_VALID_FROM = 2000


def street_legal(row, cutoffs):
    """One question, one answer: could this plate be on a road today?

    Returns (legal, why). Ordered most authoritative first.
    """
    code, note = row["code"], (row.get("validity_note") or "").strip()
    state = row.get("street_legal", "unknown")

    if row["is_current"] == "1":
        return True, "Issued today"
    if state == "valid":
        return True, note or "Retired, but documented as still valid"
    if state == "expiring":
        return True, note or "Being phased out, still legal for now"
    if state == "likely":
        return True, note or "Within the range this jurisdiction still honours"

    year = start_year(row.get("first_issued") or row.get("dates_issued"))
    if year is None:
        return False, "No issue date, so nothing to judge it on"

    if code in cutoffs:
        cut, basis, evidence = cutoffs[code]
        if year >= cut:
            return True, evidence if basis == "stated" else \
                f"{code} plates from {cut} on appear to still be valid"
        return False, f"Predates {code}'s {cut} cutoff"

    if year >= ASSUMED_VALID_FROM:
        return True, ("Issued since 2000 and no reissue is documented for "
                      f"{code} — assumed still valid")
    return False, f"No reissue documented for {code}; too old to assume it survived"


YEAR_RE = re.compile(r"\b(1[89]\d{2}|20[0-4]\d)\b")


def start_year(text):
    m = YEAR_RE.search(text or "")
    return int(m.group(1)) if m else None


def load_cutoffs(path):
    try:
        return {r["code"]: (int(r["cutoff_year"]), r["basis"], r["evidence"])
                for r in csv.DictReader(open(path))}
    except OSError:
        sys.stderr.write(f"warning: no cutoffs at {path}; falling back to the "
                         f"{ASSUMED_VALID_FROM} rule everywhere\n")
        return {}


def load_captions(path):
    """Vision-written design captions from plate_vision.py, keyed by image URL.

    Keyed by image rather than by row on purpose: rows that share a photograph share a
    design, so they should share its caption instead of paying to describe it twice.
    Absent file is normal — the browser predates the captions and still works without
    them.
    """
    try:
        out = {}
        for r in csv.DictReader(open(path)):
            if not r.get("caption"):
                continue
            spec = " · ".join(x for x in (r.get("base"), r.get("serial_color"),
                                          r.get("finish"), r.get("typeface")) if x)
            # Legends are quoted separately rather than folded into `spec`: they're
            # the plate's own words, not a design attribute like color or finish, and
            # they deserve quote marks rather than a dot-separated run-on.
            legends = " / ".join(f'"{x}"' for x in
                                 (r.get("top_legend"), r.get("bottom_legend")) if x)
            out[r["url"]] = (r["caption"], spec, legends, r.get("caveat", ""))
        return out
    except OSError:
        return {}


def main(path, cutoff_path=None):
    cutoffs = load_cutoffs(
        cutoff_path or path.replace("plate-history.csv", "plate-validity-cutoffs.csv"))
    captions = load_captions(
        path.replace("plate-history.csv", "plate-descriptions.csv"))

    rows = list(csv.DictReader(open(path)))
    data = []
    for r in rows:
        legal, why = street_legal(r, cutoffs)
        cap, spec, legends, caveat = captions.get(r["image_url"].strip(), ("", "", "", ""))
        data.append({
            # The written-from-the-photograph caption, and the structured spec line
            # underneath it. Wikipedia's own description is kept as `d` rather than
            # overwritten: it is the provenance, and on the ~2% of readings the model
            # flags as low-confidence it is the better of the two.
            "vd": cap,
            "vs": spec,
            "vl": legends,
            "vc": caveat,
            "c": r["code"],
            "y": r["first_issued"],
            "dt": r["dates_issued"],
            "cur": 1 if r["is_current"] == "1" else 0,
            "sl": 1 if legal else 0,
            "sn": why,
            "d": r["description"],
            "t": thumb(r["image_url"]) if r["image_url"] else "",
            "l": r["licence"],
            "k": licence_class(r["licence"]),
            "a": r["credit"],
            "o": r.get("image_origin", ""),
            # Why this row is showing a picture that is not its own. Wikipedia says
            # "same design as above" by spanning a Design cell or by opening the
            # description "As above, but with…", and the borrowed picture is then
            # correct — but the card has to say so, because "which plate am I actually
            # looking at" is the question this whole file exists to answer.
            "w": r.get("image_note", ""),
            "f": "https://commons.wikimedia.org/wiki/File:"
                 + urllib.parse.quote(r["image_file"].replace(" ", "_")),
            "s": r["source_page"],
            # Wikipedia drops a blank plate outline into table cells where it has no
            # photograph. These are not designs. The count is printed at build time
            # rather than written down here: it was 63 when this was first noted and
            # is an order of magnitude larger now, so any number in a comment is a
            # number that will be wrong.
            "p": 1 if "blank license plate shape" in r["image_file"].lower() else 0,
            # Filename only. Matching the description too hid Vermont's *current*
            # passenger plate, whose note happens to read "intermingled with truck,
            # municipal and (large) trailer plates" — along with four other current
            # designs. A keyword in a note is not a statement about the plate.
            "n": 1 if NON_PASSENGER.search(r["image_file"]) else 0,
        })
    data.sort(key=lambda x: (x["c"] not in CANADA, NAMES.get(x["c"], x["c"]),
                             x["y"] or "0000"))

    names = {k: v for k, v in NAMES.items() if any(d["c"] == k for d in data)}

    # Everything in the subtitle is measured. It used to hard-code "65 jurisdictions
    # · 1903-2026", which was true when written and is exactly the kind of thing that
    # silently stops being true after the next scrape.
    years = [int(d["y"]) for d in data if d["y"].isdigit()]
    span = f"{min(years)}&ndash;{max(years)}" if years else "no dated designs"
    blank = sum(1 for d in data if d["p"] or not d["t"])

    sys.stderr.write(
        f"{len(data)} rows, {len(names)} jurisdictions, {span.replace('&ndash;', '-')}; "
        f"{blank} without a photograph "
        f"({sum(1 for d in data if d['p'])} placeholder outlines, "
        f"{sum(1 for d in data if not d['t'])} with no image at all)\n")

    print(PAGE.replace("__DATA__", json.dumps(data, separators=(",", ":")))
              .replace("__NAMES__", json.dumps(names, separators=(",", ":")))
              .replace("__PLACES__", str(len(names)))
              .replace("__SPAN__", span)
              .replace("__BLANK__", str(blank))
              .replace("__TOTAL__", str(len(data))))


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Plate design history</title>
<style>
  :root {
    --bg:#f4f6f9; --card:#fff; --ink:#16202e; --muted:#6b7a8d; --line:#dde3ea;
    --free:#1f9d55; --share:#c47f17; --attrib:#2f6fd0; --bad:#c62828; --unknown:#8a8a8a;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#11161d; --card:#1a222c; --ink:#e8edf3; --muted:#93a1b3; --line:#2b3644; }
  }
  * { box-sizing:border-box }
  body { margin:0; background:var(--bg); color:var(--ink);
         font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif }
  header { position:sticky; top:0; z-index:10; background:var(--bg);
           border-bottom:1px solid var(--line); padding:14px 20px 12px }
  h1 { margin:0 0 3px; font-size:19px; letter-spacing:-.2px }
  .sub { color:var(--muted); font-size:12.5px }
  .controls { display:flex; flex-wrap:wrap; gap:8px; margin-top:11px; align-items:center }
  input, select { font:inherit; font-size:13.5px; padding:7px 10px; border-radius:9px;
                  border:1px solid var(--line); background:var(--card); color:var(--ink) }
  input[type=search] { min-width:230px; flex:1 1 230px }
  label.chk { display:inline-flex; align-items:center; gap:6px; font-size:13px;
              color:var(--muted); cursor:pointer; user-select:none }
  main { padding:18px 20px 60px }
  h2 { font-size:16px; margin:26px 0 4px; scroll-margin-top:130px }
  h2 .n { color:var(--muted); font-weight:400; font-size:13px; margin-left:7px }
  .grid { display:grid; gap:12px;
          grid-template-columns:repeat(auto-fill,minmax(210px,1fr)) }
  .card { background:var(--card); border:1px solid var(--line); border-radius:12px;
          overflow:hidden; display:flex; flex-direction:column }
  .card img { width:100%; aspect-ratio:2/1; object-fit:contain; background:#fff;
              display:block }
  .meta { padding:8px 10px 10px; font-size:12px; flex:1;
          display:flex; flex-direction:column; gap:3px }
  .yr { font-weight:700; font-size:13px }
  .now, .ok, .soon, .maybe { font-size:9px; font-weight:800; color:#fff;
         padding:1px 5px; border-radius:20px; vertical-align:2px; white-space:nowrap }
  .now { background:var(--free) }
  .ok { background:var(--attrib) }
  .soon { background:var(--share) }
  .maybe { background:transparent; color:var(--attrib); border:1px solid var(--attrib) }
  .desc { color:var(--muted); line-height:1.35 }
  /* The written caption is the card's headline now, so it gets the readable ink.
     The spec line under it is the structured fields, which are for scanning down a
     column rather than reading, hence the smaller size and the tabular color. */
  .desc.vis { color:var(--ink) }
  /* Legends are the plate's own words, so they read as quoted speech rather than as
     the muted metadata tone the spec line uses underneath them. */
  .legend { color:var(--ink); font-size:11.5px; font-style:italic; margin-top:4px; line-height:1.3 }
  .spec { color:var(--muted); font-size:10.5px; margin-top:3px; line-height:1.3 }
  .caveat { color:#a2700f; font-size:10.5px; margin-top:3px; line-height:1.3 }
  @media (prefers-color-scheme: dark) { .caveat { color:#d9a441 } }
  .foot { margin-top:auto; padding-top:6px; display:flex; align-items:center;
          gap:6px; flex-wrap:wrap }
  .lic { font-size:10.5px; font-weight:700; padding:2px 7px; border-radius:20px;
         color:#fff; white-space:nowrap }
  .free{background:var(--free)} .share{background:var(--share)}
  .attrib{background:var(--attrib)} .bad{background:var(--bad)}
  .unknown{background:var(--unknown)}
  a { color:inherit; text-decoration:none; border-bottom:1px dotted var(--muted);
      font-size:11px; color:var(--muted) }
  a:hover { color:var(--ink) }
  .empty { color:var(--muted); padding:40px 0; text-align:center }
  .origin { font-size:10px; font-weight:700; color:var(--attrib); letter-spacing:.2px }
  /* Louder than .origin on purpose: this is the card admitting the picture belongs to
     a different row, which is the thing you most need to notice before trusting it. */
  .borrowed { font-size:10.5px; line-height:1.35; color:#92400e; background:#fffbeb;
              border:1px solid #fde68a; border-radius:6px; padding:4px 6px; margin-top:6px }
  .noimg { aspect-ratio:2/1; display:flex; align-items:center; justify-content:center;
           background:var(--bg); color:var(--muted); font-size:11px }
  .gap { font-size:34px; font-weight:800; color:var(--line);
         border:2px dashed var(--line) }
  .legend { font-size:11.5px; color:var(--muted); margin-top:8px }
  .legend b { padding:1px 6px; border-radius:20px; color:#fff; font-weight:700 }
</style></head><body>
<header>
  <h1>Plate design history</h1>
  <div class="sub"><span id="shown">__TOTAL__</span> of __TOTAL__ rows ·
      __PLACES__ jurisdictions · __SPAN__ · scraped from Wikipedia<br>
      <b>__BLANK__ have no photograph</b> — a blank outline or nothing at all.
      They are still rows, so the totals above are not a count of viewable designs.</div>
  <div class="controls">
    <input type="search" id="q" placeholder="Search description, year, credit&hellip;">
    <select id="place"><option value="">All jurisdictions</option></select>
    <select id="sl">
      <option value="">Street legal: any</option>
      <option value="1">Street legal</option>
      <option value="0">Not street legal</option>
    </select>
    <select id="lic">
      <option value="">Any photo licence</option>
      <option value="free">No credit needed (PD / CC0)</option>
      <option value="share">CC BY-SA (credit + share-alike)</option>
      <option value="attrib">CC BY (credit)</option>
      <option value="bad">Tagged non-free</option>
      <option value="unknown">Unresolved</option>
    </select>
    <input type="number" id="from" placeholder="From" style="width:88px">
    <input type="number" id="to" placeholder="To" style="width:88px">
    <label class="chk"><input type="checkbox" id="pass" checked> Passenger plates only</label>
    <label class="chk"><input type="checkbox" id="cur"> Current design only</label>
    <label class="chk"><input type="checkbox" id="gapsonly"> Missing image only</label>
    <label class="chk"><input type="checkbox" id="ext"> Non-Wikipedia sources only</label>
  </div>
  <div class="legend">
    <b class="now">STREET LEGAL</b> could be on a road today &mdash; hover it for why ·
    no badge = retired<br>
    Licence badges describe the <b style="background:none;color:inherit">photograph</b>, not the plate design &mdash;
    <b class="free">PD/CC0</b> no credit ·
    <b class="share">CC BY-SA</b> credit + share-alike ·
    <b class="attrib">CC BY</b> credit ·
    <b class="bad">non-free</b> uploader&rsquo;s view of the <i>design</i>, see notes ·
    <b class="unknown">?</b> unresolved
  </div>
</header>
<main id="out"></main>
<script>
const DATA = __DATA__, NAMES = __NAMES__;
const out = document.getElementById('out');
const place = document.getElementById('place');
Object.keys(NAMES).sort((a,b)=>NAMES[a].localeCompare(NAMES[b])).forEach(k=>{
  const o=document.createElement('option'); o.value=k; o.textContent=NAMES[k]+' ('+k+')';
  place.appendChild(o);
});

function esc(s){ return (s||'').replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function render(){
  const q = document.getElementById('q').value.trim().toLowerCase();
  const p = place.value, lk = document.getElementById('lic').value;
  const passOnly = document.getElementById('pass').checked;
  const curOnly = document.getElementById('cur').checked;
  const gapsOnly = document.getElementById('gapsonly').checked;
  const sl = document.getElementById('sl').value;
  const extOnly = document.getElementById('ext').checked;
  const from = parseInt(document.getElementById('from').value)||0;
  const to = parseInt(document.getElementById('to').value)||9999;

  const hits = DATA.filter(d=>{
    if (p && d.c!==p) return false;
    if (lk && d.k!==lk) return false;
    if (passOnly && d.n) return false;
    if (curOnly && !d.cur) return false;
    if (gapsOnly && (d.t && !d.p)) return false;
    if (extOnly && (!d.o || d.o === 'wikimedia')) return false;
    if (sl !== '' && d.sl !== +sl) return false;
    const y = parseInt(d.y)||0;
    if (d.y && (y<from||y>to)) return false;
    if (!d.y && (from>0||to<9999)) return false;
    if (q && !((d.d+' '+d.vd+' '+d.vl+' '+d.vs+' '+d.dt+' '+d.y+' '+d.a+' '+NAMES[d.c]+' '+d.c).toLowerCase().includes(q))) return false;
    return true;
  });

  document.getElementById('shown').textContent = hits.length;
  if (!hits.length){ out.innerHTML='<div class="empty">Nothing matches.</div>'; return; }

  // Counted once instead of rescanning every hit for each group. At 4,300 rows and
  // 65 groups the old `hits.filter(...)` per heading was a measurable share of a
  // render that already runs on every keystroke.
  const counts = new Map();
  for (const d of hits) counts.set(d.c, (counts.get(d.c)||0) + 1);

  let h='', last=null;
  for (const d of hits){
    const hasImg = d.t && !d.p;
    if (d.c!==last){
      if (last!==null) h+='</div>';
      h += '<h2 id="'+d.c+'">'+esc(NAMES[d.c]||d.c)+'<span class="n">'+counts.get(d.c)+' rows</span></h2><div class="grid">';
      last = d.c;
    }
    h += '<div class="card">'
      +  (hasImg ? '<img loading="lazy" src="'+esc(d.t)+'" alt="'+esc(d.c+' '+d.y)+'"'
              + ' onerror="this.replaceWith(Object.assign(document.createElement(\'div\'),'
              + '{className:\'noimg gap\',textContent:\'?\'}))">'
              : '<div class="noimg gap">?</div>')
      +  '<div class="meta"><div class="yr">'+esc(d.dt||d.y||'date unknown')
      +  (d.sl ? ' <span class="now" title="'+esc(d.sn)+'">STREET LEGAL</span>' : '')
      +  '</div>'
      // The caption is the one written from the photograph where we have it. The
      // scraped description stays reachable on hover rather than stacked underneath,
      // because two descriptions of one plate is what made this page hard to read.
      +  (d.vd ? '<div class="desc vis" title="'+esc(d.d||'')+'">'+esc(d.vd)+'</div>'
                 + (d.vl ? '<div class="legend">'+esc(d.vl)+'</div>' : '')
                 + (d.vs ? '<div class="spec">'+esc(d.vs)+'</div>' : '')
                 + (d.vc ? '<div class="caveat">'+esc(d.vc)+'</div>' : '')
               : '<div class="desc">'+esc(d.d||'')+'</div>')
      // The licence describes the photograph. With no photograph there is nothing
      // for it to describe, and a green "Public domain" badge on a blank outline
      // reads as "here is a free image you can ship" — the exact opposite of true.
      +  '<div class="foot">'
      +  (hasImg ? '<span class="lic '+d.k+'">'+esc(d.l)+'</span>'
                 : '<span class="lic unknown">no photograph</span>')
      +  '<a href="'+esc(d.f)+'" target="_blank" rel="noreferrer">file</a>'
      +  '<a href="'+esc(d.s)+'" target="_blank" rel="noreferrer">article</a></div>'
      +  (d.w ? '<div class="borrowed">'+esc(d.w)+'</div>'
             : d.o && d.o!=='wikimedia' ? '<div class="origin">via '+esc(d.o)+'</div>' : '')
      +  (d.a ? '<div class="desc" style="font-size:10.5px">'+esc(d.a)+'</div>' : '')
      +  '</div></div>';
  }
  out.innerHTML = h + '</div>';
}

// Typed input is debounced; a full unfiltered render is ~120ms and firing it on
// every keystroke made the search box stutter. Selects and checkboxes are one
// deliberate action each, so they run immediately.
let timer = null;
const soon = () => { clearTimeout(timer); timer = setTimeout(render, 110); };

['q','place','lic','sl','from','to','pass','cur','gapsonly','ext'].forEach(id=>{
  const el=document.getElementById(id);
  const typed = el.type!=='checkbox' && el.tagName!=='SELECT';
  el.addEventListener(typed ? 'input' : 'change', typed ? soon : render);
});
render();
</script></body></html>
"""


if __name__ == "__main__":
    main(*sys.argv[1:3]) if len(sys.argv) > 1 else main("../research/plate-history.csv")
