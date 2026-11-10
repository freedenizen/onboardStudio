import AppKit
import MediaKit
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
        model.note(car: day.car)
        model.reload()
        scope = .day(id: day.id, title: day.label)
        view = .sessions
    }

    /// The circuit the trends are of: the one chosen in the sidebar, else the only one there is.
    var trendsCircuit: (id: String, title: String)? {
        if case .circuit(let id, let title) = scope { return (id, title) }
        if let day = selectedDay, let id = day.circuitID { return (id, day.title) }
        let circuits = LogbookFilter.circuits(in: model.entries)
        if circuits.count == 1, case .circuit(let id, let title) = circuits[0].scope { return (id, title) }
        return nil
    }

    // MARK: - A drop (#468)

    /// Shown while files are dragged over the window: that it takes them, and where they will go.
    var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                Label(
                    selectedDay.map { "Add to \($0.label)" } ?? "Add to the Logbook, each file on its own day",
                    systemImage: "plus.circle.fill"
                )
                .font(.headline)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 24)
            }
            .padding(4)
            .allowsHitTesting(false)
            .accessibilityIdentifier("logbook.dropHighlight")
    }

    // MARK: - Sidebar

    var sidebar: some View {
        List(selection: Binding(get: { scope }, set: { if let new = $0 { scope = new } })) {
            Label("All Sessions", systemImage: "book.closed").tag(LogbookScope.all)
                .accessibilityIdentifier("logbook.scope.all")
            if !model.days.isEmpty {
                TrackDaySidebarSection(
                    groups: LogbookFilter.days(in: model.entries, days: model.days), days: model.days,
                    openYears: Bindable(model).openYears)
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

    /// A new project laid out with `template` (#395), as File ▸ New from Template does.
    func newProject(from template: ProjectTemplate) {
        PendingTemplate.shared.template = template
        NSDocumentController.shared.newDocument(nil)
    }

    /// A new project from the session (#394), laid out with `template`; the next New Project on a
    /// session uses the same layout, as it does after a choice in the session's own menu.
    func newProject(fromSession entry: LogbookEntry, template: ProjectTemplate?) {
        UserDefaults.standard.set(template?.name ?? "", forKey: "logbook.projectTemplate")
        openAsProject(entry, template: template)
    }

    /// The toolbar's New Project (#395): a blank project, the templates, an existing project, the
    /// Templates window and the sample. With a session selected the project is made from that
    /// session, as the button in its detail makes it, and the menu names the session (#449): the
    /// same two words did two different things a few hundred points apart.
    var newProjectMenu: some View {
        // Where a project starts, now that the Logbook is the window at launch (#395).
        Menu {
            if let entry = shownEntry {
                Section("From \(sessionName(entry))") {
                    Button("Blank Project") { newProject(fromSession: entry, template: nil) }
                    ForEach(LogbookModel.templates(), id: \.name) { template in
                        Button(template.name) { newProject(fromSession: entry, template: template) }
                    }
                }
                Section {
                    Button("New Project Without a Session") { NSDocumentController.shared.newDocument(nil) }
                }
            } else {
                Button("Blank Project") { NSDocumentController.shared.newDocument(nil) }
                Section("From a Template") {
                    ForEach(LogbookModel.templates(), id: \.name) { template in
                        Button(template.name) { newProject(from: template) }
                    }
                }
            }
            Divider()
            Button("Open Project…") { NSDocumentController.shared.openDocument(nil) }
            Button("Templates…") { openWindow(id: TemplatesWindow.windowID) }
            Button("Open the Sample Project") { SampleProject.open() }.disabled(
                !SampleProject.isAvailable)
        } label: {
            Label("New Project", systemImage: "doc.badge.plus")
        }
    }

    /// What the toolbar's New Project will make, for its help tag.
    var newProjectHelp: String {
        shownEntry == nil
            ? "A blank project; the menu offers the templates, an existing project and the sample"
            : "A new project from the selected session, or one without it; the menu also offers an "
                + "existing project and the sample"
    }

    /// "Sonoma Raceway, Aug 23, 2026": a session in the few words a menu has room for.
    private func sessionName(_ entry: LogbookEntry) -> String {
        guard let date = entry.date else { return entry.title }
        return "\(entry.title), \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Against another session (#397)

    /// The logbook's other sessions at the entry's circuit: the personal best here and the last
    /// visit first, then the rest by date.
    func comparisons(for entry: LogbookEntry) -> [(title: String, entry: LogbookEntry)] {
        let candidates = LogbookReferences.sessions(
            at: LogbookFilter.circuitKey(of: entry), in: model.entries, excluding: entry.file.contentHash)
        var choices: [(title: String, entry: LogbookEntry)] = []
        if let best = LogbookReferences.personalBest(in: candidates) {
            choices.append(("Personal Best Here — \(LogbookReferences.phrase(for: best, lap: nil))", best))
        }
        if let last = LogbookReferences.lastVisit(in: candidates), last.id != choices.first?.entry.id {
            choices.append(("Last Visit — \(LogbookReferences.phrase(for: last, lap: nil))", last))
        }
        for candidate in candidates where !choices.contains(where: { $0.entry.id == candidate.id }) {
            choices.append((CoachingContent.candidateTitle(candidate), candidate))
        }
        return choices
    }

    /// Coach the session with `other` as the reference: the choice goes on the entry, as the
    /// window would keep it, and the window opens on it.
    func compare(_ entry: LogbookEntry, with other: LogbookEntry) {
        var changed = entry
        var settings = entry.coaching ?? CoachingSettings(dataInputID: InputID(entry.id))
        settings.reference = .logbook(entryID: other.id, lap: nil)
        changed.coaching = settings
        model.save(changed)
        CoachingWindow.open(openWindow, entry: changed)
    }
}
