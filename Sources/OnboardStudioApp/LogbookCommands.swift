import AppKit
import ProjectModel
import SwiftUI

/// What the Logbook offers the menu bar while it is the window in front (#450): the session whose
/// detail is on show, the window's view, and the window's own actions — so a menu command does to a
/// session exactly what the button at the foot of its detail does.
struct LogbookCommandContext {
    /// The session whose detail is on show; `nil` when none is, or several are selected.
    var session: LogbookEntry?
    /// Every session selected (#454): what Move to Day and Remove act on.
    var selected: [LogbookEntry]
    var days: [TrackDay]
    var view: Binding<LogbookWindow.LogbookView>
    /// Whether the table of sessions has the keyboard: ⌘⌫ removes a session only then, and
    /// deletes to the start of the line in a text field as it does everywhere else.
    var sessionsHaveFocus: Bool
    var hasProject: Bool
    var hasClips: Bool
    var comparisons: [(title: String, entry: LogbookEntry)]
    var newProject: (LogbookEntry, ProjectTemplate?) -> Void
    var addToProject: (LogbookEntry) -> Void
    var coach: (LogbookEntry) -> Void
    var replay: (LogbookEntry) -> Void
    var compare: (LogbookEntry, LogbookEntry) -> Void
    var debrief: (LogbookEntry) -> Void
    var remove: ([LogbookEntry]) -> Void
    var move: ([LogbookEntry], TrackDay) -> Void
    var moveToOwnDays: ([LogbookEntry]) -> Void
    var findSessions: () -> Void
    /// Help ▸ Take the Tour and Show Getting Started, the Logbook's own (#452).
    var takeTour: () -> Void
    var showGettingStarted: () -> Void
    var addFiles: () -> Void
    var exportLogbook: (_ includingFiles: Bool) -> Void
    var exportCSV: (_ laps: Bool) -> Void
    var exportMarkdown: () -> Void
    var importLogbook: () -> Void
}

struct LogbookCommandsKey: FocusedValueKey {
    typealias Value = LogbookCommandContext
}

extension FocusedValues {
    var logbook: LogbookCommandContext? {
        get { self[LogbookCommandsKey.self] }
        set { self[LogbookCommandsKey.self] = newValue }
    }
}

/// The Logbook in the menu bar (#450). The Session menu acts on the session whose detail is on
/// show, as Mail's Message menu and Music's Song menu act on what is selected; File, Edit and View
/// gain the window's own items while it is in front, as they do for the attribute window and
/// Coaching. Keys are recorded in docs/conventions.md.
///
/// A dimmed menu item still takes its key and does nothing with it, and of two items on one key a
/// dimmed one listed first blocks the other (measured with `NSMenu.performKeyEquivalent`). So a key
/// another window or a text field also uses — ⌃⌘C, ⌘1, ⌘⌫ — is given only while it is this
/// window's to use.
struct LogbookCommands: Commands {
    @FocusedValue(\.logbook) private var logbook
    @FocusedValue(\.editor) private var editor
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Session") { SessionMenuItems(logbook: logbook) }
        CommandGroup(after: .importExport) {
            // A whole day's files into the logbook, from wherever the user is: on the day chosen in
            // the Logbook, else each on the day its date and circuit say (#346, #450). It lives in
            // File with the other things that bring files in; the Project menu is full (#375).
            Button("Add Files to Logbook…", action: addFiles)
        }
        CommandGroup(after: .importExport) {
            // The Logbook's own exports, while it is in front, as Coaching's are (#450).
            if let logbook {
                Button("Export Logbook…") { logbook.exportLogbook(false) }
                Button("Export Logbook with Data Files…") { logbook.exportLogbook(true) }
                Button("Export Sessions as CSV…") { logbook.exportCSV(false) }
                Button("Export Laps as CSV…") { logbook.exportCSV(true) }
                Button("Export Logbook as Markdown…", action: logbook.exportMarkdown)
                Button("Import Logbook Export…", action: logbook.importLogbook)
            }
        }
        CommandGroup(after: .textEditing) {
            // A toolbar search field does not take ⌘F by itself (#200).
            if let logbook {
                Button("Find Sessions", action: logbook.findSessions).keyboardShortcut("f", modifiers: .command)
            }
        }
        CommandGroup(before: .toolbar) {
            // ⌘1–⌘3, as Photos switches Years, Months and All Photos; only while the Logbook is in
            // front, so the attribute window's ⌘1 and ⌘2 stay its own.
            if let view = logbook?.view {
                Toggle("Sessions", isOn: view.selecting(.sessions)).keyboardShortcut("1", modifiers: .command)
                Toggle("Trends", isOn: view.selecting(.trends)).keyboardShortcut("2", modifiers: .command)
                Toggle("Season", isOn: view.selecting(.season)).keyboardShortcut("3", modifiers: .command)
                Divider()
            }
        }
    }

    private func addFiles() {
        if let logbook {
            logbook.addFiles()
        } else if let editor {
            editor.requestTrackDay()
        } else {
            // No window to put the sheet on: the Logbook opens and shows it.
            let urls = OpenPanels.chooseTrackDay()
            guard !urls.isEmpty else { return }
            LogbookModel.shared.trackDayRequest = TrackDayRequest(urls: urls)
            LogbookWindow.open(openWindow)
        }
    }
}

