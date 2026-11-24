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
        LeftOutLaps.shared.note = reason.map { LeftOutLaps.Note(source: source.id, lap: number, reason: $0) }
        Task { await source.markLap(lap, as: reason, undo: undo) }
    }

    /// Across the top of the window once a lap has been left out here: what that did, and the way
    /// back.
    var leftOutNotice: some View {
        LeftOutLapNotice(source: source) { number, undo in markLap(number, as: nil, undo: undo) }
    }
}

/// The lap last left out in a Coaching window, for the window to say so. Leaving the lap being
/// read out moved the window on to another lap with nothing to say one had been left out, why,
/// or how to count it again (#669).
@MainActor @Observable final class LeftOutLaps {
    static let shared = LeftOutLaps()

    struct Note: Equatable {
        /// The `id` of the source it was left out in.
        var source: String
        var lap: Int
        var reason: LapMark.Reason
    }

    var note: Note?
}

/// "Lap 3 is left out (traffic)…", with Put Lap 3 Back, until it is dismissed or the lap counts
/// again — by this button, by the lap's own menu or by Undo.
struct LeftOutLapNotice: View {
    let source: any CoachingSource
    let putBack: (Int, UndoManager?) -> Void
    @Environment(\.undoManager) private var undoManager

    /// The note, while it is about this window's session and the lap is still left out.
    private var note: LeftOutLaps.Note? {
        guard let note = LeftOutLaps.shared.note, note.source == source.id,
            let lap = source.session?.laps.first(where: { $0.number == note.lap }),
            source.lapMarks.mark(of: lap) != nil
        else { return nil }
        return note
    }

    var body: some View {
        if let note {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label {
                    Text(Self.sentence(lap: note.lap, reason: note.reason))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coaching.leftOut.notice")
                } icon: {
                    Image(systemName: "nosign").accessibilityHidden(true)
                }
                Spacer()
                Button("Put Lap \(note.lap) Back") { putBack(note.lap, undoManager) }
                    .help("Count the lap again, as Edit ▸ Undo does")
                    .accessibilityIdentifier("coaching.leftOut.putBack")
                Button {
                    LeftOutLaps.shared.note = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .help("Hide this note; the lap stays left out")
            }
            .font(.callout)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5))
        }
    }

    /// What leaving the lap out did, in one sentence.
    static func sentence(lap: Int, reason: LapMark.Reason) -> String {
        "Lap \(lap) is left out (\(reason.word)). It is still listed, and no longer counts towards the best, "
            + "optimal or rolling lap, consistency or Trends. Its menu beside the lap changes the reason."
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
