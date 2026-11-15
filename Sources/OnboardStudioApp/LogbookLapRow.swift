import ProjectModel
import SwiftUI
import TelemetryKit

/// A circuit lap in a session's detail: its number and time, the best in the accent colour; one
/// the driver left out (#554) in secondary text with why, and a menu — or a right-click — to leave
/// it out or count it again. The figures are read again from the session's file, so a change
/// waits for it and says when the file could not be read.
struct LogbookLapRow: View {
    let entry: LogbookEntry
    let lap: LogbookEntry.LapRecord
    /// Leaves the lap out for a reason, or counts it again; `false` when the file could not be read.
    let markLap: (Int, LapMark.Reason?) async -> Bool

    @State private var marking = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Lap \(lap.number)")
                Spacer()
                if marking { ProgressView().controlSize(.mini) }
                if let reason = lap.notCounted {
                    Text("left out: \(reason.word)").foregroundStyle(.secondary)
                        .accessibilityIdentifier("logbook.lap.\(lap.number).leftOut")
                }
                Text(lap.seconds.map { TimeParsing.lapTimeString($0) } ?? "—").monospacedDigit()
                    .foregroundStyle(
                        lap.number == entry.bestLapNumber ? Color.accentColor : lap.counts ? .primary : .secondary)
                if !lap.isComplete { Text("partial").foregroundStyle(.secondary) }
                Menu {
                    items
                } label: {
                    Image(systemName: lap.counts ? "ellipsis.circle" : "nosign")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(marking)
                .accessibilityLabel("Lap \(lap.number) Counts")
                .accessibilityValue(lap.notCounted.map { "Left out: \($0.word)" } ?? "Counts")
                .help("Leave this lap out of the best, optimal and rolling laps, consistency and Trends, or count it")
                .accessibilityIdentifier("logbook.lap.\(lap.number).counts")
            }
            if failed {
                Text("The session's file could not be read, so the lap was not changed. It may have moved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .contextMenu { items }
    }

    /// "Count Lap 7", then "Leave Lap 7 Out" with a reason each, the reason in force ticked.
    @ViewBuilder private var items: some View {
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
        failed = false
        Task {
            failed = !(await markLap(lap.number, reason))
            marking = false
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