/// The Session menu: the buttons at the foot of a session's detail, in the menu bar.
private struct SessionMenuItems: View {
    let logbook: LogbookCommandContext?

    private var session: LogbookEntry? { logbook?.session }

    var body: some View {
        // ⇧⌘N, as Music makes a playlist from the songs selected.
        Button("New Project from Session") { act { logbook?.newProject($0, LogbookModel.lastTemplate()) } }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(session == nil)
        Menu("New Project from Session with Template") {
            Button("Blank Project") { act { logbook?.newProject($0, nil) } }
            Divider()
            ForEach(LogbookModel.templates(), id: \.name) { template in
                Button(template.name) { act { logbook?.newProject($0, template) } }
            }
        }
        .disabled(session == nil)
        Button("Add to Current Project") { act { logbook?.addToProject($0) } }
            .disabled(session == nil || logbook?.hasProject != true)
        Divider()
        // ⌃⌘C, the key of Project ▸ Coaching…: each window's own item holds it while it is in front.
        Button("Coach…") { act { logbook?.coach($0) } }
            .keyboardShortcut("c", modifiers: [.command, .control], when: logbook != nil)
            .disabled(session == nil)
        // No key: ⌃⌘R opens the Replay window from the Window menu.
        Button("Replay…") { act { logbook?.replay($0) } }
            .disabled(session == nil)
        Menu("Compare With") {
            ForEach(logbook?.comparisons ?? [], id: \.entry.id) { choice in
                Button(choice.title) { act { logbook?.compare($0, choice.entry) } }
            }
        }
        .disabled(session == nil || logbook?.comparisons.isEmpty != false)
        Button("Export Coaching Debrief…") { act { logbook?.debrief($0) } }
            .disabled(session == nil || logbook?.hasClips != true)
        Divider()
        // ⇧⌘R, as Music shows where a song's file is.
        Button("Show in Finder") {
            act { if let url = $0.resolveFile() { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(session == nil)
        Divider()
        // On every session selected (#454).
        MoveToDayMenu(
            entries: selected, days: logbook?.days ?? [], move: { logbook?.move(selected, $0) },
            moveToOwnDays: { logbook?.moveToOwnDays(selected) }
        )
        .disabled(selected.isEmpty)
        Divider()
        // ⌘⌫, as the Finder moves to the Trash and Photos deletes; only while the sessions have the
        // keyboard, so it still deletes to the start of a line while a note is being typed. No
        // question first: Edit ▸ Undo brings them back (#454).
        Button(LogbookWindow.removeTitle(max(selected.count, 1))) { logbook?.remove(selected) }
            .keyboardShortcut(.delete, modifiers: .command, when: logbook?.sessionsHaveFocus == true)
            .disabled(selected.isEmpty)
    }

    private var selected: [LogbookEntry] { logbook?.selected ?? [] }

    private func act(_ body: (LogbookEntry) -> Void) {
        if let session { body(session) }
    }
}

extension View {
    /// The item's key while `active`, and none otherwise: a dimmed menu item still takes its key
    /// and does nothing with it (#450), so a command whose window is not in front lets the key go
    /// to the one that is.
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command, when active: Bool) -> some View {
        keyboardShortcut(active ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }
}
