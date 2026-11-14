import ProjectModel
import SwiftUI

/// The detail column with several sessions selected (#454): how many, where and when, and what can
/// be done to all of them at once — their car, the day they are on, taking them out — in place of
/// one session's laps. Each is one step of Edit ▸ Undo.
struct SessionsSelectionDetail: View {
    let entries: [LogbookEntry]
    let days: [TrackDay]
    let knownCars: [String]
    let setCar: (String) -> Void
    let move: (TrackDay) -> Void
    let moveToOwnDays: () -> Void
    let remove: () -> Void

    /// The car they share, else none.
    private var commonCar: String {
        let cars = Set(entries.map(\.car))
        return cars.count == 1 ? cars.first ?? "" : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entries.count) Sessions Selected").font(.title3.weight(.semibold))
                    .accessibilityIdentifier("logbook.selection.title")
                Text(summary).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("logbook.selection.summary")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Car").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        CommittingTextField(
                            "Car", text: Binding(get: { commonCar }, set: setCar),
                            prompt: Text(Set(entries.map(\.car)).count > 1 ? "Several cars" : "What was driven")
                        )
                        .labelsHidden()
                        // Another selection is another field, not this one's typing carried over.
                        .id(Set(entries.map(\.id)))
                        .accessibilityIdentifier("logbook.selection.car")
                        if !knownCars.isEmpty {
                            Menu {
                                ForEach(knownCars, id: \.self) { car in Button(car) { setCar(car) } }
                            } label: {
                                Label("Cars in the Logbook", systemImage: "car")
                            }
                            .labelStyle(.iconOnly).fixedSize()
                            .accessibilityLabel("Cars in the Logbook")
                            .help("Give all of them a car the logbook already knows")
                            .accessibilityIdentifier("logbook.selection.car.known")
                        }
                    }
                }
            }
            .font(.callout)
            List(entries) { entry in
                Text(Self.line(entry)).font(.callout)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 120)
            .accessibilityIdentifier("logbook.selection.list")
            HStack {
                MoveToDayMenu(entries: entries, days: days, move: move, moveToOwnDays: moveToOwnDays)
                    .fixedSize()
                    .help("Put all of them on another day, with the clips that are their picture")
                Spacer()
                Button("Remove \(entries.count) Sessions", role: .destructive, action: remove)
                    .help("Take them out of the logbook; no file is touched, and Edit ▸ Undo brings them back")
                    .accessibilityIdentifier("logbook.selection.remove")
            }
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// "On 2 days at 1 circuit".
    private var summary: String {
        let days = Set(entries.compactMap(\.trackDayID)).count
        let circuits = Set(entries.map(LogbookFilter.circuitKey(of:))).subtracting([""]).count
        var text = "On \(days) day\(days == 1 ? "" : "s")"
        if circuits > 0 { text += " at \(circuits) circuit\(circuits == 1 ? "" : "s")" }
        return text
    }

    /// "23 Aug 2026, 10:15 · Sonoma · Miata".
    static func line(_ entry: LogbookEntry) -> String {
        var parts = [
            entry.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No date", entry.circuitTitle,
        ]
        if !entry.car.isEmpty { parts.append(entry.car) }
        return parts.joined(separator: " · ")
    }
}
