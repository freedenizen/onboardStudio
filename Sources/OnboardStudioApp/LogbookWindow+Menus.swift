import ProjectModel
import SwiftUI

/// The Logbook's toolbar, and what it hands the menu bar while it is in front (#450).
extension LogbookWindow {
    /// The session on show and the window's actions, for `LogbookCommands`: the same closures the
    /// detail's buttons and the toolbar call, so a menu item and its button cannot drift apart.
    var commandContext: LogbookCommandContext {
        let entry = shownEntry
        return LogbookCommandContext(
            session: entry, view: $view, sessionsHaveFocus: sessionsFocused, hasProject: active.editor != nil,
            hasClips: entry.map { !model.clips(of: $0).isEmpty } ?? false,
            comparisons: entry.map { comparisons(for: $0) } ?? [],
            newProject: { newProject(fromSession: $0, template: $1) },
            addToProject: { addToCurrentProject($0) },
            coach: { CoachingWindow.open(openWindow, coaching: $0) },
            replay: { ReplayWindow.open(openWindow, entry: $0) },
            compare: { compare($0, with: $1) },
            debrief: { model.openAsProject($0, template: ProjectTemplate.coachingDebrief, then: .debrief) },
            remove: { confirmRemoval = $0 },
            findSessions: { searchFocused = true },
            addFiles: addFiles,
            exportLogbook: { exportLogbook(includingFiles: $0) },
            exportCSV: { exportCSV(laps: $0) },
            exportMarkdown: exportMarkdown,
            importLogbook: importLogbook)
    }

    /// Over the session's column (#503): what is done with the session chosen.
    @ToolbarContentBuilder var sessionToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "newProject", placement: .primaryAction) {
            newProjectMenu
                .help(newProjectHelp)
                .accessibilityLabel("New Project")
                .accessibilityIdentifier("logbook.newProject")
        }
    }

    /// Over the list's column, customizable (#450): View ▸ Customize Toolbar… offers Icon and Text
    /// for the buttons that are otherwise icons alone, and lets the user drop the ones they never
    /// use.
    @ToolbarContentBuilder var logbookToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "view", placement: .principal) {
            Picker("View", selection: $view) {
                ForEach(LogbookView.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help(
                "The sessions; how the lap times and corners moved across visits to a circuit; "
                    + "or a year on one page (⌘1, ⌘2, ⌘3)"
            )
            .accessibilityIdentifier("logbook.view")
        }
        .customizationBehavior(.disabled)
        ToolbarItem(id: "newTrackDay", placement: .primaryAction) {
            Button("New Track Day…", systemImage: "calendar.badge.plus") {
                model.newDayRequested = true
            }
            .help("Begin a day: the date, the circuit, the car — before any file exists (⌥⌘N)")
            .accessibilityIdentifier("logbook.newTrackDay")
        }
        ToolbarItem(id: "addFiles", placement: .primaryAction) {
            Button("Add Files…", systemImage: "doc.badge.plus", action: addFiles)
                .help(
                    "Enter a day's telemetry files and camera clips: on the day chosen in the sidebar, "
                        + "else each on the day its date and circuit say"
                )
                .accessibilityIdentifier("logbook.addTrackDay")
        }
        ToolbarItem(id: "transfer", placement: .primaryAction) {
            Menu {
                Button("Export Logbook…") { exportLogbook(includingFiles: false) }
                Button("Export Logbook with Data Files…") { exportLogbook(includingFiles: true) }
                Divider()
                Button("Export Sessions as CSV…") { exportCSV(laps: false) }
                Button("Export Laps as CSV…") { exportCSV(laps: true) }
                Button("Export Logbook as Markdown…") { exportMarkdown() }
                Divider()
                // A logbook exported from this app, read back in: not data files, which are Add Files….
                Button("Import Logbook Export…") { importLogbook() }
            } label: {
                Label("Export or Import", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export or Import")
            .help("Take the logbook with you as files, as CSV or Markdown, or read an export back in")
            .accessibilityIdentifier("logbook.transfer")
        }
    }
}
