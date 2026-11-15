import ProjectModel
import SwiftUI
import TelemetryKit

/// A lap's number in a session's lap table, as a menu (#554): click it to leave the lap out of the
/// session's figures for a reason, or to count it again. A menu on the number rather than a column
/// of its own, so the table is no wider and the narrow detail still shows every lap's time. The
/// figures are read again from the session's file, so a change waits for it, with a spinner.
struct LapCountsMenu: View {
    let lap: LogbookEntry.LapRecord
    /// Leaves the lap out for a reason, or counts it again; `false` when the file could not be read.
    let markLap: (Int, LapMark.Reason?) async -> Bool
    /// Told whether the last change could be made, so the table can say when it could not.
    var finished: (Bool) -> Void = { _ in }

    @State private var marking = false

    var body: some View {
        Menu {
            Self.items(for: lap, mark: mark)
        } label: {
            HStack(spacing: 4) {
                Text("Lap \(lap.number)")
                if marking {
                    ProgressView().controlSize(.mini)
                } else if !lap.counts {
                    Image(systemName: "nosign").foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(marking)
        .accessibilityLabel("Lap \(lap.number)")
        .accessibilityValue(lap.notCounted.map { "Left out: \($0.word)" } ?? "Counts")
        .help("Leave this lap out of the best, optimal and rolling laps, consistency and Trends, or count it")
        .accessibilityIdentifier("logbook.lap.\(lap.number).counts")
    }

    /// "Count Lap 7", then "Leave Lap 7 Out" with a reason each, the reason in force ticked: the
    /// menu's items, and the lap's right-click menu.
    @ViewBuilder
    static func items(for lap: LogbookEntry.LapRecord, mark: @escaping (LapMark.Reason?) -> Void) -> some View {
        Button("Count Lap \(lap.number)") { mark(nil) }
            .disabled(lap.counts)
        Section("Leave Lap \(lap.number) Out") {
            ForEach(LapMark.Reason.allCases) { reason in
                Toggle(
                    reason.title,
                    isOn: Binding(get: { lap.notCounted == reason }, set: { if $0 { mark(reason) } }))
            }
        }
    }

    private func mark(_ reason: LapMark.Reason?) {
        marking = true
        Task {
            let done = await markLap(lap.number, reason)
            marking = false
            finished(done)
        }
    }

    /// "laps 4, 6 and 7": what the optimal lap is spliced from, once the laps have been read by a
    /// build that keeps it (#554).
    static func sources(of entry: LogbookEntry, noun: String) -> String? {
        let sources = entry.optimalSources
        guard !sources.isEmpty, entry.optimalLap != nil else { return nil }
        let names = sources.map(String.init)
        return sources.count == 1 ? "\(noun) \(names[0])" : "\(noun)s " + names.formatted(.list(type: .and))
    }
}
