import ProjectModel
import SwiftUI
import TelemetryKit

/// One run of a session in the Logbook (#552): the clock's time, the cones it hit and whether it
/// went off course, and the time that counts. Each change is one step of Edit ▸ Undo.
struct RunPenaltyRow: View {
    let entry: LogbookEntry
    let lap: LogbookEntry.LapRecord
    let save: (LogbookEntry) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Run \(lap.number)")
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(official).monospacedDigit()
                    .foregroundStyle(lap.number == entry.bestLapNumber ? Color.accentColor : .primary)
                    .accessibilityIdentifier("logbook.run.\(lap.number).official")
                if lap.cones > 0, !lap.isDNF, let seconds = lap.seconds {
                    Text("\(TimeParsing.lapTimeString(seconds)) + \(conesText)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Stepper(value: cones, in: 0...20) { Text(conesText).monospacedDigit() }
                .disabled(!lap.isComplete)
                .accessibilityLabel("Cones on Run \(lap.number)")
                .accessibilityValue(conesText)
                .help("Cones this run hit; each adds \(perConeText) to its time")
                .accessibilityIdentifier("logbook.run.\(lap.number).cones")
            Toggle("DNF", isOn: offCourse)
                .toggleStyle(.checkbox)
                .disabled(!lap.isComplete)
                .accessibilityLabel("Run \(lap.number) Did Not Finish")
                .help(
                    lap.isComplete
                        ? "Went off course: a DNF, though it crossed the finish"
                        : "Never reached the finish, so it is a DNF"
                )
                .accessibilityIdentifier("logbook.run.\(lap.number).offCourse")
        }
        .font(.callout)
    }

    /// "0:53.97", or "DNF".
    private var official: String {
        lap.officialSeconds(perCone: entry.perCone).map { TimeParsing.lapTimeString($0) } ?? "DNF"
    }

    private var conesText: String { lap.cones == 1 ? "1 cone" : "\(lap.cones) cones" }

    private var perConeText: String { entry.perCone.formatted(.number.precision(.fractionLength(0...1))) + " s" }

    private var cones: Binding<Int> {
        Binding(get: { lap.cones }, set: { value in change { $0.cones = value } })
    }

    private var offCourse: Binding<Bool> {
        Binding(get: { lap.isDNF }, set: { value in change { $0.offCourse = value } })
    }

    private func change(_ body: (inout LogbookEntry.LapRecord) -> Void) {
        guard let index = entry.laps.firstIndex(where: { $0.number == lap.number }) else { return }
        var changed = entry
        body(&changed.laps[index])
        changed.applyPenalties()
        if changed != entry { save(changed) }
    }
}

/// The day's penalty per cone, for a day with runs on it (#552): every run's cones count at it.
struct PenaltyPerConeField: View {
    let day: TrackDay
    let save: (TrackDay) -> Void

    var body: some View {
        GridRow {
            Text("Per cone").foregroundStyle(.secondary)
            Stepper(value: perCone, in: 0...10, step: 0.5) {
                Text(perCone.wrappedValue.formatted(.number.precision(.fractionLength(0...1))) + " s")
                    .monospacedDigit()
            }
            .accessibilityLabel("Penalty per Cone")
            .accessibilityValue(perCone.wrappedValue.formatted() + " seconds")
            .help("Seconds each cone adds to a run's time on this day")
            .accessibilityIdentifier("trackday.header.perCone")
        }
    }

    private var perCone: Binding<Double> {
        Binding(
            get: { day.penaltyPerCone ?? RunPenalty.defaultPerCone },
            set: { value in
                var changed = day
                changed.penaltyPerCone = value == RunPenalty.defaultPerCone ? nil : value
                if changed != day { save(changed) }
            })
    }
}
