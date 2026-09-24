import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A line graph of one or more channels against time, distance, distance into the current lap
/// (with the best lap as a ghost trace), or another channel (an X-Y plot with a fading trail).
public struct GraphRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: GraphParams

    public init(context: ObjectContext, params: GraphParams) {
        self.context = context
        self.params = params
    }

    /// One polyline in graph units.
    struct Trace {
        var points: [CGPoint]
        var color: RGBAColor
        var lineWidth: Double
        var isGhost: Bool
        /// Which of `params.series` this trace draws, so the ghost and live traces of one series
        /// can be recognised as the same series.
        var seriesIndex: Int
        /// Set when the series scales on its own, in which case this trace is drawn through this
        /// range and takes no part in the graph's shared fit (#145).
        var ownRange: ClosedRange<Double>?
        /// The point for the current moment: where the cursor dot goes and what the readout says.
        /// Not the last point once a graph shows what is still to come (#156).
        var cursor: CGPoint?
        /// Drawn fainter towards its start, as a trail (the channel axis).
        var fades = false
    }

    struct Layout {
        var xRange: ClosedRange<Double>
        var traces: [Trace]
        /// Where on the x axis the current moment is, for the playhead line; `nil` draws none.
        var playheadX: Double?
    }

    struct Plot {
        var rect: CGRect
        var xRange: ClosedRange<Double>
        var yRange: ClosedRange<Double>
        var scale: Double

        func map(_ p: CGPoint, using override: ClosedRange<Double>? = nil) -> CGPoint {
            let yRange = override ?? self.yRange
            let xSpan = max(xRange.upperBound - xRange.lowerBound, 0.000_001)
            let ySpan = max(yRange.upperBound - yRange.lowerBound, 0.000_001)
            return CGPoint(
                x: rect.minX + (p.x - xRange.lowerBound) / xSpan * rect.width,
                y: rect.maxY - (p.y - yRange.lowerBound) / ySpan * rect.height)
        }
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 8, rect.height > 8 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: min(rect.width, rect.height) * 0.08, color: params.backgroundColor.cgColor)
        }
        let padding = min(rect.width, rect.height) * 0.08
        let labelHeight = params.showLabels ? min(rect.height * 0.14, rect.width * 0.06) : 0
        let plotRect = CGRect(
            x: rect.minX + padding, y: rect.minY + padding + labelHeight, width: rect.width - 2 * padding,
            height: rect.height - 2 * padding - labelHeight)
        let pointBudget = max(16, min(Int(plotRect.width / 2), 300))
        let layout = self.layout(at: time, pointBudget: pointBudget)
        let plot = Plot(
            rect: plotRect, xRange: layout.xRange, yRange: verticalRange(of: layout), scale: size.height / 1080)

        drawGrid(in: cg, plot: plot)
        drawTraces(layout.traces, in: cg, plot: plot, playheadX: layout.playheadX)
        if params.showLabels {
            drawLabels(layout, in: cg, plot: plot, labelHeight: labelHeight, top: rect.minY + padding * 0.6)
        }
    }

    /// Fixed or fitted vertical range; ghost traces count so a comparison stays in view.
    func verticalRange(of layout: Layout) -> ClosedRange<Double> {
        var yMin = params.minValue ?? .infinity
        var yMax = params.maxValue ?? -.infinity
        if params.minValue == nil || params.maxValue == nil {
            // Only the traces that actually use this range. A series on its own scale would
            // otherwise go on distorting the fit for the ones that follow the shared one, which is
            // the whole problem it was taken off the shared scale to avoid.
            for trace in layout.traces where trace.ownRange == nil {
                for p in trace.points {
                    if params.minValue == nil { yMin = min(yMin, p.y) }
                    if params.maxValue == nil { yMax = max(yMax, p.y) }
                }
            }
            if !yMin.isFinite { yMin = 0 }
            if !yMax.isFinite { yMax = 1 }
            if yMax - yMin < 0.000_001 {
                yMin -= 0.5
                yMax += 0.5
            } else {
                let pad = (yMax - yMin) * 0.05
                if params.minValue == nil { yMin -= pad }
                if params.maxValue == nil { yMax += pad }
            }
        }
        return yMin...max(yMax, yMin + 0.000_001)
    }

}

// MARK: - Drawing

