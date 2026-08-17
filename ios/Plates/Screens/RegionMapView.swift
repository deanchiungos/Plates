import SwiftUI

/// A baked outline table the map view can draw: `USMap`, `CanadaMap`.
///
/// Static requirements rather than instance ones, because the geometry is a constant
/// of the type — there is only ever one United States. The map view is generic over
/// this so the pinch-zoom, the pan clamping, the callout leader lines and the
/// inside-the-outline rarity banding exist once, not once per country.
protocol MapGeometry {
    /// Width over height of the whole layout, insets included.
    static var aspect: CGFloat { get }
    /// Draw order: largest first, so small regions land on top of their neighbours.
    static var codes: [String] { get }
    /// Rings per region, in unit coordinates, rather than one merged path each.
    /// The band has to be capped against the size of the shape it is drawn inside,
    /// and a merged path cannot tell Baffin Island from the whole of Nunavut.
    static var outlines: [String: [[CGPoint]]] { get }
    static func hitTest(_ point: CGPoint, in rect: CGRect) -> String?
    static func centroid(of code: String) -> CGPoint
}

extension USMap: MapGeometry {}
extension CanadaMap: MapGeometry {}

/// One interactive map: fills, rarity bands, callout chips for the regions too small
/// to hit, pinch to zoom, drag to pan, double-tap to reset.
///
/// Every color decision is passed in rather than decided here — the screen owns what
/// Found and Rarity mode mean, and two maps on the same screen must not be able to
/// disagree about it. Zoom state, by contrast, lives *here*: each map is its own
/// viewport, and pinching Canada should not drag the United States with it.
/// Every region's rings as `Path`s, rebuilt only when the rect changes.
///
/// A reference type held in `@State`, so reading and refilling it during `body` is
/// not a state change and cannot drive another render. See the note where it is
/// used: the shapes depend on the rect alone, and the rect changes on rotation and
/// on the callout strip appearing — not thirty times a second.
@MainActor
final class MapPathCache {
    private var rect: CGRect = .null
    private var byCode: [String: [Path]] = [:]

    func rings<G: MapGeometry>(for rect: CGRect,
                               of geometry: G.Type,
                               build: ([CGPoint]) -> Path) -> [String: [Path]] {
        if rect != self.rect {
            self.rect = rect
            byCode = G.codes.reduce(into: [:]) { out, code in
                out[code] = (G.outlines[code] ?? []).filter { $0.count > 2 }.map(build)
            }
        }
        return byCode
    }
}

struct RegionMapView<G: MapGeometry>: View {

    @State private var pathCache = MapPathCache()


    /// Regions a few points across at phone size, effectively impossible to see or
    /// hit. Order them north to south so the leader lines stay roughly parallel and
    /// never cross.
    let calloutCodes: [String]

    let fill: (String) -> Color
    let stroke: (String) -> Color
    let bandWidth: (String, CGSize) -> CGFloat
    let labelColor: (String) -> Color
    /// Nil means the tap landed on nothing, which deselects.
    let onSelect: (String?) -> Void

    /// Drawn with a ring on top of everything else. Nil for no selection.
    var highlighted: String?

    let accessibilityTitle: String
    let foundCount: Int

    /// Which regions are lit, and how brightly. Nil for everything that sits still.
    ///
    /// The screen decides, not the map — the rule is "collected, and epic or better",
    /// and it has to be the same rule in both modes. See `MapScreen.spotlight`.
    var spotlight: (String) -> RarityTier? = { _ in nil }

    /// Thins the rarity band for this map.
    ///
    /// The band is tuned against the smooth, chunky outlines of the lower 48. Canada
    /// at the same on-screen width covers four times the ground, so its coastline is
    /// far more jagged at the same simplification, and a band that reads as a neat
    /// inset on Colorado fills Baffin Island's fjords solid.
    var bandScale: CGFloat = 1

    /// Only for the screenshot flags — a map that opened pre-zoomed for a real user
    /// would be a bug.
    var initialZoom: CGFloat = 1
    var initialPan: CGSize = .zero

    // Zoom state. `zoom` and `pan` are the committed viewport; `pinch` is the
    // in-flight part of a magnification.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch = Pinch()

    /// Where `pan` stood when the drag in progress began, or nil when no drag is in
    /// progress. Panning commits straight into `pan` as it happens rather than
    /// accumulating in gesture state — see the drag gesture for why.
    @State private var panStart: CGSize?

