import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit
import UniformTypeIdentifiers

/// The logbook as the app holds it, for the window (#347): read once, re-read after anything
/// that writes to it, so the table never shows a stale season.
@MainActor @Observable final class LogbookModel {
    static let shared = LogbookModel()

    private(set) var entries: [LogbookEntry] = []
    /// The track days (#392), newest first; every entry is on one once `reload` has run.
    private(set) var days: [TrackDay] = []
    private(set) var cars: [Car] = []
    /// `reload` has read the logbook at least once.
    private(set) var hasLoaded = false
    /// The plan kept for each circuit (#330), by its catalogue id: what its card shows (#460).
    var plans: [String: NextSessionPlan] = [:]
    /// What the driver is aiming for at each circuit (#461).
    var goals: [Goal] = []
    /// The Logbook window's Undo, for a Logbook edit made in another window: a plan saved for the
    /// circuit in the Coaching window is a step of it, as the card's own edits are (#543).
    @ObservationIgnored weak var windowUndo: UndoManager?
    /// New Track Day Here… on a circuit's card: the circuit the sheet begins with (#460).
    var newDayCircuit: String?
    /// Sessions read in for coaching references (#352), by entry, kept for the app's life.
    private var sessions: [UUID: TelemetrySession] = [:]
    /// Files on their way into the logbook, shown by the window's sheet (#393).
    var trackDayRequest: TrackDayRequest?
    /// File ▸ New Track Day… asked for the sheet (#393).
    var newDayRequested = false
    /// The Logbook's tour (#452): which callout is up, if any.
    var tourStep: Int?
    /// Show Trends or Show Season in an import's report (#459), for the window to go to.
    var requestedView: ImportProgress.Destination?
    /// The day chosen in the sidebar, for the Testing menu and the ways in.
    private(set) var selectedDay: TrackDay?
    /// The years of the sidebar's Track Days that are folded open, once there is more than one.
    /// Choosing a day opens its year (#485); folding is otherwise the user's.
    var openYears: Set<Int> = []

    /// The sidebar chose `day`, or none. Its year is opened, so the row that is selected is not
    /// folded out of sight when the logbook comes to span a second year (#485).
    func choose(_ day: TrackDay?) {
        selectedDay = day
        if let year = day?.year { openYears.insert(year) }
    }

    private var carComparisons: [String: CarVersusCar] = [:]

    /// Two cars' best laps compared (#354), read once per pair of sessions.
    func carComparison(first: LogbookEntry, firstCar: String, second: LogbookEntry, secondCar: String) async
        -> CarVersusCar?
    {
        // Written in the app's units, as the chart beside it is drawn (#464).
        let setting = SpeedUnitSetting(rawValue: UserDefaults.standard.value(for: Preferences.speedUnit))
        let units = CoachingUnits.following(setting ?? .automatic)
        let key = "\(first.id)|\(second.id)|\(units.speed.symbol)"
        if let cached = carComparisons[key] { return cached }
        let made = await Task.detached(priority: .userInitiated) {
            CarVersusCar.make(first: first, firstCar: firstCar, second: second, secondCar: secondCar, units: units)
        }.value
        if let made { carComparisons[key] = made }
        return made
    }

    /// The entry's session, read once off the main thread.
    func session(for entry: LogbookEntry) async -> TelemetrySession? {
        if let cached = sessions[entry.id] { return cached }
        let loaded = await Task.detached(priority: .userInitiated) { LogbookReferences.load(entry) }.value
        if let loaded { sessions[entry.id] = loaded }
        return loaded
    }

    func reload() {
        let logbook = AppLogbook.shared
        // Entries from before days existed are put on one, by their date and circuit.
        try? logbook.ensureDays()
        entries = logbook.entries()
        days = logbook.days()
        // A name put right on a day or a session leaves the garage with it, unless it has notes (#490).
        try? logbook.tidyGarage(entries: entries, days: days)
        cars = logbook.cars()
        reloadPlans()
        goals = logbook.goals()
        hasLoaded = true
    }

