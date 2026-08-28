#!/usr/bin/env python3
"""Bakes CanadaMap.swift from a Natural Earth admin-1 shapefile.

Natural Earth is public domain, so the geometry can ship with no attribution
obligation. Run once and commit the output; nothing at runtime touches this.

    python3 canada_map.py ne_50m_admin_1_states_provinces > ../Plates/Domain/CanadaMap.swift

Same shape of pipeline as USMap: project, drop the specks, Douglas-Peucker down
to something a phone can draw every frame, then encode as integers on a 0..10000
grid with y already flipped so 0 is north.

No third-party modules on purpose — the shapefile and dBASE readers below are
about sixty lines together, which is cheaper than a dependency for a script that
runs once.
"""

import math
import struct
import sys

# Natural Earth's `postal` field, mapped to the codes Plate.swift already uses.
# Listed rather than trusted so a renamed or re-coded upstream feature fails loudly
# instead of silently dropping a province off the map.
WANTED = {
    "AB": "AB", "BC": "BC", "MB": "MB", "NB": "NB", "NL": "NL",
    "NS": "NS", "NT": "NT", "NU": "NU", "ON": "ON", "PE": "PE",
    "QC": "QC", "SK": "SK", "YT": "YT",
}

# EPSG:102001, Canada Albers Equal Area. Equal-area rather than conformal because
# the map is read as "how much of Canada is left", and Mercator would hand Nunavut
# half the frame.
LAT_1, LAT_2, LAT_0, LON_0 = 50.0, 70.0, 40.0, -96.0

TARGET_POINTS = 1600          # budget across every province
MIN_RING_SHARE = 0.004        # of the province's largest ring, by area


# --- dBASE III ---------------------------------------------------------------

def read_dbf(path):
    with open(path, "rb") as f:
        blob = f.read()
    count, header_len, record_len = struct.unpack_from("<IHH", blob, 4)

    fields, offset = [], 32
    while blob[offset] != 0x0D:
        name = blob[offset:offset + 11].split(b"\0")[0].decode("latin-1")
        length = blob[offset + 16]
        fields.append((name, length))
        offset += 32

    rows = []
    for i in range(count):
        base = header_len + i * record_len + 1     # +1 skips the deletion flag
        row, at = {}, base
        for name, length in fields:
            row[name] = blob[at:at + length].decode("latin-1").strip()
            at += length
        rows.append(row)
    return rows


# --- shapefile ---------------------------------------------------------------

def read_shp(path):
    """Yields one list-of-rings per record. Non-polygons come back empty."""
    with open(path, "rb") as f:
        blob = f.read()

    at, end = 100, len(blob)
    while at < end:
        _, words = struct.unpack_from(">II", blob, at)
        content, at = at + 8, at + 8 + words * 2
        if struct.unpack_from("<I", blob, content)[0] != 5:
            yield []
            continue

        n_parts, n_points = struct.unpack_from("<II", blob, content + 36)
        parts = struct.unpack_from("<%dI" % n_parts, blob, content + 44)
        pts_at = content + 44 + n_parts * 4
        pts = struct.unpack_from("<%dd" % (n_points * 2), blob, pts_at)
        xy = list(zip(pts[0::2], pts[1::2]))

        bounds = list(parts) + [n_points]
        yield [xy[bounds[i]:bounds[i + 1]] for i in range(n_parts)]


# --- projection --------------------------------------------------------------

def albers():
    p1, p2 = math.radians(LAT_1), math.radians(LAT_2)
    p0, l0 = math.radians(LAT_0), math.radians(LON_0)
    n = 0.5 * (math.sin(p1) + math.sin(p2))
    c = math.cos(p1) ** 2 + 2 * n * math.sin(p1)
    rho0 = math.sqrt(c - 2 * n * math.sin(p0)) / n

    def project(lon, lat):
        lam, phi = math.radians(lon), math.radians(lat)
        rho = math.sqrt(max(c - 2 * n * math.sin(phi), 0.0)) / n
        theta = n * (lam - l0)
        return rho * math.sin(theta), rho0 - rho * math.cos(theta)

    return project


# --- geometry ----------------------------------------------------------------

def ring_area(ring):
    total = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        total += x1 * y2 - x2 * y1
    return abs(total) / 2.0


def simplify(ring, tolerance):
    """Douglas-Peucker over an open run, with the closing point restored after."""
    closed = len(ring) > 2 and ring[0] == ring[-1]
    pts = ring[:-1] if closed else ring[:]
    if len(pts) < 3:
        return ring

    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]

    while stack:
        lo, hi = stack.pop()
        if hi <= lo + 1:
            continue
        ax, ay = pts[lo]
        bx, by = pts[hi]
        dx, dy = bx - ax, by - ay
        span = math.hypot(dx, dy) or 1e-12

        worst, at = -1.0, lo
        for i in range(lo + 1, hi):
            px, py = pts[i]
            d = abs(dy * (px - ax) - dx * (py - ay)) / span
            if d > worst:
                worst, at = d, i

        if worst > tolerance:
            keep[at] = True
            stack.append((lo, at))
            stack.append((at, hi))

    out = [p for p, k in zip(pts, keep) if k]
    if len(out) < 3:
        return None
    return out + [out[0]]


