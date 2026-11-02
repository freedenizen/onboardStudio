import Foundation
import TelemetryKit

/// The debrief on one page (#331): what an instructor hands over in the paddock — the track with
/// its corners numbered, where the time went, every corner's numbers, and what to try next. The
/// same sheet writes as Markdown and, in the app, as a PDF.
public struct CoachingSheet: Sendable {
    /// A point of the outline, in a unit square with north up and y growing downwards.
    public struct Point: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct CornerMark: Hashable, Sendable {
        public var label: String
        public var point: Point
        public init(label: String, point: Point) {
            self.label = label
            self.point = point
        }
    }

    public struct Item: Hashable, Sendable {
        public var headline: String
        public var evidence: [String]
        public var suggestion: String
    }

    /// The track and the day: "Sonoma", "23 Aug 2026 · Driver · Car".
    public var title: String
    public var subtitle: String
    public var headline: String
    public var notes: [String]
    public var opportunities: [Item]
    public var rows: [CornerRow]
    public var plan: NextSessionPlan?
    public var outline: [Point]
    public var corners: [CornerMark]
    public var warnings: [String]
    public var units: CoachingUnits
    public var lapNumber: Int

    public init(
        analysis: CoachingAnalysis, lapNumber: Int, units: CoachingUnits, title: String, subtitle: String = "",
        plan: NextSessionPlan? = nil, warnings: [String] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.lapNumber = lapNumber
        self.units = units
        headline = analysis.headline(lapNumber: lapNumber, units: units)
        notes = [analysis.splicedFrom, analysis.alignmentLine].compactMap { $0 }
        opportunities = analysis.top.map {
            Item(headline: $0.note.headline, evidence: $0.note.evidence, suggestion: $0.note.suggestion)
        }
        rows = analysis.rows(units: units)
        self.plan = plan
        self.warnings = warnings
        let map = Self.map(of: analysis)
        outline = map.outline
        corners = map.corners
    }

    /// "Sonoma – Lap 2 coaching sheet", for the file name.
    public var fileStem: String {
        let track = title.trimmingCharacters(in: .whitespaces)
        return "\(track.isEmpty ? "Coaching" : track) – Lap \(lapNumber) coaching sheet"
    }

    // MARK: - The map

    /// The reference lap's outline and its corners' apexes, scaled into a unit square with the
    /// aspect kept; empty without position.
    static func map(of analysis: CoachingAnalysis) -> (outline: [Point], corners: [CornerMark]) {
        let reference = analysis.reference
        guard let latitudes = reference.latitude, let longitudes = reference.longitude, latitudes.count > 1,
            let midLatitude = latitudes.first
        else { return ([], []) }
        let perLatitude = 110_540.0
        let perLongitude = 111_320.0 * cos(midLatitude * .pi / 180)
        let raw = zip(latitudes, longitudes).map { (x: $1 * perLongitude, y: $0 * perLatitude) }
        guard let minX = raw.map(\.x).min(), let maxX = raw.map(\.x).max(), let minY = raw.map(\.y).min(),
            let maxY = raw.map(\.y).max()
        else { return ([], []) }
        let span = max(maxX - minX, maxY - minY, 1)
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        func place(latitude: Double, longitude: Double) -> Point {
            Point(
                x: (longitude * perLongitude - minX + offsetX) / span,
                y: 1 - (latitude * perLatitude - minY + offsetY) / span)
        }
        let outline = zip(latitudes, longitudes).map { place(latitude: $0, longitude: $1) }
        let corners = analysis.corners.compactMap { comparison -> CornerMark? in
            guard let apex = reference.position(atDistance: comparison.reference.corner.apexDistance) else {
                return nil
            }
            return CornerMark(label: comparison.label, point: place(latitude: apex.latitude, longitude: apex.longitude))
        }
        return (outline, corners)
    }

    // MARK: - Markdown

    public var markdown: String {
        let format = CoachingNotes.Formatter(units: units)
        var lines: [String] = []
        lines.append("# \(title.isEmpty ? "Coaching sheet" : title) — Lap \(lapNumber)")
        if !subtitle.isEmpty { lines.append("*\(subtitle)*") }
        lines.append("")
        lines.append("**\(headline)**")
        for note in notes where !note.isEmpty { lines.append(note.hasSuffix(".") ? note : note + ".") }
        if let plan, !plan.experiments.isEmpty {
            lines.append("")
            lines.append("## Next session, try…")
            lines.append("")
            for (index, experiment) in plan.experiments.enumerated() {
                lines.append("\(index + 1). **\(experiment.title)** — \(experiment.text)")
            }
        }
        lines.append("")
        lines.append("## Where the time went")
        lines.append("")
        if opportunities.isEmpty {
            lines.append("Nothing lost: every corner matched the reference.")
        }
        for (index, item) in opportunities.enumerated() {
            lines.append("\(index + 1). **\(item.headline)**")
            for evidence in item.evidence { lines.append("   - \(evidence)") }
            lines.append("   - *Try:* \(item.suggestion)")
        }
        lines.append("")
        lines.append("## Every corner")
        lines.append("")
        lines.append("| Turn | Lost | Phase | Brake | Min speed | Where | Exit | Throttle | Consistent |")
        lines.append("|---|---:|---|---|---|---|---|---|---|")
        for row in rows {
            let lost = (row.timeLost >= 0 ? "+" : "−") + format.seconds(abs(row.timeLost))
            let cells = [
                row.label, lost, row.phase, row.brake, row.minimumSpeed, row.minimumPoint, row.exitSpeed, row.throttle,
                row.consistent,
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        if !warnings.isEmpty {
            lines.append("")
            for warning in warnings { lines.append("- \(warning)") }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