    /// Writes an edited day — its car, driver, conditions, notes, clips — and shows it. A change
    /// of car or driver goes to the sessions that took them from the day (#453). One step of Undo
    /// in the Logbook window, named for the field (#454).
    func saveDay(_ day: TrackDay, undo: UndoManager? = nil) {
        let name = days.first { $0.id == day.id }.map { LogbookEditName.of($0, day) } ?? "Change Track Day"
        edit(name, undo: undo) { logbook in
            try logbook.updateDay(day)
            try logbook.addToGarage(day.car)
        }
    }

    /// Writes an edited entry — its car and driver (#453), its conditions and notes (#348) — and
    /// shows it; with the Logbook window's undo manager, as a step of its Undo (#454).
    func save(_ entry: LogbookEntry, undo: UndoManager? = nil) {
        let name = entries.first { $0.id == entry.id }.map { LogbookEditName.of($0, entry) } ?? "Change Session"
        edit(name, undo: undo) { logbook in
            try logbook.save(entry)
            try logbook.addToGarage(entry.car)
        }
    }

    // MARK: - Into a project

    /// A new project with the session's data file, its clips and `template` (#394), showing
    /// `then` once it is open (#396).
    func openAsProject(_ entry: LogbookEntry, template: ProjectTemplate?, then: LogbookOpenRequest.Then? = nil) {
        guard entry.resolveFile() != nil else { return }
        PendingLogbookOpen.shared.request = LogbookOpenRequest(
            entry: entry, clips: clipURLs(of: entry), template: template, then: then)
        NSDocumentController.shared.newDocument(nil)
    }

    /// The clips of the session's day that are its picture, in the order they were recorded.
    func clips(of entry: LogbookEntry) -> [ClipRecord] {
        let clips = days.first { $0.id == entry.trackDayID }?.clips.filter { $0.sessionID == entry.id } ?? []
        return clips.sorted { ($0.recordedAt ?? .distantPast, $0.path) < ($1.recordedAt ?? .distantPast, $1.path) }
    }

    /// Each clip's files that still exist, chapters after their first.
    func clipURLs(of entry: LogbookEntry) -> [URL] {
        clips(of: entry).flatMap { clip -> [URL] in
            guard let first = clip.resolveFile() else { return [] }
            return [first]
                + clip.chapterPaths.map { URL(fileURLWithPath: $0) }.filter {
                    FileManager.default.fileExists(atPath: $0.path)
                }
        }
    }

    /// The built-in templates and the user's own, as New Project from Template offers them.
    static func templates() -> [ProjectTemplate] {
        ProjectTemplate.builtIn + TemplateLibrary.app.entries().compactMap { try? TemplateLibrary.app.load($0) }
    }

    /// The template the last New Project used (Classic Dash to begin with), `nil` for blank.
    static func lastTemplate() -> ProjectTemplate? {
        let name = UserDefaults.standard.string(forKey: "logbook.projectTemplate") ?? "Classic Dash"
        return templates().first { $0.name == name }
    }
}

/// What a new project is made of from the logbook (#394): the session's data file, the clips
/// that are its picture, a template to lay it out, and what to show once it is open.
struct LogbookOpenRequest {
    enum Then { case coaching, debrief }
    let entry: LogbookEntry
    var clips: [URL] = []
    var template: ProjectTemplate?
    var then: Then?
}

/// Hands a session to the next editor that appears (New Project).
@MainActor
final class PendingLogbookOpen {
    static let shared = PendingLogbookOpen()
    var request: LogbookOpenRequest?
}

/// Every track day in one place (#347): a sidebar of circuits, cars and years, a sortable,
/// searchable table of sessions, and a detail pane with the laps and the way into a project.
struct LogbookWindow: View {
    static let windowID = "logbook"

    @SceneStorage("logbook.scope") private var storedScope = "all"
    /// Sessions, or the trends across visits (#353).
    @SceneStorage("logbook.view") var view: LogbookView = .sessions

