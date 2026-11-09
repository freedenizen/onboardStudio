import Foundation
import ProjectModel
import TelemetryKit

/// One file of an every-corner export (#326): which corner, and the project seconds it covers.
public struct CornerExport: Sendable, Equatable {
    public let index: Int
    /// What the circuit calls it ("4", "3a"), else its number.
    public let label: String
    public let range: ClosedRange<Double>
    /// Seconds lost (+) or gained (−) against the reference in this corner.
    public let timeLost: Double
    /// The clip's own retimes, in project time (#360): the braking zone slowed, a sight picture held.
    public let retimes: [Retime]

    public init(index: Int, label: String, range: ClosedRange<Double>, timeLost: Double, retimes: [Retime] = []) {
        self.index = index
        self.label = label
        self.range = range
        self.timeLost = timeLost
        self.retimes = retimes
    }

    public var title: String { "Turn \(label)" }

    /// `Sonoma – Turn 4.mp4`.
    public func fileName(base: String, fileExtension: String) -> String {
        "\(base) – \(title).\(fileExtension)"
    }
}

extension ProjectCompiler {
    /// Seconds before the brake point a corner's clip begins, and after the corner it ends.
    public static let cornerClipLeadSeconds = 2.0
    public static let cornerClipHoldSeconds = 2.0

    /// The files an every-corner export writes: the corners of the coaching lap — the lap chosen
    /// in Project ▸ Coaching…, else the lap being compared, else the first lap read — each from
    /// `cornerClipLeadSeconds` before its brake point to `cornerClipHoldSeconds` after its end,
    /// in project time and clipped to it. With `onlyOpportunities`, the corners that lost time,
    /// biggest loss first. Empty for any other kind of range, or without a data input that reads.
    public static func cornerExports(_ range: ExportRange, in loaded: LoadedProject, duration: Double)
        -> [CornerExport]
    {
        guard case .eachCorner(let onlyOpportunities, let retime) = range else { return [] }
        guard let read = coachingLap(in: loaded) else { return [] }
        let (input, lap, analysis) = (read.input, read.lap, read.analysis)
        let corners = onlyOpportunities ? analysis.opportunities.map(\.corner) : analysis.corners
        return corners.compactMap { comparison in
            let metrics = comparison.lap
            let from = lap.start + analysis.lap.elapsed(atDistance: metrics.phaseStart) - cornerClipLeadSeconds
            let exit = analysis.lap.elapsed(atDistance: metrics.corner.endDistance)
            let to = lap.start + exit + cornerClipHoldSeconds
            let start = min(max(input.sync.projectTime(forInputTime: from), 0), duration)
            let stop = min(max(input.sync.projectTime(forInputTime: to), start), duration)
            guard stop > start else { return nil }
            // Distances into the lap → project seconds.
            func projectTime(atDistance distance: Double) -> Double {
                input.sync.projectTime(forInputTime: lap.start + analysis.lap.elapsed(atDistance: distance))
            }
            return CornerExport(
                index: comparison.index, label: comparison.label, range: start...stop,
                timeLost: comparison.timeLost,
                retimes: retime.map {
                    cornerRetimes($0, for: comparison, within: start...stop, projectTime: projectTime(atDistance:))
                } ?? [])
        }
    }

    /// A corner clip's retimes (#360): from the lap's brake point to its slowest point at
    /// `brakingRate`, and a hold of the whole frame when the lap reaches the distance at which the
    /// reference braked, for a sight picture of where to brake. A corner the lap was not braked
    /// for has no braking zone to slow; one the reference did not brake for has no sight picture.
    static func cornerRetimes(
        _ retime: CornerClipRetime, for comparison: CornerComparison, within clip: ClosedRange<Double>,
        projectTime: (Double) -> Double
    ) -> [Retime] {
        var retimes: [Retime] = []
        let lap = comparison.lap
        if let rate = retime.brakingRate, lap.brakePointMeters != nil {
            let from = projectTime(lap.phaseStart)
            let slowest = projectTime(lap.corner.apexDistance + lap.minimumSpeedMeters)
            if slowest > from, clip.contains(from) {
                retimes.append(Retime(start: from, kind: .speed(end: min(slowest, clip.upperBound), rate: rate)))
            }
        }
        if let seconds = retime.referenceHoldSeconds, seconds > 0, comparison.reference.brakePointMeters != nil {
            let at = projectTime(comparison.reference.phaseStart)
            if clip.contains(at) { retimes.append(Retime(start: at, kind: .hold(seconds: seconds))) }
        }
        return retimes
    }

    /// The lap a coaching export reads, and its reading.
    public struct CoachingLap: Sendable {
        public let input: Input
        public let session: TelemetrySession
        public let track: CoachingTrack
        public let lap: Lap
        public let analysis: CoachingAnalysis
    }

    /// The coaching lap of the first data input that reads: the lap chosen in Project ▸ Coaching…,
    /// else the lap being compared, else the first lap read, against the project's reference.
    /// The track is the compile's when it carried one, else read now.
    public static func coachingLap(in loaded: LoadedProject) -> CoachingLap? {
        let project = loaded.project
        for input in project.dataInputs {
            guard let session = loaded.sessions[input.id] else { continue }
            let track =
                loaded.coaching[input.id]
                ?? CoachingTracks.make(for: project, sessions: loaded.sessions, previous: nil)[input.id]
            guard let track, !track.laps.isEmpty else { continue }
            let chosen =
                project.coaching.flatMap { $0.dataInputID == input.id ? $0.lap : nil }
                ?? project.lapComparison.flatMap { $0.lap.dataInputID == input.id ? $0.lap.lap : nil }
            let lap = track.laps.first { $0.number == chosen } ?? track.laps[0]
            guard let analysis = track.analyses[lap.number] else { continue }
            return CoachingLap(input: input, session: session, track: track, lap: lap, analysis: analysis)
        }
        return nil
    }
}