def main(stem):
    rows = read_dbf(stem + ".dbf")
    shapes = list(read_shp(stem + ".shp"))
    project = albers()

    regions = {}
    for row, rings in zip(rows, shapes):
        if row.get("adm0_a3") != "CAN" or not rings:
            continue
        code = WANTED.get(row.get("postal", ""))
        if code is None:
            print("skipping unmapped: %r" % row.get("name"), file=sys.stderr)
            continue
        regions.setdefault(code, []).extend(
            [[project(lon, lat) for lon, lat in ring] for ring in rings])

    missing = set(WANTED.values()) - set(regions)
    if missing:
        sys.exit("no geometry for %s" % ", ".join(sorted(missing)))

    # Drop the specks. The Arctic archipelago is thousands of islands and only the
    # handful you could name — Baffin, Victoria, Ellesmere, Banks — earn their points.
    for code, rings in regions.items():
        rings.sort(key=ring_area, reverse=True)
        floor = ring_area(rings[0]) * MIN_RING_SHARE
        regions[code] = [r for r in rings if ring_area(r) >= floor]

    # A first pass at a tolerance far below anything visible on a phone. Natural
    # Earth carries coastline detail measured in metres; dropping it here means the
    # bisection below runs over thousands of points instead of hundreds of thousands.
    for code, rings in regions.items():
        regions[code] = [s for s in (simplify(r, 2e-5) for r in rings) if s]
    print("after prepass: %d points"
          % sum(len(r) for rings in regions.values() for r in rings), file=sys.stderr)

    # One tolerance for the whole country, bisected to land on the point budget.
    # Per-province tolerances would simplify a shared border differently on each side
    # and open seams between neighbours.
    def total_at(tolerance):
        out, count = {}, 0
        for code, rings in regions.items():
            kept = [s for s in (simplify(r, tolerance) for r in rings) if s]
            out[code] = kept or [regions[code][0]]
            count += sum(len(r) for r in out[code])
        return out, count

    lo, hi = 0.0, 0.002
    simplified, count = total_at(hi)
    while count > TARGET_POINTS:
        hi *= 2
        simplified, count = total_at(hi)
    for _ in range(16):
        mid = (lo + hi) / 2
        candidate, count = total_at(mid)
        if count > TARGET_POINTS:
            lo = mid
        else:
            hi, simplified = mid, candidate
    simplified, count = total_at(hi)
    print("tolerance %.6f -> %d points" % (hi, count), file=sys.stderr)

    xs = [x for rings in simplified.values() for r in rings for x, _ in r]
    ys = [y for rings in simplified.values() for r in rings for _, y in r]
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)
    span_x, span_y = max_x - min_x, max_y - min_y

    # Each axis is stretched to fill 0...10000 independently, exactly as USMap does.
    # `aspect` carries the true proportion, and the drawing rect restores it — so a
    # single shared scale here would apply the aspect twice and squash the country.
    scale_x, scale_y = 10000.0 / span_x, 10000.0 / span_y

    def place(x, y):
        # y is subtracted: Albers y grows north, screen y grows south.
        return (round((x - min_x) * scale_x), round((max_y - y) * scale_y))

    encoded = {}
    for code, rings in simplified.items():
        encoded[code] = ";".join(
            " ".join("%d,%d" % place(x, y) for x, y in ring) for ring in rings)

    aspect = span_x / span_y
    print(TEMPLATE % (count, len(encoded), round(aspect, 4),
                      "\n".join('        "%s": "%s",' % (c, encoded[c])
                                for c in sorted(encoded))),
          end="")


TEMPLATE = '''import SwiftUI

/// Outlines of the ten provinces and three territories.
///
/// Source: Natural Earth `ne_50m_admin_1_states_provinces`, which is public domain
/// — no attribution obligation, unlike the Statistics Canada boundary files. Albers
/// equal-area, standard parallels 50N and 70N, then simplified with Douglas-Peucker
/// down to %d points across %d regions. Regenerate with `tools/canada_map.py`.
///
/// Equal-area, not conformal: the map answers "how much of Canada is left", and a
/// Mercator would hand Nunavut half the frame.
///
/// Same encoding as `USMap` — integers on a 0...10000 grid, y already flipped so 0
/// is north, rings separated by ';' and points by ' '. Fifteen hundred
/// `CGPoint(x:y:)` literals is the kind of expression that sends the Swift type
/// checker away for minutes; parsing a string at first use costs under a millisecond.
enum CanadaMap {

    /// Width over height of the whole layout.
    static let aspect: CGFloat = %s

    private static let encoded: [String: String] = [
%s
    ]
}
'''


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "ne_50m_admin_1_states_provinces")
