#!/usr/bin/env python3
"""A local page for reviewing the 63 generated plate tiles.

Four things it lets you do without touching Xcode:
  - retype the tile label ("Mass." reads oddly, want "Massachusetts")
  - drag the code/name block to wherever it should actually sit, viewed at the
    exact point size and font the Game grid renders it in
  - flag a design and write a note on why, for later
  - drag a per-plate slider that dims the art toward whichever of black/white
    increases contrast, so text-visibility problems can be judged by eye
    rather than argued about in the abstract

Every edit autosaves to dev/research/plate-review.json as you make it — there is
no separate save step. Nothing here touches the app. Run

    python3 ios/tools/plate_art_assets.py build

afterward to fold the results in: tile-label edits into Plate.swift, position
and dim into PlateArtwork.swift, flagged notes into dev/research/plate-flags.md.

    python3 ios/tools/plate_review_server.py
    # open http://localhost:8770
"""
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLATE_SWIFT = os.path.join(REPO, "ios", "Plates", "Domain", "Plate.swift")
ARTWORK_SWIFT = os.path.join(REPO, "ios", "Plates", "Design", "PlateArtwork.swift")
THEME_SWIFT = os.path.join(REPO, "ios", "Plates", "Design", "Theme.swift")
CATALOG = os.path.join(REPO, "ios", "Plates", "Assets.xcassets", "PlateArt")
REVIEW_JSON = os.path.join(REPO, "dev", "research", "plate-review.json")
# The exact file Theme.PlateFont.condensed resolves to on-device (confirmed via
# `system_profiler SPFontsDataType`) — served straight to the page so the type
# in the browser is the same face at the same weight, not a CSS approximation.
FONT_PATH = "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf"
PORT = 8770


def parse_plates():
    """code -> (name, short, group) in source order, three groups worth."""
    src = open(PLATE_SWIFT).read()
    groups = {"states": "States", "bonus": "Bonus", "provinces": "Canada"}
    out = []
    for var, label in groups.items():
        m = re.search(rf"static let {var}: \[Plate\] = \[(.*?)\n    \]", src, re.S)
        for line in m.group(1).splitlines():
            e = re.search(r'code: "(\w+)".*?name: "([^"]*)".*?short: "([^"]*)"', line)
            if e:
                out.append({"code": e.group(1), "name": e.group(2),
                           "short": e.group(3), "group": label})
    return out


def parse_artwork():
    """code -> {ink, field, halo, scrim, offsetX, offsetY} from the generated Swift."""
    src = open(ARTWORK_SWIFT).read()
    out = {}
    for m in re.finditer(
        r'"(\w+)": Entry\(ink: 0x([0-9A-Fa-f]+), field: 0x([0-9A-Fa-f]+), '
        r'halo: (true|false), scrim: ([\d.]+), '
        r'offsetX: (-?[\d.]+), offsetY: (-?[\d.]+)\)', src
    ):
        code, ink, field, halo, scrim, ox, oy = m.groups()
        out[code] = {"ink": int(ink, 16), "field": int(field, 16),
                     "halo": halo == "true", "scrim": float(scrim),
                     "offsetX": float(ox), "offsetY": float(oy)}
    return out


def parse_tile_metrics():
    """(tileMinWidth, tileAspect) straight from Theme.swift.

    Read rather than hard-coded so "true size" in this tool cannot silently
    drift from whatever the app actually uses.
    """
    src = open(THEME_SWIFT).read()
    w = float(re.search(r"tileMinWidth: CGFloat = ([\d.]+)", src).group(1))
    num, den = re.search(r"tileAspect: CGFloat = ([\d.]+) / ([\d.]+)", src).groups()
    return w, float(num) / float(den)


def load_review():
    if os.path.exists(REVIEW_JSON):
        return json.load(open(REVIEW_JSON))
    return {}


def save_review(data):
    os.makedirs(os.path.dirname(REVIEW_JSON), exist_ok=True)
    # Keep it minimal and diffable: an entry survives only if it still differs
    # from doing nothing, so closing a tile's flag or re-centring its text
    # makes the file shrink instead of accumulating dead overrides forever.
    clean = {code: v for code, v in data.items()
             if v.get("short") or v.get("flagged") or v.get("note") or
                v.get("scrim", 0) > 0 or v.get("offsetX", 0) or v.get("offsetY", 0)}
    json.dump(clean, open(REVIEW_JSON, "w"), indent=2, sort_keys=True)
    return clean


PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<title>Plate review</title>
<style>
  @font-face { font-family: 'DINCondensedBoldLocal'; src: local('DIN Condensed Bold'),
               url('/font.ttf') format('truetype'); font-weight: 700; }
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, system-ui, sans-serif; background: #f2f2f4;
         margin: 0; padding: 24px; color: #1a1a1a; }
  h1 { font-size: 20px; margin: 0 0 2px; }
  .sub { color: #666; font-size: 13px; margin-bottom: 20px; }
  .sub b { color: #1a1a1a; }
  h2 { font-size: 14px; text-transform: uppercase; letter-spacing: 0.04em;
       color: #888; margin: 28px 0 10px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
          gap: 14px; }
  .card { background: #fff; border-radius: 10px; padding: 10px;
          box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
  .card.flagged { outline: 2px solid #e0483e; }

  .stage { display: flex; align-items: flex-end; gap: 10px; }
  .big-wrap { flex: 1; }
  .truewrap { text-align: center; }
  .truewrap .caption { font-size: 9px; color: #999; margin-top: 3px; }

  .tile { position: relative; aspect-ratio: __ASPECT__; border-radius: 7px;
          overflow: hidden; background: #ddd; user-select: none; }
  .tile.big { cursor: grab; touch-action: none; }
  .tile.big:active { cursor: grabbing; }
  .tile.true { width: __TRUEW__px; border-radius: __TRUER__px; box-shadow: 0 0 0 1px #ccc; }
  .tile img { position: absolute; inset: 0; width: 100%; height: 100%;
              object-fit: cover; pointer-events: none; }
  .tile .scrim { position: absolute; inset: 0; pointer-events: none; }
  .tile .label { position: absolute; display: flex; flex-direction: column;
                 align-items: center; justify-content: center; text-align: center;
                 font-family: 'DINCondensedBoldLocal', 'Arial Narrow', sans-serif;
                 font-weight: 700; left: 50%; top: 50%;
                 transform: translate(calc(-50% + var(--dx, 0px)), calc(-50% + var(--dy, 0px))); }
  .tile.big .label { pointer-events: none; }
  .tile .code { letter-spacing: 0.4px; white-space: nowrap; }
  .tile .short { letter-spacing: 0.6px; opacity: 0.72; text-transform: uppercase;
                 margin-top: 0.5px; white-space: nowrap; }

  .row { display: flex; align-items: center; gap: 6px; margin-top: 8px; font-size: 12px; }
  .row label { color: #666; width: 34px; flex-shrink: 0; }
  input[type=text] { flex: 1; font-size: 13px; padding: 3px 6px;
                      border: 1px solid #ccc; border-radius: 5px; }
  input[type=range] { flex: 1; }
  .pct { width: 30px; text-align: right; color: #888; font-variant-numeric: tabular-nums; }

  .posrow { display: flex; align-items: center; gap: 8px; margin-top: 8px; font-size: 11px;
            color: #888; }
  .posrow .coords { font-variant-numeric: tabular-nums; }
  .posrow button { font-size: 11px; padding: 3px 8px; border: 1px solid #ccc;
                    border-radius: 5px; background: #f7f7f7; cursor: pointer; }
  .posrow button:hover { background: #eee; }

  textarea { width: 100%; box-sizing: border-box; font-size: 12px; margin-top: 6px;
             border: 1px solid #ccc; border-radius: 5px; padding: 5px; resize: vertical;
             min-height: 32px; display: none; font-family: inherit; }
  .card.flagged textarea { display: block; }
  .flagrow { display: flex; align-items: center; gap: 6px; margin-top: 8px; font-size: 12px; }
  .flagrow input[type=checkbox] { width: 15px; height: 15px; }
  .meta { font-size: 10px; color: #999; margin-top: 4px; }
  .saved { position: fixed; bottom: 16px; right: 16px; background: #1a1a1a; color: #fff;
           font-size: 12px; padding: 6px 12px; border-radius: 6px; opacity: 0;
           transition: opacity 0.2s; }
  .saved.show { opacity: 0.85; }
</style></head>
<body>
<h1>Plate review</h1>
<div class="sub"><b id="n">0</b> flagged &middot; drag the big tile to move the
  text, the small one next to it is the real __TRUEW__&times;__TRUEH__pt size
  &middot; edits autosave &middot; run <code>plate_art_assets.py build</code>
  to apply</div>
<div id="root"></div>
<div class="saved" id="saved">saved</div>
<script>
const DATA = __DATA__;
const TRUE_W = __TRUEW__, TRUE_H = __TRUEH__;   // pt, straight from Theme.swift
const CODE_SIZE = 19, NAME_SIZE = 19 * 7.5 / 19;  // pt, matches PlateLettering defaults
const BIG = 4.2;   // the working copy is this many times true size

function luminance(hex) {
  const ch = v => { v/=255; return v<=0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); };
  const r=(hex>>16)&255, g=(hex>>8)&255, b=hex&255;
  return 0.2126*ch(r)+0.7152*ch(g)+0.0722*ch(b);
}
function hexStr(h){ return '#'+h.toString(16).padStart(6,'0'); }
function embossShadow(color, strong) {
  const a1 = strong ? 0.90 : 0.40, a2 = strong ? 0.60 : 0.20;
  const r1 = strong ? 1.1 : 0.8,  r2 = strong ? 2.2 : 1.7;
  const c = hexStr(color);
  return `0 0 ${r1}px ${c}${Math.round(a1*255).toString(16).padStart(2,'0')},
          0 0 ${r2}px ${c}${Math.round(a2*255).toString(16).padStart(2,'0')}`;
}

let saveTimer = null;
function queueSave(code) {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => save(code), 350);
}
function save(code) {
  const c = document.getElementById('card-'+code);
  const st = state[code];
  const body = {
    code,
    short: c.querySelector('.f-short').value,
    flagged: c.querySelector('.f-flag').checked,
    note: c.querySelector('.f-note').value,
    scrim: parseFloat(c.querySelector('.f-scrim').value),
    offsetX: st.ox, offsetY: st.oy,
  };
  fetch('/save', {method:'POST', body: JSON.stringify(body)})
    .then(r => r.json())
    .then(() => {
      const s = document.getElementById('saved');
      s.classList.add('show');
      clearTimeout(s._t);
      s._t = setTimeout(() => s.classList.remove('show'), 900);
      updateCount();
    });
}
function updateCount() {
  document.getElementById('n').textContent =
    document.querySelectorAll('.card.flagged').length;
}

// Per-plate live position, independent of the DOM so big/true stay in sync
// and a save always sends the current value even mid-drag.
const state = {};

function applyLabel(code) {
  const st = state[code];
  ['big', 'true'].forEach(kind => {
    const label = document.querySelector(`#card-${code} .tile.${kind} .label`);
    if (!label) return;
    const w = kind === 'big' ? TRUE_W * BIG : TRUE_W;
    const h = kind === 'big' ? TRUE_H * BIG : TRUE_H;
    label.style.setProperty('--dx', (st.ox * w) + 'px');
    label.style.setProperty('--dy', (st.oy * h) + 'px');
  });
  document.querySelector(`#card-${code} .coords`).textContent =
    `x ${st.ox.toFixed(2)}  y ${st.oy.toFixed(2)}`;
}

function clamp(v) { return Math.max(-0.4, Math.min(0.4, v)); }

function wireDrag(code) {
  const big = document.querySelector(`#card-${code} .tile.big`);
  let dragging = null;
  big.addEventListener('pointerdown', e => {
    big.setPointerCapture(e.pointerId);
    dragging = { x: e.clientX, y: e.clientY, ox: state[code].ox, oy: state[code].oy };
  });
  big.addEventListener('pointermove', e => {
    if (!dragging) return;
    const rect = big.getBoundingClientRect();
    state[code].ox = clamp(dragging.ox + (e.clientX - dragging.x) / rect.width);
    state[code].oy = clamp(dragging.oy + (e.clientY - dragging.y) / rect.height);
    applyLabel(code);
  });
  const end = e => {
    if (!dragging) return;
    dragging = null;
    queueSave(code);
  };
  big.addEventListener('pointerup', end);
  big.addEventListener('pointercancel', end);
}

function nudge(code, dx, dy) {
  state[code].ox = clamp(state[code].ox + dx);
  state[code].oy = clamp(state[code].oy + dy);
  applyLabel(code);
  queueSave(code);
}

function tileHTML(p, kind) {
  const wide = kind === 'big';
  const sizeAttr = wide ? '' : 'true';
  const codePx = (kind === 'big' ? CODE_SIZE * BIG : CODE_SIZE);
  const namePx = (kind === 'big' ? NAME_SIZE * BIG : NAME_SIZE);
  const shadow = p.embossColor !== null
    ? `text-shadow: ${embossShadow(p.embossColor, p.embossStrong)};` : '';
  return `
    <div class="tile ${wide ? 'big' : 'true'}">
      <img src="/img/${p.code}.png">
      <div class="scrim" data-scrim style="background:${hexStr(p.embossColor ?? 0)};opacity:${p.scrim}"></div>
      <div class="label" style="color:${hexStr(p.ink)};${shadow}">
        <div class="code" style="font-size:${codePx}px">${p.code}</div>
        <div class="short" style="font-size:${namePx}px">${p.short}</div>
      </div>
    </div>`;
}

function card(p) {
  state[p.code] = { ox: p.offsetX, oy: p.offsetY };
  const div = document.createElement('div');
  div.className = 'card' + (p.flagged ? ' flagged' : '');
  div.id = 'card-' + p.code;
  div.innerHTML = `
    <div class="stage">
      <div class="big-wrap">${tileHTML(p, 'big')}</div>
      <div class="truewrap">${tileHTML(p, 'true')}
        <div class="caption">true size</div>
      </div>
    </div>
    <div class="posrow">
      <span class="coords"></span>
      <button data-nudge="0,-0.02">&uarr;</button>
      <button data-nudge="0,0.02">&darr;</button>
      <button data-nudge="-0.02,0">&larr;</button>
      <button data-nudge="0.02,0">&rarr;</button>
      <button data-reset>center</button>
    </div>
    <div class="row">
      <label>text</label>
      <input type="text" class="f-short" value="${p.short.replace(/"/g,'&quot;')}">
    </div>
    <div class="row">
      <label>dim</label>
      <input type="range" class="f-scrim" min="0" max="0.8" step="0.02" value="${p.scrim}">
      <span class="pct">${Math.round(p.scrim*100)}%</span>
    </div>
    <div class="flagrow">
      <input type="checkbox" class="f-flag" ${p.flagged ? 'checked' : ''}>
      <span>flag for rework</span>
    </div>
    <textarea class="f-note" placeholder="why?">${p.note || ''}</textarea>
    <div class="meta">${p.name}</div>
  `;

  const shortInput = div.querySelector('.f-short');
  div.querySelectorAll('.label .short').forEach(el => {
    shortInput.addEventListener('input', () => {
      div.querySelectorAll('.label .short').forEach(s => s.textContent = shortInput.value);
      queueSave(p.code);
    });
  });

  const scrimInput = div.querySelector('.f-scrim');
  const pct = div.querySelector('.pct');
  scrimInput.addEventListener('input', () => {
    div.querySelectorAll('[data-scrim]').forEach(s => s.style.opacity = scrimInput.value);
    pct.textContent = Math.round(scrimInput.value * 100) + '%';
    queueSave(p.code);
  });

  const flag = div.querySelector('.f-flag');
  const note = div.querySelector('.f-note');
  flag.addEventListener('change', () => {
    div.classList.toggle('flagged', flag.checked);
    updateCount();
    queueSave(p.code);
  });
  note.addEventListener('input', () => queueSave(p.code));

  div.querySelectorAll('[data-nudge]').forEach(btn => {
    const [dx, dy] = btn.dataset.nudge.split(',').map(Number);
    btn.addEventListener('click', () => nudge(p.code, dx, dy));
  });
  div.querySelector('[data-reset]').addEventListener('click', () => {
    state[p.code].ox = 0; state[p.code].oy = 0;
    applyLabel(p.code);
    queueSave(p.code);
  });

  return div;
}

const root = document.getElementById('root');
const groups = {};
DATA.forEach(p => { (groups[p.group] ||= []).push(p); });
Object.entries(groups).forEach(([name, plates]) => {
  const h = document.createElement('h2');
  h.textContent = name;
  root.appendChild(h);
  const g = document.createElement('div');
  g.className = 'grid';
  plates.forEach(p => g.appendChild(card(p)));
  root.appendChild(g);
});
DATA.forEach(p => { wireDrag(p.code); applyLabel(p.code); });
updateCount();
</script>
</body></html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # the default access log is noise for a single-user local tool

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self._serve_page()
        elif self.path.startswith("/img/"):
            self._serve_image(self.path[len("/img/"):])
        elif self.path == "/font.ttf":
            self._serve_font()
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/save":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))
        review = load_review()
        code = body["code"]
        plates = {p["code"]: p for p in parse_plates()}
        baseline_short = plates.get(code, {}).get("short", "")
        entry = {
            "short": body.get("short", "") if body.get("short") != baseline_short else "",
            "flagged": bool(body.get("flagged")),
            "note": body.get("note", "").strip(),
            "scrim": round(float(body.get("scrim", 0)), 3),
            "offsetX": round(float(body.get("offsetX", 0)), 3),
            "offsetY": round(float(body.get("offsetY", 0)), 3),
        }
        review[code] = entry
        cleaned = save_review(review)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True, "kept": code in cleaned}).encode())

    def _serve_page(self):
        plates = parse_plates()
        artwork = parse_artwork()
        review = load_review()
        true_w, aspect = parse_tile_metrics()
        true_h = true_w / aspect
        rows = []
        for p in plates:
            art = artwork.get(p["code"])
            ov = review.get(p["code"], {})
            has_art = art is not None
            emboss_color = None
            emboss_strong = False
            if has_art:
                emboss_color = 0x000000 if luminance_py(art["ink"]) > 0.4 else 0xFFFFFF
                emboss_strong = art["halo"]
            rows.append({
                "code": p["code"], "name": p["name"], "group": p["group"],
                "short": ov.get("short") or p["short"],
                "flagged": ov.get("flagged", False),
                "note": ov.get("note", ""),
                "scrim": ov.get("scrim", art["scrim"] if has_art else 0),
                "offsetX": ov.get("offsetX", art["offsetX"] if has_art else 0),
                "offsetY": ov.get("offsetY", art["offsetY"] if has_art else 0),
                "ink": art["ink"] if has_art else 0x000000,
                "embossColor": emboss_color,
                "embossStrong": emboss_strong,
            })
        page = (PAGE.replace("__DATA__", json.dumps(rows))
                    .replace("__TRUEW__", f"{true_w:g}")
                    .replace("__TRUEH__", f"{true_h:.1f}")
                    .replace("__TRUER__", f"{true_w * 7 / 78:.1f}")
                    .replace("__ASPECT__", f"{aspect:.6f}"))
        body = page.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_image(self, name):
        if not re.fullmatch(r"[A-Za-z]{2,3}\.png", name):
            self.send_error(400)
            return
        code = name[:-4]
        path = os.path.join(CATALOG, f"{code}.imageset", f"{code}.png")
        if not os.path.exists(path):
            self.send_error(404)
            return
        data = open(path, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def _serve_font(self):
        if not os.path.exists(FONT_PATH):
            self.send_error(404)
            return
        data = open(FONT_PATH, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "font/ttf")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=86400")
        self.end_headers()
        self.wfile.write(data)


def luminance_py(hex_int):
    def ch(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (hex_int >> 16) & 0xFF, (hex_int >> 8) & 0xFF, hex_int & 0xFF
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def main():
    server = ThreadingHTTPServer(("localhost", PORT), Handler)
    print(f"plate review: http://localhost:{PORT}")
    print(f"autosaving to {REVIEW_JSON}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