extension GraphRenderer {
    func drawGrid(in cg: CGContext, plot: Plot) {
        guard params.gridLines > 0, params.gridColor.alpha > 0 else { return }
        cg.setStrokeColor(params.gridColor.cgColor)
        cg.setLineWidth(max(0.5, plot.scale))
        for line in 0...params.gridLines + 1 {
            let y = plot.rect.minY + plot.rect.height * Double(line) / Double(params.gridLines + 1)
            cg.move(to: CGPoint(x: plot.rect.minX, y: y))
            cg.addLine(to: CGPoint(x: plot.rect.maxX, y: y))
        }
        // An X-Y plot has a value on both axes, so it is ruled both ways.
        if params.axis == .channel {
            for line in 0...params.gridLines + 1 {
                let x = plot.rect.minX + plot.rect.width * Double(line) / Double(params.gridLines + 1)
                cg.move(to: CGPoint(x: x, y: plot.rect.minY))
                cg.addLine(to: CGPoint(x: x, y: plot.rect.maxY))
            }
        }
        cg.strokePath()
    }

    /// Ghosts first so live data draws on top; everything clipped to the plot.
    func drawTraces(_ traces: [Trace], in cg: CGContext, plot: Plot, playheadX: Double? = nil) {
        cg.saveGState()
        cg.clip(to: plot.rect.insetBy(dx: -2 * plot.scale, dy: -2 * plot.scale))
        let liveColor = traces.first { !$0.isGhost }?.color
        for trace in traces.sorted(by: { $0.isGhost && !$1.isGhost }) where trace.points.count > 1 {
            let mapped = trace.points.map { plot.map($0, using: trace.ownRange) }
            if trace.fades {
                drawTrail(mapped, color: trace.color, lineWidth: trace.lineWidth, in: cg, plot: plot)
                continue
            }
            if params.fillUnderLine, !trace.isGhost, trace.color == liveColor {
                var fill = trace.color
                fill.alpha *= 0.25
                cg.setFillColor(fill.cgColor)
                cg.move(to: CGPoint(x: mapped[0].x, y: plot.rect.maxY))
                for p in mapped { cg.addLine(to: p) }
                cg.addLine(to: CGPoint(x: mapped[mapped.count - 1].x, y: plot.rect.maxY))
                cg.closePath()
                cg.fillPath()
            }
            cg.setStrokeColor(trace.color.cgColor)
            cg.setLineWidth(max(1, trace.lineWidth * plot.scale))
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            cg.move(to: mapped[0])
            for p in mapped.dropFirst() { cg.addLine(to: p) }
            cg.strokePath()
        }
        cg.restoreGState()
        if params.showCursor, params.showPlayheadLine, let playheadX {
            let x = plot.map(CGPoint(x: playheadX, y: plot.yRange.lowerBound)).x
            var color = params.textColor
            color.alpha *= 0.8
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(max(1, 2 * plot.scale))
            cg.move(to: CGPoint(x: x, y: plot.rect.minY))
            cg.addLine(to: CGPoint(x: x, y: plot.rect.maxY))
            cg.strokePath()
        }
        if params.showCursor, let live = traces.first(where: { !$0.isGhost }), let cursor = live.cursor {
            let p = plot.map(cursor, using: live.ownRange)
            let r = max(2, 5 * plot.scale)
            cg.setFillColor(live.color.cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// Caption top-left, current value top-right, range on the left edge (and, for an X-Y plot,
    /// the horizontal range along the bottom).
    func drawLabels(_ layout: Layout, in cg: CGContext, plot: Plot, labelHeight: Double, top: Double) {
        let style = context.styled(TextDrawing.Style(pointSize: labelHeight * 0.8, color: params.textColor))
        let places = decimals(for: plot.yRange.upperBound - plot.yRange.lowerBound)
        if !params.label.isEmpty {
            TextDrawing.draw(params.label, at: CGPoint(x: plot.rect.minX, y: top), style: style, in: cg)
        }
        if let live = layout.traces.first(where: { !$0.isGhost }), let cursor = live.cursor {
            let unit = unitText(for: params.series.first?.channel ?? "")
            var text = ValueFormatting.format(cursor.y, decimals: places) + (unit.isEmpty ? "" : " \(unit)")
            if params.axis == .channel {
                let xUnit = unitText(for: params.xChannel)
                let xPlaces = decimals(for: plot.xRange.upperBound - plot.xRange.lowerBound)
                text =
                    ValueFormatting.format(cursor.x, decimals: xPlaces) + (xUnit.isEmpty ? "" : " \(xUnit)") + ", "
                    + text
            }
            TextDrawing.draw(
                text, at: CGPoint(x: plot.rect.maxX, y: top), alignment: .trailing,
                style: context.styled(TextDrawing.Style.mono(labelHeight * 0.8, color: params.textColor)), in: cg)
        }
        let small = context.styled(
            TextDrawing.Style(pointSize: labelHeight * 0.55, color: params.textColor, weightBold: false))
        TextDrawing.draw(
            ValueFormatting.format(plot.yRange.upperBound, decimals: places),
            at: CGPoint(x: plot.rect.minX, y: plot.rect.minY), style: small, in: cg)
        let bottom = ValueFormatting.format(plot.yRange.lowerBound, decimals: places)
        TextDrawing.draw(
            bottom,
            at: CGPoint(x: plot.rect.minX, y: plot.rect.maxY - TextDrawing.size(of: bottom, style: small).height),
            style: small, in: cg)
        if params.axis == .channel {
            // The horizontal range along the bottom, clear of the vertical minimum in the corner.
            let xPlaces = decimals(for: plot.xRange.upperBound - plot.xRange.lowerBound)
            let height = TextDrawing.size(of: bottom, style: small).height
            let low = ValueFormatting.format(plot.xRange.lowerBound, decimals: xPlaces)
            let high = ValueFormatting.format(plot.xRange.upperBound, decimals: xPlaces)
            let gap = TextDrawing.size(of: bottom, style: small).width + TextDrawing.size(of: "00", style: small).width
            TextDrawing.draw(
                low, at: CGPoint(x: plot.rect.minX + gap, y: plot.rect.maxY - height), style: small, in: cg)
            TextDrawing.draw(
                high, at: CGPoint(x: plot.rect.maxX, y: plot.rect.maxY - height), alignment: .trailing, style: small,
                in: cg)
        }
    }

    func decimals(for span: Double) -> Int { span < 5 ? 2 : span < 50 ? 1 : 0 }

    func unitText(for channel: String) -> String {
        context.units.label(for: channel) ?? ""
    }

}

// MARK: - Data

extension GraphRenderer {

    /// Builds the traces for project `time`. Exposed for tests.
    func layout(at time: Double, pointBudget: Int) -> Layout {
        guard let sampler = context.sampler else { return Layout(xRange: 0...1, traces: []) }
        let session = sampler.session
        let now = context.inputTime(time)
        let distance = session[.distance]
        let timing = LapTiming.resolve(at: now, laps: session.laps)

        switch params.axis {
        case .time:
            let window = max(params.window, 0.1)
            let start = now - window * playhead
            let times = linspace(start, start + window, pointBudget)
            let traces = params.series.indices.map { index in
                trace(index, sampler: sampler, times: times, x: { $0 - start }, ghost: false, now: now)
            }
            return layout(xRange: 0...window, traces: traces, playheadX: now - start)

        case .distance:
            let window = max(params.window, 1)
            guard let distance, let here = distance.value(at: now) else {
                return fallbackTime(now: now, window: params.window, sampler: sampler, pointBudget: pointBudget)
            }
            let startDistance = here - window * playhead
            let start =
                LapComparison.time(
                    atDistance: startDistance, in: distance, between: distance.firstTime ?? now, and: now)
                ?? (distance.firstTime ?? now)
            // Where the car will be the rest of the window further on, or the end of the data.
            let lastTime = distance.lastTime ?? now
            let end =
                playhead < 1
                ? LapComparison.time(atDistance: startDistance + window, in: distance, between: now, and: lastTime)
                    ?? lastTime : now
            let traces = params.series.indices.map { index in
                trace(
                    index, sampler: sampler, times: linspace(start, end, pointBudget),
                    x: { (distance.value(at: $0) ?? here) - startDistance }, ghost: false, now: now)
            }
            return layout(xRange: 0...window, traces: traces, playheadX: here - startDistance)

        case .lap:
            return lapLayout(now: now, sampler: sampler, timing: timing, distance: distance, pointBudget: pointBudget)

        case .channel:
            return channelLayout(now: now, sampler: sampler, pointBudget: pointBudget)
        }
    }

    /// Where the current moment sits across a scrolling axis, 0…1.
    var playhead: Double { min(max(params.playheadPosition, 0), 1) }

    private func lapLayout(
        now: Double, sampler: TelemetrySampler, timing: LapTiming, distance: Channel?, pointBudget: Int
    ) -> Layout {
        let session = sampler.session
        let lapStart = timing.currentLap?.start ?? (session.timeRange?.lowerBound ?? now)
        guard let distance, let startDistance = distance.value(at: lapStart) else {
            // Without distance, show time into the lap instead.
            let best = timing.bestLapTime ?? max(now - lapStart, 1)
            let traces = params.series.indices.map { index in
                trace(
                    index, sampler: sampler, times: linspace(lapStart, now, pointBudget), x: { $0 - lapStart },
                    ghost: false, now: now)
            }
            return layout(xRange: 0...max(best, now - lapStart, 1), traces: traces)
        }
        var traces: [Trace] = []
        var xMax = max((distance.value(at: now) ?? startDistance) - startDistance, 1)
        if params.compareBestLap, let bestNumber = timing.bestLapNumber,
            let best = session.laps.first(where: { $0.number == bestNumber }), let bestEnd = best.end,
            let bestStartDistance = distance.value(at: best.start)
        {
            xMax = max(xMax, LapComparison.length(of: best, distance: distance) ?? 0)
            for index in params.series.indices {
                var ghost = trace(
                    index, sampler: sampler, times: linspace(best.start, bestEnd, pointBudget),
                    x: { (distance.value(at: $0) ?? bestStartDistance) - bestStartDistance }, ghost: true)
                ghost.color = params.ghostColor
                traces.append(ghost)
            }
        }
        for index in params.series.indices {
            traces.append(
                trace(
                    index, sampler: sampler, times: linspace(lapStart, now, pointBudget),
                    x: { (distance.value(at: $0) ?? startDistance) - startDistance }, ghost: false, now: now))
        }
        return layout(xRange: 0...xMax, traces: traces)
    }

    private func fallbackTime(now: Double, window: Double, sampler: TelemetrySampler, pointBudget: Int) -> Layout {
        let seconds = max(window / 20, 1)  // ~20 m/s: a rough metres → seconds guess
        let start = now - seconds
        let traces = params.series.indices.map { index in
            trace(
                index, sampler: sampler, times: linspace(start, now, pointBudget), x: { $0 - start }, ghost: false,
                now: now)
        }
        return layout(xRange: 0...seconds, traces: traces)
    }

    /// One series sampled at `times`. A live trace's cursor is its value at `now`, or where the
    /// data last had one before then.
    private func trace(
        _ index: Int, sampler: TelemetrySampler, times: [Double], x: (Double) -> Double, ghost: Bool,
        now: Double? = nil
    ) -> Trace {
        let series = params.series[index]
        guard let role = ChannelValue.role(series.channel) else {
            return Trace(
                points: [], color: series.color, lineWidth: series.lineWidth, isGhost: ghost, seriesIndex: index)
        }
        var points: [CGPoint] = []
        points.reserveCapacity(times.count)
        var cursor: CGPoint?
        for t in times {
            guard let v = sampler.value(of: role, at: t) else { continue }
            let point = CGPoint(x: x(t), y: context.units.value(v, of: series.channel))
            points.append(point)
            if let now, t <= now { cursor = point }
        }
        if let now, let v = sampler.value(of: role, at: now) {
            cursor = CGPoint(x: x(now), y: context.units.value(v, of: series.channel))
        }
        var trace = Trace(
            points: points, color: series.color, lineWidth: series.lineWidth, isGhost: ghost, seriesIndex: index)
        trace.cursor = cursor
        return trace
    }

    private func linspace(_ a: Double, _ b: Double, _ count: Int) -> [Double] {
        guard b > a, count > 1 else { return [b] }
        return (0..<count).map { a + (b - a) * Double($0) / Double(count - 1) }
    }
}

extension GraphRenderer {
    /// A layout whose own-scale series have their ranges fitted. One range per *series*, over
    /// every trace of it: the best lap's ghost and the live lap are two traces of the same series,
    /// and fitting each to itself would put both peaks on the top line however different they
    /// were — the comparison the lap axis exists to draw — while the live one rescaled under
    /// itself as the lap filled in.
    func layout(xRange: ClosedRange<Double>, traces: [Trace], playheadX: Double? = nil) -> Layout {
        var traces = traces
        for (index, series) in params.series.enumerated() where series.usesOwnScale {
            let points = traces.filter { $0.seriesIndex == index }.flatMap(\.points)
            let range = Self.ownRange(of: series, points: points)
            for i in traces.indices where traces[i].seriesIndex == index { traces[i].ownRange = range }
        }
        return Layout(xRange: xRange, traces: traces, playheadX: playheadX)
    }

    /// The range a series is drawn through when it scales on its own: what it was given, falling
    /// back per-bound to this series' own data. `nil` when it follows the graph's shared range.
    static func ownRange(of series: GraphSeries, points: [CGPoint]) -> ClosedRange<Double>? {
        guard series.usesOwnScale else { return nil }
        var low = series.minValue ?? .infinity
        var high = series.maxValue ?? -.infinity
        if series.minValue == nil || series.maxValue == nil {
            for p in points {
                if series.minValue == nil { low = min(low, p.y) }
                if series.maxValue == nil { high = max(high, p.y) }
            }
            if !low.isFinite { low = 0 }
            if !high.isFinite { high = 1 }
            if high - low < 0.000_001 {
                low -= 0.5
                high += 0.5
            } else {
                let pad = (high - low) * 0.05
                if series.minValue == nil { low -= pad }
                if series.maxValue == nil { high += pad }
            }
        }
        return low...max(high, low + 0.000_001)
    }
}

// MARK: - The channel axis (#156)

extension GraphRenderer {
    /// Each series against `xChannel` over the last `window` seconds, as a trail ending at now.
    fileprivate func channelLayout(now: Double, sampler: TelemetrySampler, pointBudget: Int) -> Layout {
        let times = linspace(now - max(params.window, 0.1), now, pointBudget)
        var traces: [Trace] = []
        if let xRole = ChannelValue.role(params.xChannel) {
            for (index, series) in params.series.enumerated() {
                var trace = Trace(
                    points: [], color: series.color, lineWidth: series.lineWidth, isGhost: false, seriesIndex: index)
                trace.fades = true
                if let role = ChannelValue.role(series.channel) {
                    for t in times {
                        guard let x = sampler.value(of: xRole, at: t), let y = sampler.value(of: role, at: t) else {
                            continue
                        }
                        trace.points.append(
                            CGPoint(
                                x: context.units.value(x, of: params.xChannel),
                                y: context.units.value(y, of: series.channel)))
                    }
                }
                trace.cursor = trace.points.last
                traces.append(trace)
            }
        }
        return layout(xRange: horizontalRange(of: traces), traces: traces)
    }

    /// The channel axis's fixed or fitted range, fitted like the vertical one.
    func horizontalRange(of traces: [Trace]) -> ClosedRange<Double> {
        var low = params.xMinValue ?? .infinity
        var high = params.xMaxValue ?? -.infinity
        if params.xMinValue == nil || params.xMaxValue == nil {
            for trace in traces {
                for p in trace.points {
                    if params.xMinValue == nil { low = min(low, p.x) }
                    if params.xMaxValue == nil { high = max(high, p.x) }
                }
            }
            if !low.isFinite { low = 0 }
            if !high.isFinite { high = 1 }
            if high - low < 0.000_001 {
                low -= 0.5
                high += 0.5
            } else {
                let pad = (high - low) * 0.05
                if params.xMinValue == nil { low -= pad }
                if params.xMaxValue == nil { high += pad }
            }
        }
        return low...max(high, low + 0.000_001)
    }

    /// A line that fades out towards its oldest point, one segment at a time.
    func drawTrail(_ points: [CGPoint], color: RGBAColor, lineWidth: Double, in cg: CGContext, plot: Plot) {
        cg.setLineWidth(max(1, lineWidth * plot.scale))
        cg.setLineCap(.round)
        let last = Double(points.count - 1)
        for index in 1..<points.count {
            var faded = color
            faded.alpha *= 0.1 + 0.9 * Double(index) / last
            cg.setStrokeColor(faded.cgColor)
            cg.move(to: points[index - 1])
            cg.addLine(to: points[index])
            cg.strokePath()
        }
    }
}
