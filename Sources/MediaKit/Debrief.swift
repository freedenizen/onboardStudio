import Foundation
import ProjectModel
import TelemetryKit

/// What a coaching debrief video is made of (#327): a title card, the corners that cost the
/// most as clips in the project's own layout, and a closing card with what to try next time.
public struct DebriefPlan: Sendable, Equatable {
    /// A card of text on a plain background: a title and the lines under it.
    public struct Card: Sendable, Equatable {
        public var title: String
        public var lines: [String]
        public var seconds: Double

        public init(title: String, lines: [String], seconds: Double) {
            self.title = title
            self.lines = lines
            self.seconds = seconds
        }
    }

    public var title: Card
    /// The corner clips in the order they play: the biggest loss first.
    public var corners: [CornerExport]
    public var closing: Card

    public init(title: Card, corners: [CornerExport], closing: Card) {
        self.title = title
        self.corners = corners
        self.closing = closing
    }

    /// How long the debrief plays.
    public var duration: Double {
        title.seconds + corners.reduce(0) { $0 + $1.range.upperBound - $1.range.lowerBound } + closing.seconds
    }

    /// The segments as the sheet lists them: "Title card", "Turn 4 — 0.31 s lost", …, "Next session".
    public var segmentTitles: [String] {
        ["Title card"]
            + corners.map { corner in
                "\(corner.title) — \(String(format: "%.2f", corner.timeLost)) s lost"
            } + ["Next session"]
    }

    public static let titleSeconds = 5.0
    public static let closingSecondsPerLine = 2.5
    public static let closingSecondsMinimum = 5.0

    /// The debrief of the coaching lap — the lap chosen in Project ▸ Coaching…, else the lap being
    /// compared, else the first lap read — against the project's reference: the top `cornerCount`
    /// corners that lost time, biggest loss first, with the clip each has inside the project
    /// (`duration`); `nil` without a data input that reads. A lap that lost nothing has no corner
    /// clips and a closing card that says so.
    public static func make(in loaded: ProjectCompiler.LoadedProject, duration: Double, cornerCount: Int = 3)
        -> DebriefPlan?
    {
        guard let read = ProjectCompiler.coachingLap(in: loaded) else { return nil }
        let clips = ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: true), in: loaded, duration: duration)
        let kept = Array(clips.prefix(max(cornerCount, 0)))
        let keptIndices = Set(kept.map(\.index))
        let title = titleCard(for: read, project: loaded.project)
        let tries = read.analysis.opportunities.filter { keptIndices.contains($0.corner.index) }
            .map { "Turn \($0.corner.label): \($0.note.suggestion)" }
        let closingLines =
            tries.isEmpty
            ? ["This lap matched \(read.track.referencePhrase) in every corner. Drive it again the same way."]
            : tries
        let closing = Card(
            title: "Next session, try…", lines: closingLines,
            seconds: max(closingSecondsMinimum, Double(closingLines.count) * closingSecondsPerLine))
        return DebriefPlan(title: title, corners: kept, closing: closing)
    }

    /// The session, the track and the day, then the lap read, what it was read against, and the
    /// best, optimal and fastest rolling laps.
    static func titleCard(for read: ProjectCompiler.CoachingLap, project: Project) -> Card {
        let details = project.details
        let session = read.session
        func text(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let heading = text(details.track) ?? text(session.info.trackName) ?? "Coaching Debrief"
        var lines: [String] = []
        let when = [text(details.event), text(details.session), text(details.date)].compactMap { $0 }
        if !when.isEmpty { lines.append(when.joined(separator: " · ")) }
        let who = [text(details.driver), text(details.car)].compactMap { $0 }
        if !who.isEmpty { lines.append(who.joined(separator: " · ")) }
        let stats = SessionStats(session: session)
        if let best = stats.bestLap {
            lines.append("Best lap \(TimeParsing.lapTimeString(best.seconds)) (lap \(best.number))")
        }
        if let optimal = stats.optimalLap { lines.append("Optimal lap \(TimeParsing.lapTimeString(optimal))") }
        if let rolling = CoachingReference.fastestRolling.resolve(in: session)?.duration,
            rolling < (stats.bestLap?.seconds ?? .infinity) - 0.005
        {
            lines.append("Fastest rolling lap \(TimeParsing.lapTimeString(rolling))")
        }
        let loss = read.analysis.totalLoss
        let behind = loss >= 0 ? "\(String(format: "%.2f", loss)) s behind" : "\(String(format: "%.2f", -loss)) s ahead"
        lines.append("Lap \(read.lap.number) read against \(read.track.referencePhrase): \(behind)")
        return Card(title: heading, lines: lines, seconds: titleSeconds)
    }
}
