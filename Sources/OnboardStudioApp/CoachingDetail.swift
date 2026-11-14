import ProjectModel
import SwiftUI
import TelemetryKit

/// One corner, read closely (#322): the time lost in each phase, both laps' readings side by
/// side with where each came from, the two lines through the corner, and the way to the video.
struct CornerDetailView: View {
    let analysis: CoachingAnalysis
    let comparison: CornerComparison
    let units: CoachingUnits
    /// Every other complete lap of the session, for the spread of lines through the corner (#334).
    var others: [LapProfile] = []
    /// `nil` when the reference cannot be filmed: a spliced lap, or a file without a camera.
    let compareInVideo: (() -> Void)?
    /// The lap being read, for the traffic mark's label.
    var lapNumber: Int?
    /// Marks the corner as held up by traffic or a flag, or clears it (#571).
    var markTraffic: ((TrafficSpan.Kind?) -> Void)?

    private var format: CoachingNotes.Formatter { CoachingNotes.Formatter(units: units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Compare in Video by the corner's name: below the readings it was out of sight (#458).
                HStack(alignment: .firstTextBaseline) {
                    Text("Turn \(comparison.label)").font(.title3.weight(.semibold))
                    Spacer()
                    if let compareInVideo {
                        Button("Compare in Video", action: compareInVideo)
                            .help("Lay the project out with both laps' pictures over this corner")
                            .accessibilityIdentifier("coaching.compareInVideo")
                    }
                }
                if let markTraffic, let lapNumber {
                    CornerMarkPicker(
                        comparison: comparison, referencePhrase: analysis.referencePhrase, lapNumber: lapNumber,
                        mark: markTraffic)
                }
                PhaseLossBars(comparison: comparison, units: units)
                CornerLinesView(analysis: analysis, comparison: comparison, units: units, others: others)
                readings
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("coaching.detail")
    }

    /// Both laps' readings, one row per measurement.
    private var readings: some View {
        let lap = comparison.lap
        let reference = comparison.reference
        return VStack(alignment: .leading, spacing: 4) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("This lap").font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                    Text(analysis.reference.label).font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                }
                row("Brake point", before(lap.brakePointMeters), before(reference.brakePointMeters))
                row("Peak braking", lap.peakBrakingG.map(format.g), reference.peakBrakingG.map(format.g))
                row("Brakes off", relative(lap.brakeReleaseMeters), relative(reference.brakeReleaseMeters))
                row(
                    "Trail braking", lap.trailBrakingMeters.map(format.metres),
                    reference.trailBrakingMeters.map(format.metres))
                row("Entry speed", format.speed(lap.entrySpeed), format.speed(reference.entrySpeed))
                row("Minimum speed", format.speed(lap.minimumSpeed), format.speed(reference.minimumSpeed))
                row("Slowest point", relative(lap.minimumSpeedMeters), relative(reference.minimumSpeedMeters))
                row("Throttle", relative(lap.throttlePickupMeters), relative(reference.throttlePickupMeters))
                row("Full throttle", relative(lap.fullThrottleMeters), relative(reference.fullThrottleMeters))
                row("Exit speed", format.speed(lap.exitSpeed), format.speed(reference.exitSpeed))
                row("Coasting", lap.coastingSeconds.map(format.seconds), reference.coastingSeconds.map(format.seconds))
                row("Peak lateral G", lap.peakLateralG.map(format.g), reference.peakLateralG.map(format.g))
                row("Time in corner", format.seconds(lap.timeInCorner), format.seconds(reference.timeInCorner))
            }
            .font(.callout)
            Text(sources).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ name: String, _ lap: String?, _ reference: String?) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(lap ?? "–").monospacedDigit()
            Text(reference ?? "–").monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): this lap \(lap ?? "no reading"), reference \(reference ?? "no reading")")
    }

    /// "172 m before the apex"
    private func before(_ metres: Double?) -> String? {
        metres.map { "\(format.metres($0)) before" }
    }

    /// "12 m after" / "4 m before" / "at the apex"
    private func relative(_ metres: Double?) -> String? {
        guard let metres else { return nil }
        if abs(metres) < 1 { return "at the apex" }
        return "\(format.metres(abs(metres))) \(metres > 0 ? "after" : "before")"
    }

    private var sources: String {
        let brake = comparison.lap.brakeSource?.displayName ?? "no braking found"
        let throttle = comparison.lap.throttleSource?.displayName ?? "no pick-up found"
        return "Distances are from the apex. Brakes read from \(brake); throttle from \(throttle)."
    }
}

/// The two lines through the corner, drawn from GPS, with the brake points and slowest points
/// marked. A relative picture, not a survey: lap-to-lap spread is about a metre and absolute
/// accuracy one to three, and the help tag says so.
struct CornerLinesView: View {
    let analysis: CoachingAnalysis
    let comparison: CornerComparison
    let units: CoachingUnits
    var others: [LapProfile] = []

