import AppKit
import ProjectModel
import SwiftUI

/// The window's ways into a day (#393): which day is chosen, files onto it, a day begun.
extension LogbookWindow {
    /// The day the sidebar has chosen, if it is one.
    var selectedDay: TrackDay? {
        guard case .day(let id, _) = scope else { return nil }
        return model.days.first { $0.id == id }
    }

    /// Files into the logbook: onto the chosen day, else each onto its own (#393).
    func addFiles() {
        let day = selectedDay
        let urls = OpenPanels.chooseTrackDay(for: day)
        if !urls.isEmpty { model.trackDayRequest = TrackDayRequest(urls: urls, day: day) }
    }

    func create(_ day: TrackDay) {
        try? AppLogbook.shared.saveDay(day)
        // A car typed for the first time joins the garage.
        if !day.car.isEmpty, !model.cars.contains(where: { $0.name.caseInsensitiveCompare(day.car) == .orderedSame }) {
            try? AppLogbook.shared.saveCars(model.cars + [Car(name: day.car)])
        }
        model.reload()
        scope = .day(id: day.id, title: day.label)
        view = .sessions
    }

    // MARK: - Sidebar

    var sidebar: some View {
        List(selection: Binding(get: { scope }, set: { if let new = $0 { scope = new } })) {
            Label("All Sessions", systemImage: "book.closed").tag(LogbookScope.all)
                .accessibilityIdentifier("logbook.scope.all")
            if !model.days.isEmpty {
                TrackDaySidebarSection(
                    groups: LogbookFilter.days(in: model.entries, days: model.days), days: model.days)
            }
            let circuits = LogbookFilter.circuits(in: model.entries)
            if !circuits.isEmpty {
                Section("Circuits") {
                    ForEach(circuits, id: \.scope) { group in
                        Label(group.scope.title, systemImage: "flag.checkered").badge(group.count).tag(group.scope)
                    }
                }
            }
            let cars = LogbookFilter.cars(in: model.entries)
            if !cars.isEmpty {
                Section("Cars") {
                    ForEach(cars, id: \.scope) { group in
                        Label(group.scope.title, systemImage: "car").badge(group.count).tag(group.scope)
                    }
                }
            }
            let years = LogbookFilter.years(in: model.entries)
            if !years.isEmpty {
                Section("Years") {
                    ForEach(years, id: \.scope) { group in
                        Label(group.scope.title, systemImage: "calendar").badge(group.count).tag(group.scope)
                    }
                }
            }
        }
        .accessibilityIdentifier("logbook.sidebar")
    }

}
