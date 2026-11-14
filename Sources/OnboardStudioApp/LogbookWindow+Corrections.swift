import AppKit
import ProjectModel
import SwiftUI
import UniformTypeIdentifiers

/// Putting the Logbook right (#454): several sessions selected at once, a right-click menu, Move
/// to Day by menu or by dragging rows onto a day in the sidebar, and every edit a step of Edit ▸
/// Undo — so a removal no longer asks first.
extension LogbookWindow {
    /// The sessions selected that the sidebar and the search let through, in the table's order.
    var selectedEntries: [LogbookEntry] { shown.filter { selection.contains($0.id) } }

    func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        model.remove(ids, undo: undoManager)
        selection.subtract(ids)
    }

    func removeDay(_ day: TrackDay) {
        model.removeDay(day, undo: undoManager)
        if case .day(let id, _) = scope, id == day.id { scope = .all }
    }

    func move(_ ids: [UUID], to day: TrackDay) {
        model.move(ids, toDay: day.id, undo: undoManager)
    }

    func moveToOwnDays(_ ids: [UUID]) {
        model.moveToOwnDays(ids, undo: undoManager)
    }

    /// A row's right-click menu: what is done with one session, then what can be done to all of
    /// those clicked.
    @ViewBuilder func sessionMenu(for ids: Set<UUID>) -> some View {
        let entries = shown.filter { ids.contains($0.id) }
        if entries.count == 1, let entry = entries.first {
            Button("New Project from Session") { newProject(fromSession: entry, template: LogbookModel.lastTemplate()) }
            Button("Coach…") { coach(entry) }
            Button("Replay…") { ReplayWindow.open(openWindow, entry: entry) }
            Button("Show in Finder") {
                if let url = entry.resolveFile() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
        }
        if !entries.isEmpty {
            MoveToDayMenu(
                entries: entries, days: model.days, move: { move(entries.map(\.id), to: $0) },
                moveToOwnDays: { moveToOwnDays(entries.map(\.id)) })
            if !model.knownCars.isEmpty {
                Menu("Car") {
                    ForEach(model.knownCars, id: \.self) { car in
                        Button(car) { model.setCar(car, ofSessions: entries.map(\.id), undo: undoManager) }
                    }
                }
            }
            Divider()
            Button(Self.removeTitle(entries.count)) { remove(entries.map(\.id)) }
        }
    }

    /// "Remove from Logbook", or "Remove 3 Sessions from Logbook".
    static func removeTitle(_ count: Int) -> String {
        count == 1 ? "Remove from Logbook" : "Remove \(count) Sessions from Logbook"
    }

    /// The detail column with several sessions selected: how many, and what can be done to all.
    var selectionDetail: some View {
        let entries = selectedEntries
        let ids = entries.map(\.id)
        return SessionsSelectionDetail(
            entries: entries, days: model.days, knownCars: model.knownCars,
            setCar: { model.setCar($0, ofSessions: ids, undo: undoManager) },
            move: { move(ids, to: $0) }, moveToOwnDays: { moveToOwnDays(ids) }, remove: { remove(ids) })
    }
}

/// Move to Day ▸ (#454): the day the sessions' own dates say, then the days at their circuit, then
/// every other day — a session filed on the wrong day used to be removed and added again.
struct MoveToDayMenu: View {
    let entries: [LogbookEntry]
    let days: [TrackDay]
    let move: (TrackDay) -> Void
    let moveToOwnDays: () -> Void

    /// The day all the sessions are on, if they share one: not a place to move them.
    private var current: UUID? {
        let ids = Set(entries.map(\.trackDayID))
        guard ids.count == 1, let only = ids.first else { return nil }
        return only
    }

    /// The circuit they were all driven at, if one.
    private var circuit: String? {
        // The venue, not the course (#552): days are at a circuit or a car park, not on a layout.
        let keys = Set(entries.map(LogbookFilter.venueKey(of:)))
        guard keys.count == 1, let key = keys.first, !key.isEmpty else { return nil }
        return key
    }

    private var candidates: [TrackDay] { days.filter { $0.id != current } }
    private var here: [TrackDay] { candidates.filter { circuit != nil && $0.circuitKey == circuit } }
    private var others: [TrackDay] { candidates.filter { circuit == nil || $0.circuitKey != circuit } }

    var body: some View {
        Menu("Move to Day") {
            Button(entries.count == 1 ? "Its Own Day" : "Their Own Days", action: moveToOwnDays)
                .help("The day the session's own date and circuit say, made if there is none")
            if !here.isEmpty {
                Section(here.first?.title ?? "") {
                    ForEach(here) { day in Button(day.label) { move(day) } }
                }
            }
            if !others.isEmpty {
                if here.isEmpty {
                    Divider()
                    ForEach(others) { day in Button(day.label) { move(day) } }
                } else {
                    Menu("Other Days") {
                        ForEach(others) { day in Button(day.label) { move(day) } }
                    }
                }
            }
        }
        .accessibilityIdentifier("logbook.moveToDay")
    }
}

/// A session dragged from the table onto a day in the sidebar (#454): only its id, inside the app.
struct LogbookSessionDrag: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .logbookSession)
    }
}

extension UTType {
    /// Declared in the app's Info.plist; nothing outside the app reads it.
    nonisolated static let logbookSession = UTType(
        exportedAs: "com.freedenizen.onboardstudio.logbook-session", conformingTo: .data)
}
