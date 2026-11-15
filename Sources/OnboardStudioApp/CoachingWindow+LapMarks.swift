import ProjectModel
import SwiftUI
import TelemetryKit

// Leaving a whole lap out (#554): traffic, a flag, an off. The lap is still read and listed, but
// it is never the best, never in the optimal or the rolling lap, and not in the consistency.
extension CoachingContent {
    /// Leaves lap `number` out for `reason`, or counts it again: one step of Undo, after which the
    /// reading is made again without it.
    func markLap(_ number: Int, as reason: LapMark.Reason?, undo: UndoManager?) {
        guard let lap = source.session?.laps.first(where: { $0.number == number }) else { return }
        Task { await source.markLap(lap, as: reason, undo: undo) }
    }
}

/// Whether the lap being read counts, as the window's choices offer it: "Counts", or left out
/// with a reason. Beside the lap it is about, as the corner's own mark is beside the corner.
struct LapCountsPicker: View {
    let lapTitle: String
    let reason: LapMark.Reason?
    let mark: (LapMark.Reason?) -> Void

    var body: some View {
        Picker(
            "\(lapTitle):",
            selection: Binding(get: { reason }, set: { mark($0) })
        ) {
            Text("Counts").tag(LapMark.Reason?.none)
            Section("Leave Out") {
                ForEach(LapMark.Reason.allCases) { reason in
                    Text("Left Out: \(reason.title)").tag(LapMark.Reason?.some(reason))
                }
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(
            "Leave this lap out of the best, optimal and rolling laps and the consistency figures: it was held "
                + "up by traffic, under a flag or had an off"
        )
        .accessibilityIdentifier("coaching.lapCounts")
    }
}

/// Said in the walkthrough's first step about a lap the driver left out: it is still read, but
/// counts towards nothing.
struct LeftOutLapNote: View {
    let lapTitle: String
    let reason: LapMark.Reason

    var body: some View {
        Label {
            Text(
                "\(lapTitle) is left out (\(reason.word)): it is not the best, the optimal or the rolling lap, and "
                    + "does not count towards consistency or your Trends."
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("coaching.walkthrough.lapLeftOut")
        } icon: {
            Image(systemName: "nosign").accessibilityHidden(true)
        }
        .font(.callout).foregroundStyle(.secondary)
    }
}

/// Whether the lap the walkthrough reads counts, and the way to change it.
struct LapMarking {
    /// Why it was left out; `nil` while it counts.
    var reason: LapMark.Reason?
    var mark: (LapMark.Reason?) -> Void
}

/// Under the walkthrough's first step: a lap left out says so, and a lap the telemetry suggests
/// was traffic offers to leave it out (#554) beside the corners it suggests (#572).
struct LapTrafficNotes: View {
    let analysis: CoachingAnalysis
    let lapNumber: Int
    let marking: LapMarking?

    var body: some View {
        if let reason = marking?.reason {
            LeftOutLapNote(lapTitle: "Lap \(lapNumber)", reason: reason)
        }
        SuggestedCorners(
            analysis: analysis, lapNumber: lapNumber,
            leaveLapOut: marking.flatMap { marking in marking.reason == nil ? { marking.mark(.traffic) } : nil })
    }
}