    enum LogbookView: String, CaseIterable, Identifiable {
        case sessions, trends, season
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sessions: "Sessions"
            case .trends: "Trends"
            case .season: "Season"
            }
        }
    }
    @State var scope: LogbookScope = .all
    @State private var search = ""
    /// The sessions selected: several at once, to correct a mistaken import in one go (#454).
    @State var selection: Set<UUID> = []
    @State private var sortOrder = [KeyPathComparator(\LogbookEntry.date, order: .reverse)]
    /// The car header's Rename… (#490).
    @State var renamingCar: CarRename?
    /// The window's, for the Logbook's edits to be steps of Edit ▸ Undo (#454).
    @Environment(\.undoManager) var undoManager
    /// Getting Started in the detail column, and what it remembers (#452).
    @AppStorage(Preferences.showLogbookGettingStarted.key) var showGettingStarted = true
    @AppStorage(Preferences.logbookCoached.key) var coached = false
    @AppStorage(Preferences.logbookSawProgress.key) var sawProgress = false
    @AppStorage(Preferences.logbookTourSeen.key) private var tourSeen = false
    /// What the last export or import did, under the table (#350).
    @State var message: String?
    /// Files are being dragged over the window (#468).
    @State var isDropTarget = false
    @Environment(\.openWindow) var openWindow
    @Bindable var model = LogbookModel.shared
    var active = ActiveEditor.shared
    /// The toolbar's search field and the table of sessions have the keyboard: Edit ▸ Find
    /// Sessions puts it in the one, and Session ▸ Remove from Logbook… takes ⌘⌫ only from the
    /// other (#450).
    @FocusState var searchFocused: Bool
    @FocusState var sessionsFocused: Bool

    static func open(_ openWindow: OpenWindowAction) { openWindow(id: windowID) }

    var body: some View {
        browser
            .overlay { if isDropTarget { dropHighlight } }
            .overlay { LogbookTourOverlay(model: model) }
            // The session, the view and the window's actions, for the menu bar (#450).
            .focusedSceneValue(\.logbook, commandContext)
            .sheet(item: $model.trackDayRequest) { request in
                TrackDayImportSheet(editor: active.editor, request: request, undo: undoManager)
                    .onDisappear { model.reload() }
            }
            .sheet(
                isPresented: $model.newDayRequested, onDismiss: { model.newDayCircuit = nil },
                content: {
                    NewTrackDaySheet(
                        knownCars: model.knownCars,
                        knownCircuits: LogbookFilter.typedCircuits(in: model.entries, days: model.days),
                        lastDay: model.days.first, circuitKey: model.newDayCircuit, create: create)
                }
            )
            .modifier(carSheets)
            .onAppear {
                model.reload()
                // Once, as the editor's is: the app opens here (#452).
                if !tourSeen {
                    tourSeen = true
                    model.tourStep = 0
                }
            }
            .onChange(of: undoManager, initial: true) { model.windowUndo = undoManager }
            .onChange(of: view) { if view != .sessions { sawProgress = true } }
            .onChange(of: scope, initial: true) { model.choose(selectedDay) }
            .onChange(of: model.days) { followTheChosenDay() }
            .onChange(of: carRows) { followTheChosenCar() }
            .onChange(of: model.requestedView, initial: true) { showRequestedView() }
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                let day = selectedDay
                Task { @MainActor in
                    let urls = await Self.urls(from: providers)
                    if !urls.isEmpty { model.trackDayRequest = TrackDayRequest(urls: urls, day: day) }
                }
                return true
            }
    }

    /// Three columns, as Mail has (#503): the sidebar and what it narrows, the sessions — or their
    /// trends, or the season — and the session chosen. The toolbar follows the columns, so the
    /// list's buttons stay over the list and New Project over the session, however wide the
    /// session is dragged. The session was a pane of an `HSplitView` beside a two-column split
    /// view (#448), and the toolbar, laid out across the window, ran under its edge. The split view
    /// does not keep the session's width; the keeper in the column puts it back (#483).
    private var browser: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } content: {
            content
                .frame(minWidth: 460, minHeight: 420)
                .navigationSplitViewColumnWidth(min: 460, ideal: 660)
                .toolbar(id: "logbook") { logbookToolbar }
                .searchable(text: $search, placement: .toolbar, prompt: "Circuit, car, driver, notes")
                .searchFocused($searchFocused)
        } detail: {
            Group {
                if let entry = shownEntry {
                    detail(of: entry)
                } else if selectedEntries.count > 1 {
                    selectionDetail
                } else if showGettingStarted, !gettingStarted.allSatisfy(\.done) {
                    LogbookGettingStartedView(
                        steps: gettingStarted, perform: performGettingStarted, hide: { showGettingStarted = false })
                } else {
                    ContentUnavailableView(
                        "No Session Selected", systemImage: "flag.checkered",
                        description: Text("Choose a session to see its laps and conditions, and what to do with it."))
                }
            }
            .navigationSplitViewColumnWidth(
                min: LogbookDetailWidth.range.lowerBound, ideal: LogbookDetailWidth.range.lowerBound,
                max: LogbookDetailWidth.range.upperBound
            )
            .background(LogbookDetailWidthKeeper())
            .toolbar(id: "logbook.session") { sessionToolbar }
        }
        // No "Logbook" in the toolbar: in the narrowest window (989 points) the list's column is 460
        // wide, and the title, the view picker and the list's buttons needed about 560, so AppKit
        // pushed Add Files and Export over the session's edge (#503). The window keeps its title
        // for the Window menu and Mission Control; the sidebar and the view picker say where you are.
        .toolbar(removing: .title)
    }

    // MARK: - Table and detail

    var shown: [LogbookEntry] {
        LogbookFilter.apply(model.entries, scope: scope, search: search).sorted(using: sortOrder)
    }

    /// The session whose detail is on screen: the one selected, while it is one of the sessions
    /// the sidebar and the search let through, on Trends and the Season too (#503). A session the
    /// sidebar or the search has taken out of the table has no detail and no buttons to press
    /// (#457). What New Project in the toolbar is about, too (#449).
    var shownEntry: LogbookEntry? {
        guard selection.count == 1, let entry = model.entries.first(where: { selection.contains($0.id) }),
            LogbookFilter.matches(entry, scope: scope), LogbookFilter.matches(entry, search: search)
        else { return nil }
        return entry
    }

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A session opened from Trends or the Season: selected among the sessions, with whatever
    /// would keep it out of the table — the sidebar's choice, a search — put aside.
    private func show(_ id: UUID) {
        if let entry = model.entries.first(where: { $0.id == id }) {
            if !LogbookFilter.matches(entry, scope: scope) { scope = .all }
            if !LogbookFilter.matches(entry, search: search) { search = "" }
        }
        selection = [id]
        view = .sessions
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty, model.days.isEmpty {
            ContentUnavailableView {
                Label("No Track Days Yet", systemImage: "book.closed")
            } description: {
                Text(
                    "The logbook keeps every track day: where and when, the car, every session and its laps. "
                        + "Begin a day, or add a day's files or folders.")
            } actions: {
                Button("New Track Day…") { model.newDayRequested = true }
                    .accessibilityIdentifier("logbook.empty.newTrackDay")
                Button("Add Files…", action: addFiles)
                Button("New Project") { NSDocumentController.shared.newDocument(nil) }
            }
        } else if view == .season {
            SeasonView(
                entries: model.entries, plans: (active.editor?.trackLibrary ?? TrackLibrary.app).all(),
                goals: model.goals, onOpen: show)
        } else if view == .trends {
            LogbookTrendsView(
                entries: model.entries, circuitKey: trendsCircuit?.id, circuitTitle: trendsCircuit?.title ?? "",
                goals: model.goals, onOpen: show)
        } else {
            VStack(spacing: 0) {
                if let day = selectedDay {
                    TrackDayHeader(
                        day: day, sessions: model.entries.filter { $0.trackDayID == day.id },
                        save: { model.saveDay($0, undo: undoManager) }, addSessions: addFiles,
                        remove: { removeDay(day) },
                        knownCircuits: LogbookFilter.typedCircuits(in: model.entries, days: model.days))
                    Divider()
                }
                carHeader
                circuitCard
                lapReadingOffer
                if shown.isEmpty, isSearching {
                    // Not an empty striped table (#457).
                    ContentUnavailableView.search(text: search).frame(maxHeight: .infinity)
                } else if shown.isEmpty, selectedCar != nil {
                    noSessionsInTheCar.frame(maxHeight: .infinity)
                } else {
                    LogbookTable(
                        entries: shown, bests: PersonalBests.badges(in: model.entries),
                        selection: $selection, sortOrder: $sortOrder
                    ) { ids in sessionMenu(for: ids) }
                    .focused($sessionsFocused)
                    // A click on a session gives the sessions the keyboard, as it does by itself on
                    // macOS 26 and not on macOS 27 (#509).
                    .background(TableClick(onRow: { sessionsFocused = true }))
                }
                if let message {
                    Divider()
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .accessibilityIdentifier("logbook.message")
                }
            }
        }
    }

    /// The selected session: its numbers, its laps, and what can be done with it.
    private func detail(of entry: LogbookEntry) -> some View {
        LogbookDetail(
            entry: entry, clips: model.clips(of: entry), hasProject: active.editor != nil,
            templates: LogbookModel.templates, newProject: { openAsProject(entry, template: $0) },
            coach: { coach(entry) },
            compare: { compare(entry, with: $0) }, comparisons: comparisons(for: entry),
            debrief: {
                model.openAsProject(entry, template: ProjectTemplate.coachingDebrief, then: .debrief)
            },
            replay: { ReplayWindow.open(openWindow, entry: entry) },
            addToProject: { addToCurrentProject(entry) },
            remove: { remove([entry.id]) },
            save: { model.save($0, undo: undoManager) },
            knownCars: model.knownCars,
            personalBest: PersonalBests.best(in: model.entries, circuitKey: circuitKey(of: entry)),
            visits: PersonalBests.trackDays(in: model.entries, circuitKey: circuitKey(of: entry)),
            otherCourses: otherCourses(than: entry),
            renameCourse: { name in entry.course.map { model.renameCourse($0.id, to: name, undo: undoManager) } },
            joinCourse: { model.move([entry.id], toCourse: $0, undo: undoManager) },
            separateCourse: { model.separateCourse([entry.id], undo: undoManager) }
        )
    }

    /// The courses another session could be on instead of this one's: those at its venue first.
    private func otherCourses(than entry: LogbookEntry) -> [CourseTag] {
        let venue = LogbookFilter.venueKey(of: entry)
        let here = Set(model.entries.filter { LogbookFilter.venueKey(of: $0) == venue }.compactMap(\.course?.id))
        let others = model.courses.filter { $0.id != entry.course?.id }
        return others.filter { here.contains($0.id) } + others.filter { !here.contains($0.id) }
    }

    private func circuitKey(of entry: LogbookEntry) -> String { LogbookFilter.circuitKey(of: entry) }

    // MARK: - Into a project

    /// A new project with the session's data file, its clips and `template` (#394).
    func openAsProject(_ entry: LogbookEntry, template: ProjectTemplate?) {
        model.openAsProject(entry, template: template)
    }

    func addToCurrentProject(_ entry: LogbookEntry) {
        guard let editor = active.editor, let url = entry.resolveFile() else { return }
        editor.addData(at: url)
        NSApp.activate()
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            if let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url"),
                let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil)
            {
                urls.append(url)
            }
        }
        return urls
    }
}