    struct Mark {
        var point: CGPoint
        var isReference: Bool
        var isBrake: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(height: 200)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(accessibilityDescription)
            .help(
                "The two lines through the corner from GPS, this lap in the accent colour. Lap-to-lap spread is about "
                    + "a metre and absolute accuracy one to three, so read the lines relative to each other.")
            // Rows of whole entries: an `HStack` shared the width out and broke each over two lines,
            // one of them inside a word (#457).
            FlowLayout {
                Group {
                    Label("This lap", systemImage: "line.diagonal").foregroundStyle(Color.accentColor)
                    Label(analysis.reference.label, systemImage: "line.diagonal").foregroundStyle(.secondary)
                    if !others.isEmpty {
                        Label("Other laps", systemImage: "line.diagonal").foregroundStyle(.tertiary)
                    }
                    Label("Brake point", systemImage: "circle.fill")
                    Label("Slowest", systemImage: "square.fill")
                }
                .lineLimit(1)
                .padding(.trailing, 6)
            }
            .font(.caption).foregroundStyle(.secondary)
            if let offset = analysis.delta.lateralOffset(atDistance: comparison.reference.corner.apexDistance) {
                let format = CoachingNotes.Formatter(units: units)
                let side = offset > 0 ? "right" : "left"
                let distance = format.metres(abs(offset))
                Text("At the apex this lap ran \(distance) to the \(side) of \(analysis.referencePhrase)'s line.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityDescription: String {
        "Map of turn \(comparison.label): this lap's line and \(analysis.reference.label)'s line, "
            + "with the brake points and slowest points marked."
    }

    struct Lines {
        var reference: [CGPoint] = []
        var lap: [CGPoint] = []
        var others: [[CGPoint]] = []
        var marks: [Mark] = []
    }

    /// Both lines over the corner and a little either side, in metres about the reference's apex.
    func lines() -> Lines {
        let corner = comparison.reference.corner
        guard let apex = analysis.reference.position(atDistance: corner.apexDistance) else { return Lines() }
        let perLatitude = 110_540.0
        let perLongitude = 111_320.0 * cos(apex.latitude * .pi / 180)
        func local(_ position: (latitude: Double, longitude: Double)) -> CGPoint {
            CGPoint(
                x: (position.longitude - apex.longitude) * perLongitude,
                y: (position.latitude - apex.latitude) * perLatitude)
        }
        let margin = 80.0
        let from = max(0, min(comparison.reference.phaseStart, corner.startDistance) - margin)
        let to = min(analysis.reference.lengthMeters, corner.endDistance + margin)
        var reference: [CGPoint] = []
        var lap: [CGPoint] = []
        var otherLines = Array(repeating: [CGPoint](), count: others.count)
        var distance = from
        while distance <= to {
            if let position = analysis.reference.position(atDistance: distance) { reference.append(local(position)) }
            let onLap = analysis.delta.lapDistance(atReferenceDistance: distance)
            if let position = analysis.lap.position(atDistance: onLap) { lap.append(local(position)) }
            // The other laps by distance: same session, same line to a metre, which is the point.
            for (index, other) in others.enumerated() {
                if let position = other.position(atDistance: distance) { otherLines[index].append(local(position)) }
            }
            distance += 2
        }
        var marks: [Mark] = []
        func mark(_ metrics: CornerMetrics, profile: LapProfile, isReference: Bool) {
            let apexDistance = metrics.corner.apexDistance
            if let brake = metrics.brakePointMeters, let position = profile.position(atDistance: apexDistance - brake) {
                marks.append(Mark(point: local(position), isReference: isReference, isBrake: true))
            }
            if let position = profile.position(atDistance: apexDistance + metrics.minimumSpeedMeters) {
                marks.append(Mark(point: local(position), isReference: isReference, isBrake: false))
            }
        }
        mark(comparison.reference, profile: analysis.reference, isReference: true)
        mark(comparison.lap, profile: analysis.lap, isReference: false)
        return Lines(reference: reference, lap: lap, others: otherLines, marks: marks)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let lines = lines()
        let (reference, lap, marks) = (lines.reference, lines.lap, lines.marks)
        let all = reference + lap + lines.others.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(),
            let maxY = all.map(\.y).max()
        else { return }
        let padding = 14.0
        let span = max(maxX - minX, maxY - minY, 1)
        let scale = (min(size.width, size.height) - 2 * padding) / span
        let offsetX = (size.width - (maxX - minX) * scale) / 2
        let offsetY = (size.height - (maxY - minY) * scale) / 2
        func place(_ point: CGPoint) -> CGPoint {
            // North up: y grows downwards on screen.
            CGPoint(x: offsetX + (point.x - minX) * scale, y: size.height - offsetY - (point.y - minY) * scale)
        }
        func path(_ points: [CGPoint]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: place(first))
            for point in points.dropFirst() { path.addLine(to: place(point)) }
            return path
        }
        for other in lines.others { context.stroke(path(other), with: .color(.secondary.opacity(0.35)), lineWidth: 1) }
        context.stroke(path(reference), with: .color(.secondary), lineWidth: 2)
        context.stroke(path(lap), with: .color(.accentColor), lineWidth: 2)
        for mark in marks {
            let at = place(mark.point)
            let rect = CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)
            let shading: GraphicsContext.Shading = .color(mark.isReference ? .secondary : .accentColor)
            if mark.isBrake {
                context.fill(Path(ellipseIn: rect), with: shading)
            } else {
                context.fill(Path(rect), with: shading)
            }
        }
    }
}

/// Where a corner's time went, phase by phase: in the corner's detail and in its step of the
/// walkthrough (#458).
struct PhaseLossBars: View {
    let comparison: CornerComparison
    let units: CoachingUnits

    private var format: CoachingNotes.Formatter { CoachingNotes.Formatter(units: units) }

    var body: some View {
        let losses = CornerPhase.allCases.map { ($0, comparison.phaseLoss[$0] ?? 0) }
        let scale = max(losses.map { abs($0.1) }.max() ?? 0, 0.01)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Time lost by phase").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                ForEach(losses, id: \.0) { phase, loss in
                    GridRow {
                        Text(phase.displayName).frame(width: 60, alignment: .leading)
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(loss > 0 ? Color.red : Color.green)
                                .frame(width: max(2, geometry.size.width * abs(loss) / scale))
                        }
                        .frame(height: 10)
                        Text((loss >= 0 ? "+" : "−") + format.seconds(abs(loss)))
                            .monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(phase.displayName): \(format.seconds(abs(loss))) \(loss >= 0 ? "lost" : "gained")")
                }
            }
        }
    }
}
