import Charts
import ProjectModel
import SwiftUI
import TelemetryKit

/// One line of a trace: a lap's values across the span, in its colour.
struct AnalysisSeries: Identifiable {
    let id: Int
    let label: String
    let color: Color
    let points: [LapAnalysis.Point]
}

/// A trace against distance (#556): every chosen lap's line, the cursor as a rule across it; a
/// hover or a drag moves the cursor, which every other panel follows.
struct AnalysisTracePanel: View {
    let title: String
    let series: [AnalysisSeries]
    let span: ClosedRange<Double>
    let height: Double
    /// Metres shown as the axis's unit: 1 for metres, 0.3048 for feet.
    let metresPerUnit: Double
    let unitSymbol: String
    @Binding var cursor: Double?
    var zeroLine = false
    var format: (Double) -> String = { String(format: "%.1f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Chart {
                if zeroLine { RuleMark(y: .value("Level", 0)).foregroundStyle(.secondary.opacity(0.5)) }
                ForEach(series) { line in
                    ForEach(line.points, id: \.distance) { point in
                        LineMark(
                            x: .value("Distance", point.distance), y: .value(title, point.value),
                            series: .value("Lap", line.id)
                        )
                        .foregroundStyle(line.color)
                        .interpolationMethod(.linear)
                    }
                }
                if let cursor, span.contains(cursor) {
                    RuleMark(x: .value("Cursor", cursor)).foregroundStyle(.primary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: span)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let metres = value.as(Double.self) { Text("\(Int((metres / metresPerUnit).rounded()))") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel { if let number = value.as(Double.self) { Text(format(number)) } }
                }
            }
            .chartLegend(.hidden)
            // A line runs to the grid point just outside the span; the plot ends where its axis does.
            .chartPlotStyle { $0.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                move(to: location, proxy: proxy, geometry: geometry)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged {
                                move(to: $0.location, proxy: proxy, geometry: geometry)
                            }
                        )
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(spoken)
        }
    }

    private func move(to location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let x = location.x - geometry[frame].origin.x
        guard let distance = proxy.value(atX: x, as: Double.self) else { return }
        cursor = min(max(distance, span.lowerBound), span.upperBound)
    }

    /// What VoiceOver reads: each lap's value at the cursor.
    private var spoken: String {
        guard let cursor else { return "\(series.count) laps" }
        return series.compactMap { line in
            line.points.min { abs($0.distance - cursor) < abs($1.distance - cursor) }.map {
                "\(line.label) \(format($0.value))"
            }
        }.joined(separator: ", ")
    }
}

/// The reference lap's path, each lap's car at the cursor, the corner names; a click zooms the
/// traces to the corner it is nearest (#556).
struct AnalysisMapPanel: View {
    let analysis: LapAnalysis
    let colors: [Color]
    let cursor: Double?
    let onClick: (Double) -> Void

