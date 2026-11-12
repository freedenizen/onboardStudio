import Foundation
import TelemetryKit

/// What Watch plays for a corner in the coaching walkthrough (#516): this lap's corner, then the
/// reference lap's, each from a moment before the brakes go on to a moment after the exit — and
/// where those moments are in what can be played: a project's picture, or the day's own clips.
public enum CornerFootage {
    public enum Side: Sendable, Equatable { case lap, reference }

    /// One stretch to play, in the seconds of the session it was driven in.
    public struct Piece: Sendable, Equatable {
        public let side: Side
        public let sessionTimes: ClosedRange<Double>
    }

    /// Seconds shown before braking begins, so the approach is seen, and after the exit.
    public static let leadIn = 1.5
    public static let leadOut = 1.0

    /// This lap's corner, then the reference's when `referenceIsFootage`: when the reference was
    /// driven as one stretch of a session with a picture — not spliced from several laps, nor read
    /// from a file there is no picture of.
    public static func pieces(
        of comparison: CornerComparison, in analysis: CoachingAnalysis, referenceIsFootage: Bool
    ) -> [Piece] {
        var pieces = [Piece(side: .lap, sessionTimes: span(of: comparison.lap, on: analysis.lap))]
        if referenceIsFootage, !analysis.reference.isSpliced {
            pieces.append(Piece(side: .reference, sessionTimes: span(of: comparison.reference, on: analysis.reference)))
        }
        return pieces
    }

    /// From before the brakes go on to after the exit, on `profile`'s session clock.
    static func span(of metrics: CornerMetrics, on profile: LapProfile) -> ClosedRange<Double> {
        let start = profile.time(atDistance: metrics.phaseStart) - leadIn
        let end = profile.time(atDistance: metrics.phaseEnd) + leadOut
        return min(start, end)...max(start, end)
    }

    /// Where `sessionTimes` of a data input with `sync` plays in a project's output, cut to the
    /// output; `nil` when none of it is there — the picture ends before the corner, say.
    public static func outputRange(
        of sessionTimes: ClosedRange<Double>, sync: SyncSettings, timeMap: TimeMap
    ) -> ClosedRange<Double>? {
        let start = timeMap.outputTime(atProject: sync.projectTime(forInputTime: sessionTimes.lowerBound))
        let end = timeMap.outputTime(atProject: sync.projectTime(forInputTime: sessionTimes.upperBound))
        return clamp(min(start, end)...max(start, end), to: timeMap.outputDuration)
    }

    /// A camera's recording: when it started, by its clock, and how long it ran, every chapter.
    public struct Recording: Sendable, Equatable {
        public let startEpoch: Double
        public let duration: Double

        public init(startEpoch: Double, duration: Double) {
            self.startEpoch = startEpoch
            self.duration = duration
        }
    }

    /// The recording that was running when `sessionTimes` began, and the stretch of it, in its own
    /// seconds, cut to the recording; `nil` when no recording covers the start or the session has
    /// no clock (`epoch` returns `nil`).
    public static func recordingRange(
        of sessionTimes: ClosedRange<Double>, epoch: (Double) -> Double?, recordings: [Recording]
    ) -> (recording: Int, range: ClosedRange<Double>)? {
        guard let start = epoch(sessionTimes.lowerBound), let end = epoch(sessionTimes.upperBound) else { return nil }
        // The recording the approach is in; a corner that began before the camera did is shown
        // from the recording's start.
        let index =
            recordings.firstIndex { start >= $0.startEpoch && start < $0.startEpoch + $0.duration }
            ?? recordings.firstIndex { end > $0.startEpoch && start < $0.startEpoch + $0.duration }
        guard let index else { return nil }
        let recording = recordings[index]
        guard
            let range = clamp(
                (start - recording.startEpoch)...(end - recording.startEpoch), to: recording.duration)
        else { return nil }
        return (index, range)
    }

    private static func clamp(_ range: ClosedRange<Double>, to duration: Double) -> ClosedRange<Double>? {
        let start = max(0, range.lowerBound)
        let end = min(duration, range.upperBound)
        return end > start ? start...end : nil
    }
}
