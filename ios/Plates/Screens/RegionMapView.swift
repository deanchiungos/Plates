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
/// Every colour decision is passed in rather than decided here — the screen owns what
/// Found and Rarity mode mean, and two maps on the same screen must not be able to
/// disagree about it. Zoom state, by contrast, lives *here*: each map is its own
/// viewport, and pinching Canada should not drag the United States with it.
struct RegionMapView<G: MapGeometry>: View {

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
                        for ring in G.outlines[code] ?? [] where ring.count > 2 {
                            let path = self.path(ring, in: rect)

                            // Each region carries its band *inside* its own outline
                            // rather than as a stroke on the shared boundary. A stroke
                            // on the border belongs to both neighbours at once, so
                            // where two rarities meet the colours overdraw each other
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

                    // Selection is drawn last, and as a *centred* stroke on the
                    // boundary rather than as a band clipped inside the region.
                    //
                    // Inside was wrong for this one job. Every other band is inset so
                    // neighbouring colours cannot overdraw each other, but a band
                    // thick enough to read as "selected" is thick enough to swallow
                    // anything narrow: at 3.4x it closed up the Texas panhandle and
                    // the state came out a black blob. A centred stroke keeps its
                    // width whatever the shape is, and overdrawing the neighbour by
                    // half a line is not merely harmless here — it is what makes the
                    // selected region read as being on top.
                    if let highlighted, let rings = G.outlines[highlighted] {
                        let paths = rings.filter { $0.count > 2 }
                            .map { self.path($0, in: rect) }

                        // Three passes: blurred halo, the region's own fill painted
                        // back over the inside of it, then the crisp line.
                        //
                        // The middle pass is the one that matters. A blur spreads
                        // both ways, and left alone the halo washed pink across the
                        // whole of Texas — the fill it was meant to be drawing
                        // attention to came out muddy. Re-filling the interior clips
                        // the glow to the outside, which is also where a glow belongs:
                        // it should look like the region is lit from behind, not like
                        // someone has coloured it in.
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
}