    var body: some View {
        let path = analysis.path()
        GeometryReader { geometry in
            let projection = Projection(path: path.map { ($0.latitude, $0.longitude) }, size: geometry.size)
            Canvas { context, _ in
                var line = Path()
                for (index, point) in path.enumerated() {
                    let at = projection.point(point.latitude, point.longitude)
                    if index == 0 { line.move(to: at) } else { line.addLine(to: at) }
                }
                context.stroke(line, with: .style(.secondary), lineWidth: 3)
                for corner in analysis.corners {
                    guard let apex = analysis.position(analysis.reference, at: corner.apex) else { continue }
                    let at = projection.point(apex.latitude, apex.longitude)
                    context.draw(
                        Text(corner.label).font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: at.x, y: at.y - 10))
                }
                guard let cursor else { return }
                for trace in analysis.traces.reversed() {
                    guard let place = analysis.position(trace, at: cursor) else { continue }
                    let at = projection.point(place.latitude, place.longitude)
                    let dot = Path(ellipseIn: CGRect(x: at.x - 5, y: at.y - 5, width: 10, height: 10))
                    context.fill(dot, with: .color(colors[trace.id % colors.count]))
                    context.stroke(dot, with: .color(.white), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let (latitude, longitude) = projection.coordinate(location)
                if let distance = analysis.distance(nearestLatitude: latitude, longitude: longitude) {
                    onClick(distance)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track map")
        .accessibilityValue(analysis.corner(at: cursor ?? -1_000).map { "At \($0.title)" } ?? "")
        .accessibilityHint("Click a corner to zoom the traces to it")
        .accessibilityIdentifier("analysis.map")
    }

    /// Latitude and longitude to points, north up, the path fitted with a margin.
    struct Projection {
        let minLatitude: Double
        let minLongitude: Double
        let scale: Double
        let longitudeScale: Double
        let offset: CGPoint
        let height: Double

        init(path: [(Double, Double)], size: CGSize, margin: Double = 16) {
            let latitudes = path.map(\.0)
            let longitudes = path.map(\.1)
            minLatitude = latitudes.min() ?? 0
            minLongitude = longitudes.min() ?? 0
            longitudeScale = cos(((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2 * .pi / 180)
            let width = max(((longitudes.max() ?? 1) - minLongitude) * longitudeScale, 1e-9)
            let tall = max((latitudes.max() ?? 1) - minLatitude, 1e-9)
            scale = min((size.width - 2 * margin) / width, (size.height - 2 * margin) / tall)
            offset = CGPoint(
                x: (size.width - width * scale) / 2, y: (size.height - tall * scale) / 2)
            height = tall * scale
        }

        func point(_ latitude: Double, _ longitude: Double) -> CGPoint {
            CGPoint(
                x: offset.x + (longitude - minLongitude) * longitudeScale * scale,
                y: offset.y + height - (latitude - minLatitude) * scale)
        }

        func coordinate(_ point: CGPoint) -> (Double, Double) {
            let latitude = minLatitude + (offset.y + height - point.y) / scale
            let longitude = minLongitude + (point.x - offset.x) / scale / longitudeScale
            return (latitude, longitude)
        }
    }
}

/// Lateral against longitudinal G for each lap across the span: how much of the grip each used,
/// and whether braking ran into turning (#556). The car's grip is a dashed line round them (#631).
/// The cursor's points are larger.
struct AnalysisFrictionCircle: View {
    let analysis: LapAnalysis
    let colors: [Color]
    let span: ClosedRange<Double>
    let cursor: Double?
    var target: GripTarget?

    var body: some View {
        let grid = analysis.grid(in: span, points: 300)
        let clouds = analysis.traces.map { analysis.frictionCircle($0, at: grid) }
        let outline = target?.envelope.outline() ?? []
        let reached =
            clouds.flatMap { $0 }.map { max(abs($0.lateral), abs($0.longitudinal)) }
            + outline.map { max(abs($0.lateral), abs($0.longitudinal)) }
        let limit = max(1, (reached.max() ?? 1) * 1.1)
        VStack(alignment: .leading, spacing: 0) {
            circle(clouds: clouds, outline: outline, limit: limit)
            // Under the circle, not over its points, and its own words for VoiceOver and the tests.
            if let target {
                Text(target.caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .padding([.horizontal, .bottom], 4)
                    .help("Each lap's points against the most grip the car has shown in conditions like these")
                    .accessibilityIdentifier("analysis.gripTarget")
            }
        }
    }

    private func circle(
        clouds: [[LapAnalysis.GPoint]], outline: [(lateral: Double, longitudinal: Double)], limit: Double
    )
        -> some View
    {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 4
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            func at(lateral: Double, longitudinal: Double) -> CGPoint {
                CGPoint(x: centre.x + lateral / limit * radius, y: centre.y - longitudinal / limit * radius)
            }
            func at(_ point: LapAnalysis.GPoint) -> CGPoint {
                at(lateral: point.lateral, longitudinal: point.longitudinal)
            }
            for ring in stride(from: 0.5, through: limit, by: 0.5) {
                let r = ring / limit * radius
                context.stroke(
                    Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                    with: .style(.quaternary), lineWidth: 1)
            }
            var axes = Path()
            axes.move(to: CGPoint(x: centre.x - radius, y: centre.y))
            axes.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
            axes.move(to: CGPoint(x: centre.x, y: centre.y - radius))
            axes.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
            context.stroke(axes, with: .style(.quaternary), lineWidth: 1)
            if !outline.isEmpty {
                var shape = Path()
                shape.addLines(outline.map { at(lateral: $0.lateral, longitudinal: $0.longitudinal) })
                shape.closeSubpath()
                context.stroke(shape, with: .style(.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            for (index, cloud) in clouds.enumerated().reversed() {
                let color = colors[index % colors.count].opacity(0.45)
                for point in cloud {
                    let p = at(point)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(color))
                }
            }
            guard let cursor else { return }
            for trace in analysis.traces {
                guard let point = analysis.frictionCircle(trace, at: [cursor]).first else { continue }
                let p = at(point)
                let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                context.fill(dot, with: .color(colors[trace.id % colors.count]))
                context.stroke(dot, with: .color(.white), lineWidth: 1)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Friction circle · rings every 0.5 G").font(.caption2).foregroundStyle(.secondary).padding(4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Friction circle")
        .accessibilityValue(spoken(clouds))
        .accessibilityIdentifier("analysis.frictionCircle")
    }

    /// The most combined G each lap reached across the span, and the most of the target it used.
    private func spoken(_ clouds: [[LapAnalysis.GPoint]]) -> String {
        zip(analysis.traces, clouds).map { trace, cloud in
            let most = cloud.map { hypot($0.lateral, $0.longitudinal) }.max() ?? 0
            let reading = "\(trace.label) up to \(String(format: "%.2f", most)) G"
            guard let target else { return reading }
            let used = target.mostUsed(cloud.map { ($0.lateral, $0.longitudinal) })
            return reading + ", \(GripWording.percent(used)) of \(target.noun)"
        }.joined(separator: ", ")
    }
}