    /// True only while a pan is actually in flight.
    ///
    /// A cancelled gesture never calls `onEnded`, so without this a drag the
    /// ScrollView stole halfway through would leave `panStart` set, and the next drag
    /// would measure its translation from a position two gestures old.
    @GestureState private var panning = false

    /// A live pinch: how much, and about which point on screen.
    ///
    /// The anchor is the whole trick. Scaling about a fixed centre means that once you
    /// have panned away, the content under your fingers slides out from beneath them
    /// as you pinch.
    private struct Pinch: Equatable {
        var factor: CGFloat = 1
        var anchor: CGPoint = .zero
    }

    private static var maxZoom: CGFloat { 8 }

    private var scale: CGFloat { min(max(zoom * pinch.factor, 1), Self.maxZoom) }

    /// Fraction of the width given to the map; the rest is the callout column. With
    /// nothing to call out the map takes the lot.
    private var mapShare: CGFloat { calloutCodes.isEmpty ? 1 : 0.84 }

    var body: some View {
        GeometryReader { geo in
            let rect = mapRect(in: geo.size)
            let shift = liveOffset(in: rect)

            // Every region's rings, built once per rect rather than per frame.
            //
            // The outlines are 65 regions, 103 rings, 3,125 points, and the Canvas
            // was rebuilding all of them from raw coordinates on every tick — then
            // `drawSpotlights` rebuilt the lit ones again. At 30fps that is roughly
            // 93,750 point transforms and 3,000 path allocations a second for shapes
            // that cannot move: `path(_:in:)` depends only on `rect`, and the pan and
            // zoom are applied by the layer transform below, not by the geometry.
            //
            // Held in a reference type so re-reading it is not a state change. `rect`
            // changes on rotation and on the callout strip appearing, and that is the
            // whole of when this has to be rebuilt.
            let rings = pathCache.rings(for: rect, of: G.self) { ring in
                self.path(ring, in: rect)
            }

            // Resolved once per render, which is what the comment on `lit` always
            // claimed and what the `moving` line below was doing — while
            // `drawSpotlights` re-read the property inside the draw closure and paid
            // for all 52 codes again every frame, each one rebuilding `seenCodes` as
            // a fresh Set over every sighting in the collection.
            let lit = self.lit
            // Paused, not absent, when nothing is lit — which is most of the time. A
            // fresh trip has collected nothing, so there is nothing to animate and
            // the map costs exactly what it did before this feature existed.
            let moving = !lit.isEmpty

            TimelineView(.animation(minimumInterval: Self.frameInterval,
                                    paused: !moving)) { tl in
              let time = moving ? tl.date.timeIntervalSinceReferenceDate : 0

              Canvas { ctx, size in
                // Zooming inside the context rather than with `.scaleEffect` on the
                // view: the latter magnifies an already-rasterised bitmap, and Rhode
                // Island turns to mush at 4x. Transforming here re-runs the vectors at
                // whatever scale, so the outlines stay crisp all the way in.
                ctx.drawLayer { layer in
                    let mid = CGPoint(x: rect.midX, y: rect.midY)
                    layer.translateBy(x: mid.x + shift.width, y: mid.y + shift.height)
                    layer.scaleBy(x: scale, y: scale)
                    layer.translateBy(x: -mid.x, y: -mid.y)

                    for code in G.codes {
                        let asked = bandWidth(code, size) * bandScale

                        // Ring by ring rather than one merged path per region, because
                        // the band is capped against the shape it is drawn inside. A
                        // band sized for Texas is wider than several of Nunavut's
                        // islands, while Nunavut as a whole is enormous — so capping
                        // per region would still leave the Arctic a bar of solid gold.
                        for path in rings[code] ?? [] {

                            // Each region carries its band *inside* its own outline
                            // rather than as a stroke on the shared boundary. A stroke
                            // on the border belongs to both neighbours at once, so
                            // where two rarities meet the colors overdraw each other
                            // and neither is readable. Clipping and stroking at double
                            // width leaves exactly the inner half.
                            //
                            // Band width is divided by the zoom so it holds the same
                            // thickness on screen — left alone it would swallow the
                            // small regions exactly when you zoomed in to see them.
                            layer.drawLayer { one in
                                one.clip(to: path)
                                one.fill(path, with: .color(fill(code)))
                                let w = band(asked, for: path, in: size, at: scale)
                                if w > 0 {
                                    one.stroke(path, with: .color(stroke(code)),
                                               lineWidth: w * 2 / scale)
                                }
                            }
                        }
                    }

                    // The rare ones, lit. After every fill so a neighbour cannot
                    // paint over a halo, before the selection ring so tapping a
                    // legendary region still reads as selected rather than as
                    // whatever the light happens to be doing.
                    if moving {
                        drawSpotlights(&layer, lit: lit, rings: rings,
                                       size: size, at: time)
                    }

                    // Selection is drawn last, and as a *centred* stroke on the
                    // boundary rather than as a band clipped inside the region.
                    //
                    // Inside was wrong for this one job. Every other band is inset so
                    // neighbouring colors cannot overdraw each other, but a band
                    // thick enough to read as "selected" is thick enough to swallow
                    // anything narrow: at 3.4x it closed up the Texas panhandle and
                    // the state came out a black blob. A centred stroke keeps its
                    // width whatever the shape is, and overdrawing the neighbour by
                    // half a line is not merely harmless here — it is what makes the
                    // selected region read as being on top.
                    if let highlighted, let paths = rings[highlighted] {

                        // Three passes: blurred halo, the region's own fill painted
                        // back over the inside of it, then the crisp line.
                        //
                        // The middle pass is the one that matters. A blur spreads
                        // both ways, and left alone the halo washed pink across the
                        // whole of Texas — the fill it was meant to be drawing
                        // attention to came out muddy. Re-filling the interior clips
                        // the glow to the outside, which is also where a glow belongs:
                        // it should look like the region is lit from behind, not like
                        // someone has colored it in.
                        //
                        // Widths and the blur radius are divided by the zoom so the
                        // halo holds its size on screen. A glow that grew with the map
                        // would drown the small regions at exactly the magnification
                        // you zoomed in to see them at.
                        layer.drawLayer { halo in
                            halo.addFilter(.blur(radius: 4 / scale))
                            for path in paths {
                                halo.stroke(path,
                                            with: .color(Theme.mapSelection.opacity(0.9)),
                                            lineWidth: 5 / scale)
                            }
                        }
                        for path in paths {
                            layer.fill(path, with: .color(fill(highlighted)))
                        }
                        for path in paths {
                            layer.stroke(path, with: .color(Theme.mapSelection),
                                         lineWidth: 2.0 / scale)
                        }
                    }
                }

                // Chips are chrome, not geography: they neither move nor scale. They
                // also stop earning their keep once you have zoomed in far enough to
                // hit the small regions directly.
                if calloutOpacity > 0 {
                    ctx.opacity = calloutOpacity
                    drawCallouts(&ctx, size: size, mapRect: rect)
                    ctx.opacity = 1
                }
              }
            }
            .contentShape(Rectangle())
            // Pinch stays live at every zoom. Two fingers never mean "scroll the
            // page", so it can coexist with the enclosing ScrollView.
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in
                        state = Pinch(factor: value.magnification,
                                      anchor: value.startLocation)
                    }
                    .onEnded { value in
                        let next = min(max(zoom * value.magnification, 1), Self.maxZoom)
                        let settled = anchoredPan(zoomingTo: next,
                                                  about: value.startLocation,
                                                  in: rect)
                        zoom = next
                        // Re-clamp against the new zoom: pinching back toward 1x
                        // leaves less room to pan than the old offset assumed.
                        pan = clamp(settled, at: next, in: rect)
                    }
            )
            // Panning is only *attached* while there is something to pan.
            //
            // Returning `.zero` from an updating closure was not enough. The gesture
            // still recognised the touch and won it from the ScrollView, so a
            // one-finger drag anywhere on the map did nothing *and* stopped the page
            // from scrolling — the map trapped every vertical swipe that landed on
            // it, leaving only the gaps between cards scrollable. A gesture cannot
            // decline a touch after claiming it, so the fix is to not attach one
            // until zoomed in.
            //
            // High priority, and a short threshold, for the other half of that
            // arbitration: once there *is* something to pan, a drag starting on the
            // map has to beat the enclosing ScrollView rather than race it. Eight
            // points let the scroll view get there first often enough that the map
            // could lose a gesture it should have owned.
            //
            // The pan commits continuously into `pan` rather than accumulating in
            // `@GestureState` and being applied at the end. Both are correct on
            // paper, but only one of them can *fail* correctly: if a frame is
            // dropped, or the gesture is cancelled, or the translation applied on
            // release disagrees by a pixel with the one drawn a moment earlier, the
            // accumulate-then-apply version pays for it with a visible jump at the
            // instant the finger leaves the glass. Here `onEnded` has nothing left to
            // apply, so there is nothing that can arrive late and land as a snap.
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .updating($panning) { _, state, _ in state = true }
                    .onChanged { value in
                        let start = panStart ?? pan
                        if panStart == nil { panStart = start }
                        pan = clamp(CGSize(width: start.width + value.translation.width,
                                           height: start.height + value.translation.height),
                                    at: zoom, in: rect)
                    }
                    .onEnded { _ in panStart = nil },
                isEnabled: zoom > 1
            )
            .onChange(of: panning) { _, isPanning in
                if !isPanning { panStart = nil }
            }
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.32)) { zoom = 1; pan = .zero }
                Haptics.selection()
            }
            .onTapGesture(coordinateSpace: .local) { point in
                // Chips win over the map while they are on screen. One is allowed to
                // overlap a neighbour's edge, and being the easier target is the point.
                if calloutOpacity > 0.5,
                   let hit = callouts(in: geo.size).first(where: {
                       $0.rect.insetBy(dx: -16, dy: -3.5).contains(point)
                   }) {
                    Haptics.selection()
                    onSelect(hit.code)
                    return
                }
                guard let code = G.hitTest(unzoom(point, in: rect), in: rect) else {
                    // Tapped the sea, or the gap between two maps. That is a
                    // deselect, not a miss to be swallowed — tapping away from a
                    // thing is how everyone expects to stop having it selected.
                    onSelect(nil)
                    return
                }
                Haptics.selection()
                onSelect(code)
            }
        }
        .aspectRatio(G.aspect / mapShare, contentMode: .fit)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.07), radius: 8, y: 3)
        )
        // Without this a zoomed map spills out over whatever is below it.
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue("\(foundCount) of \(G.codes.count) regions found")
        .onAppear {
            zoom = initialZoom
            pan = initialPan
        }
    }

    // MARK: - Layout

    private func mapRect(in size: CGSize) -> CGRect {
        let w = size.width * mapShare
        return CGRect(x: 0, y: 0, width: w, height: w / G.aspect)
    }

    /// Chip rectangles, stacked down the right-hand edge beside the regions they
    /// point at.
    private func callouts(in size: CGSize) -> [(code: String, rect: CGRect)] {
        guard !calloutCodes.isEmpty else { return [] }

        let chipW = size.width * 0.135
        let chipH = size.width * 0.058
        let gap = chipH * 0.30
        let count = CGFloat(calloutCodes.count)
        let total = count * chipH + (count - 1) * gap
        // Nudged above centre: these all belong to the top-right of the map, and a line
        // that runs upward reads worse than one that runs across.
        var y = (mapRect(in: size).height - total) * 0.34

        return calloutCodes.map { code in
            let r = CGRect(x: size.width - chipW, y: y, width: chipW, height: chipH)
            y += chipH + gap
            return (code, r)
        }
    }

    /// Callouts start fading the moment you pinch and are gone by 1.5x.
    ///
    /// They exist to solve "I cannot hit Rhode Island at 1x", and zooming solves that
    /// better. Holding them longer only meant lines dangling off the edge toward a
    /// corner that had been panned out of view.
    private var calloutOpacity: Double {
        Double(min(max((1.5 - scale) / 0.5, 0), 1))
    }

    // MARK: - Zoom maths

    /// Keeps the map from being dragged off its own card: at any zoom the pan is
    /// limited to the amount of the map that is actually hidden.
    private func clamp(_ size: CGSize, at zoom: CGFloat, in rect: CGRect) -> CGSize {
        let slackX = rect.width * (zoom - 1) / 2
        let slackY = rect.height * (zoom - 1) / 2
        return CGSize(width: min(max(size.width, -slackX), slackX),
                      height: min(max(size.height, -slackY), slackY))
    }

    /// Committed pan, plus whatever a pinch is currently doing to it.
    ///
    /// Dragging is not folded in here any more — it writes straight to `pan`, so it
    /// is already committed by the time this is read.
    private func liveOffset(in rect: CGRect) -> CGSize {
        var base = pan
        if pinch.factor != 1 {
            base = anchoredPan(zoomingTo: scale, about: pinch.anchor, in: rect)
        }
        return clamp(base, at: scale, in: rect)
    }

    /// The pan that keeps whatever is under `anchor` pinned there while the scale
    /// changes from the committed `zoom` to `target`.
    ///
    /// Falls out of the draw transform, `screen = (base - mid) * s + mid + shift`.
    /// Solving for the shift that leaves the point under the fingers unmoved gives
    /// `shift' = d(1 - f) + shift·f`, where `d` is the anchor's offset from the centre
    /// and `f` the ratio of new scale to old.
    private func anchoredPan(zoomingTo target: CGFloat,
                             about anchor: CGPoint,
                             in rect: CGRect) -> CGSize {
        guard zoom > 0 else { return pan }
        let f = target / zoom
        let dx = anchor.x - rect.midX
        let dy = anchor.y - rect.midY
        return CGSize(width: dx * (1 - f) + pan.width * f,
                      height: dy * (1 - f) + pan.height * f)
    }

    /// Map coordinates to where they are actually drawn. Used for the leader lines,
    /// which have to follow their regions as the map moves under them.
    private func zoomed(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let shift = liveOffset(in: rect)
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        return CGPoint(x: (point.x - mid.x) * scale + mid.x + shift.width,
                       y: (point.y - mid.y) * scale + mid.y + shift.height)
    }

    /// The inverse — screen point back to un-zoomed map coordinates, so hit testing
    /// keeps working at any magnification.
    private func unzoom(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let shift = liveOffset(in: rect)
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        return CGPoint(x: (point.x - mid.x - shift.width) / scale + mid.x,
                       y: (point.y - mid.y - shift.height) / scale + mid.y)
    }

    // MARK: - Callouts

    /// Leader lines and chips for the regions too small to hit.
    ///
    /// The region itself stays drawn in its real place — this adds a target, it does
    /// not move the geography. The line is what keeps the chip from reading as a legend
    /// entry.
    private func drawCallouts(_ ctx: inout GraphicsContext, size: CGSize, mapRect: CGRect) {
        for (code, chip) in callouts(in: size) {
            // Through the same transform the map is drawn with. The chip is fixed chrome
            // but the region under it is not, so an untransformed origin left the line
            // pointing at where the region used to be before you zoomed.
            let from = zoomed(point(G.centroid(of: code), in: mapRect), in: mapRect)
            let to = CGPoint(x: chip.minX, y: chip.midY)

            var line = Path()
            line.move(to: from)
            // An elbow rather than a diagonal: a straight line from Rhode Island to a
            // chip 100pt away cuts across four other states on the way.
            line.addLine(to: CGPoint(x: to.x - chip.width * 0.34, y: from.y))
            line.addLine(to: to)
            ctx.stroke(line, with: .color(Theme.inkMuted.opacity(0.55)),
                       lineWidth: max(size.width / 500, 0.6))

            ctx.fill(Path(ellipseIn: CGRect(x: from.x - 1.6, y: from.y - 1.6,
                                            width: 3.2, height: 3.2)),
                     with: .color(Theme.inkMuted.opacity(0.8)))

            let shape = Path(roundedRect: chip, cornerRadius: chip.height * 0.3)
            ctx.drawLayer { layer in
                layer.clip(to: shape)
                layer.fill(shape, with: .color(fill(code)))
                layer.stroke(shape, with: .color(stroke(code)),
                             lineWidth: bandWidth(code, size) * 2)
            }

            ctx.draw(Text(code)
                        .font(Theme.PlateFont.glyph(chip.height * 0.66))
                        .foregroundStyle(labelColor(code)),
                     at: CGPoint(x: chip.midX, y: chip.midY), anchor: .center)
        }
    }

    private func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    private func path(_ ring: [CGPoint], in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(ring[0], in: rect))
        for p in ring.dropFirst() { path.addLine(to: point(p, in: rect)) }
        path.closeSubpath()
        return path
    }

    /// How heavy a band this particular shape can carry.
    ///
    /// Two limits, both learned from the Arctic. Every one of Nunavut's islands is a
    /// legendary plate, so every one asks for the heaviest band on the scale, and at
    /// phone size the archipelago came out a solid bar of gold with no fill visible
    /// anywhere in it.
    ///
    /// Under a few points across, the band is dropped altogether: it cannot be read at
    /// that size, and the region is already identified by its main landmass. Above
    /// that it is capped at a fifth of the shape's narrower dimension, so the two sides
    /// of the band can never meet in the middle.
    ///
    /// Both bounds are multiplied by the scale to undo the division at the point of
    /// use — the shape on screen grows with the zoom, so they should only bind at
    /// magnifications where the shape is genuinely small.
    private func band(_ asked: CGFloat, for path: Path,
                      in size: CGSize, at scale: CGFloat) -> CGFloat {
        let box = path.boundingRect
        let narrow = min(box.width, box.height) * scale
        guard narrow >= size.width * 0.035 else { return 0 }
        return min(asked, narrow * 0.2)
    }

    // MARK: - Lighting the rare ones

    /// Every region that should be moving, resolved once per render rather than per
    /// frame. Empty is the common case and the one worth being fast: a fresh trip has
    /// collected nothing, so there is nothing to light and no timeline to run.
    fileprivate var lit: [(code: String, tier: RarityTier)] {
        G.codes.compactMap { code in spotlight(code).map { (code, $0) } }
    }

    /// Frames per second for the lighting.
    ///
    /// Deliberately 30 and not the display's own rate. The map redraws all 52 regions
    /// per frame — that is the cost of `Canvas`, which has no scene graph to leave
    /// alone — so on a 120 Hz phone an unthrottled timeline would quadruple the work
    /// of the whole screen to turn a light around seven outlines. Nothing here moves
    /// fast enough to show the difference: the quickest cycle is a five-second
    /// rotation, which travels 2.4° in a 30 Hz frame.
    fileprivate static var frameInterval: Double { 1.0 / 30.0 }

    /// One rotation of the conic light, in seconds. Legendary turns; mythic turns
    /// twice, in opposite directions, at speeds that do not divide into each other so
    /// the two sets of lobes never settle into a pattern.
    private static var legendaryLap: Double { 4.5 }
    private static var mythicLap: Double { 5.0 }
    private static var mythicCounterLap: Double { 7.0 }

    /// How far apart, in seconds, two regions' clocks can be set.
    ///
    /// Longer than the longest cycle here, so the offsets spread across a full turn of
    /// every effect rather than bunching within one.
    private static var spread: Double { 12 }

    /// A region's own place in the cycle, as a 0..<`spread` offset applied to the clock
    /// before anything is derived from it.
    ///
    /// Without this every lit region breathes, rotates and gleams on the same beat,
    /// and seven states flashing in unison reads as one blinking UI element rather
    /// than as seven things each doing its own thing. Offsetting the *time* rather
    /// than each effect separately keeps a single region internally coherent — its
    /// glow and its gleam still belong to each other — while no two regions agree.
    ///
    /// Deliberately not `hashValue`: Swift seeds that per process, so the map would
    /// deal itself a different set of offsets on every launch. FNV-1a over the code's
    /// bytes gives the same answer forever, which means Alaska has a *character*
    /// rather than a random draw.
    private static func phase(_ code: String) -> Double {
        var h: UInt64 = 14695981039346656037
        for byte in code.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Double(h % 997) / 997 * spread
    }

    /// A conic gradient with `count` bright lobes evenly spaced around the turn.
    ///
    /// Built as stops rather than animated as a dash pattern, which is the whole
    /// point: a dash offset that slides along the path is how marching ants are
    /// drawn, and it reads as one. Rotating the light instead leaves the border still
    /// and lit, and only the brightness travels.
    private static func lobes(_ count: Int, _ color: Color,
                              hot: Color, spread: Double) -> Gradient {
        var stops: [Gradient.Stop] = []
        for i in 0..<count {
            let base = Double(i) / Double(count)
            stops.append(.init(color: color.opacity(0), location: base))
            stops.append(.init(color: color.opacity(0.55), location: base + spread * 0.3))
            stops.append(.init(color: hot, location: base + spread * 0.5))
            stops.append(.init(color: color.opacity(0.55), location: base + spread * 0.7))
            stops.append(.init(color: color.opacity(0), location: base + spread))
        }
        stops.append(.init(color: color.opacity(0), location: 1))
        return Gradient(stops: stops)
    }

    /// Lighting width for a region too small for `band` to allow anything at all.
    ///
    /// `band` returns zero below a few points across, and that is right for a *band*:
    /// a band is drawn inside the outline, so on a shape that thin the two sides meet
    /// and the fill disappears underneath. The lighting is mostly *outside* the
    /// outline and has no such problem — but it reused the same test as a yes/no
    /// gate, so eleven regions were excluded from the effect entirely. Hawaii and
    /// Puerto Rico sat there as flat crimson while Alaska and Nunavut turned;
    /// Vermont, P.E.I., Rhode Island, Delaware, Massachusetts, Connecticut, New
    /// Hampshire, New Jersey and D.C. did the same whenever they were epic or above.
    /// A tier you cannot see is not a tier, and a rule that quietly exempts the
    /// smallest regions punishes exactly the plates that are hardest to catch.
    ///
    /// The zero is still right for one case, which is why this is not simply a lower
    /// threshold: a *speck belonging to a larger region*. Nunavut is nineteen islands
    /// around one enormous landmass, and lighting all nineteen is how the Arctic
    /// became a solid blob. So this applies only when nothing in the region cleared
    /// the bar — a region with a mainland still lights the mainland alone.
    ///
    /// Scaled to the shape, with a floor so a speck still reads and a ceiling so the
    /// aura around Rhode Island cannot be the size of Rhode Island.
    private func minimumGlow(for path: Path, in size: CGSize) -> CGFloat {
        let box = path.boundingRect
        let narrow = min(box.width, box.height) * scale
        return min(max(size.width * 0.004, narrow * 0.35), size.width * 0.012)
    }

    /// The whole effect for a region small enough that `band` allowed it nothing:
    /// an aura, and nothing else.
    ///
    /// The full treatment is three strokes and a sweep, all of them drawn *over* the
    /// fill. On Texas that is a border. On Puerto Rico, six points tall, it is the
    /// entire island — the first attempt at this turned Hawaii into a red scribble
    /// and Puerto Rico into a smear, which is a worse answer than leaving them dark.
    ///
    /// So the effect degrades with the shape rather than switching off at a
    /// threshold: large regions get the rotating lobes and the gleam, medium ones
    /// lose the gleam, and these keep only the blurred halo. Then the fill goes back
    /// on top, which is what makes it a halo at all — the light ends up outside the
    /// coastline and the island stays an island.
    private func aura(_ layer: inout GraphicsContext, over path: Path, code: String,
                      tier: RarityTier, width w: CGFloat, opacity: Double) {
        layer.drawLayer { glow in
            glow.addFilter(.blur(radius: w * 1.7 / scale))
            glow.stroke(path, with: .color(tier.color.opacity(opacity)),
                        lineWidth: w * 2.6 / scale)
        }
        layer.fill(path, with: .color(fill(code)))
        // A hairline so the coast still has an edge once the fill is back over the
        // stroke that used to be its outline.
        layer.stroke(path, with: .color(tier.color.opacity(0.75)),
                     lineWidth: max(w * 0.35, 0.5) / scale)
    }

    /// Draws the lighting for every region that has earned it.
    ///
    /// Runs inside the same zoomed layer as the fills, so widths divide by `scale` for
    /// the same reason the bands do — a halo that grew with the zoom would drown the
    /// small regions at exactly the magnification you went in to see them at.
    fileprivate func drawSpotlights(_ layer: inout GraphicsContext,
                                    lit: [(code: String, tier: RarityTier)],
                                    rings: [String: [Path]],
                                    size: CGSize, at time: Double) {
        for (code, tier) in lit {
            let color = tier.color
            // Each region reads the same clock at its own offset — see `phase`. The
            // islands of one region share it, so Hawaii pulses as a place rather than
            // as eight unrelated flickers.
            let clock = time + Self.phase(code)
            let breathe = 0.30 + 0.48 * (0.5 - 0.5 * cos(clock * .pi * 2 / 3.2))
            let throb = 0.34 + 0.58 * (0.5 - 0.5 * cos(clock * .pi * 2 / 3.4))
            // The existing width rule, reused rather than reinvented — and reused for
            // the *weight* of the lighting, not merely as a yes/no threshold.
            //
            // Fixed widths were tried first and Canada threw them out. `band` caps a
            // line at a fifth of the shape's narrower dimension precisely so a stroke
            // sized for Colorado cannot fill Baffin Island's fjords solid; lighting
            // that ignored the cap did exactly that, and Nunavut came out a crimson
            // blob with no land visible inside it. Everything below is a multiple of
            // `w`, so a jagged ring lights itself as finely as it bands itself.
            let asked = bandWidth(code, size) * bandScale
            let paths = rings[code] ?? []
            let widths = paths.map { band(asked, for: $0, in: size, at: scale) }
            // Whether any part of this region was big enough for `band` to allow.
            // See `minimumGlow` for what happens when none of it was.
            let hasMainland = widths.contains { $0 > 0 }

            for (path, banded) in zip(paths, widths) {
                // Too small for a band, and part of a region that has no larger piece
                // to speak for it: an aura instead of the full treatment.
                if banded == 0 {
                    guard !hasMainland else { continue }
                    aura(&layer, over: path, code: code, tier: tier,
                         width: minimumGlow(for: path, in: size),
                         opacity: tier >= .legendary ? throb : breathe)
                    continue
                }
                let w = banded

                let box = path.boundingRect
                let centre = CGPoint(x: box.midX, y: box.midY)

                switch tier {
                case .epic:
                    layer.drawLayer { glow in
                        glow.addFilter(.blur(radius: w * 1.9 / scale))
                        glow.stroke(path, with: .color(color.opacity(breathe)),
                                    lineWidth: w * 2.4 / scale)
                    }

                case .legendary, .mythic:
                    let isMythic = tier == .mythic
                    // A border that is always lit, so between lobes the region still
                    // reads as special rather than blinking out.
                    layer.drawLayer { glow in
                        glow.addFilter(.blur(radius: w * 2.1 / scale))
                        glow.stroke(path,
                                    with: .color(color.opacity(isMythic ? throb : 0.45)),
                                    lineWidth: w * (isMythic ? 2.8 : 2.4) / scale)
                    }
                    layer.stroke(path, with: .color(color.opacity(0.9)),
                                 lineWidth: w * (isMythic ? 1.0 : 0.8) / scale)

                    let turn = clock / (isMythic ? Self.mythicLap : Self.legendaryLap)
                    layer.stroke(
                        path,
                        with: .conicGradient(
                            Self.lobes(isMythic ? 4 : 3, color,
                                       hot: tier.highlight, spread: isMythic ? 0.10 : 0.12),
                            center: centre,
                            angle: .degrees(turn * 360)),
                        lineWidth: w * (isMythic ? 1.7 : 1.6) / scale)

                    // The second set, turning the other way. Only mythic gets it, and
                    // it is what separates the two tiers: legendary rotates, mythic
                    // interferes with itself.
                    if isMythic {
                        let back = -clock / Self.mythicCounterLap
                        layer.stroke(
                            path,
                            with: .conicGradient(
                                Self.lobes(3, color, hot: tier.highlight, spread: 0.13),
                                center: centre,
                                angle: .degrees(back * 360)),
                            lineWidth: w * 1.3 / scale)
                    }

                    gleam(&layer, over: path, box: box, tier: tier, at: clock, in: size)

                default:
                    break
                }
            }
        }
    }

    /// A band of light crossing the fill, on a longer cycle than the rotation.
    ///
    /// Skipped on anything narrow: at a couple of dozen points across the sweep is one
    /// frame of white over the whole shape, which reads as a flicker rather than a
    /// gleam and is the most expensive thing here — a clip and a gradient fill per
    /// region per frame.
    private func gleam(_ layer: inout GraphicsContext, over path: Path, box: CGRect,
                       tier: RarityTier, at time: Double, in size: CGSize) {
        guard box.width * scale > size.width * 0.06 else { return }

        let period = tier == .mythic ? 4.4 : 5.2
        // Rests for the back half of the cycle, so it is an occasional glint rather
        // than a windscreen wiper.
        let t = (time.truncatingRemainder(dividingBy: period)) / period
        guard t < 0.55 else { return }
        let progress = t / 0.55

        let width = max(box.width * 0.22, 6 / scale)
        let travel = box.width + width * 2
        let x = box.minX - width + travel * progress

        layer.drawLayer { g in
            g.clip(to: path)
            let band = CGRect(x: x, y: box.minY - 1,
                              width: width, height: box.height + 2)
            g.fill(Path(band),
                   with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: tier.highlight.opacity(0.75), location: 0.45),
                        .init(color: .white.opacity(0.9), location: 0.5),
                        .init(color: tier.highlight.opacity(0.75), location: 0.55),
                        .init(color: .white.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: band.minX, y: band.midY),
                    endPoint: CGPoint(x: band.maxX, y: band.midY)))
        }
    }
}
