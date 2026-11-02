import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// The logbook as the app holds it, for the window (#347): read once, re-read after anything
/// that writes to it, so the table never shows a stale season.
@MainActor @Observable final class LogbookModel {
    static let shared = LogbookModel()

    private(set) var entries: [LogbookEntry] = []
    private(set) var cars: [Car] = []

    func reload() {
        let logbook = AppLogbook.shared
        entries = logbook.entries()
        cars = logbook.cars()
    }

    func remove(_ entry: LogbookEntry) {
        try? AppLogbook.shared.remove(id: entry.id)
        reload()
    }

    /// Writes an edited entry — its conditions and notes (#348) — and shows it.
    func save(_ entry: LogbookEntry) {
        try? AppLogbook.shared.save(entry)
        reload()
    }
}

/// Hands a session to the next editor that appears (Open as Project).
@MainActor
final class PendingLogbookOpen {
    static let shared = PendingLogbookOpen()
    var entry: LogbookEntry?
}

/// Every track day in one place (#347): a sidebar of circuits, cars and years, a sortable,
/// searchable table of sessions, and a detail pane with the laps and the way into a project.
struct LogbookWindow: View {
    static let windowID = "logbook"

    @SceneStorage("logbook.scope") private var storedScope = "all"
    @State private var scope: LogbookScope = .all
    @State private var search = ""
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\LogbookEntry.date, order: .reverse)]
    @State private var trackDay: TrackDayRequest?
    @State private var confirmRemoval: LogbookEntry?
    @Environment(\.openWindow) private var openWindow
    private var model = LogbookModel.shared
    private var active = ActiveEditor.shared

    static func open(_ openWindow: OpenWindowAction) { openWindow(id: windowID) }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            content
                .frame(minWidth: 720, minHeight: 420)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Track Day…", systemImage: "plus") {
                            let urls = OpenPanels.chooseTrackDay()
                            if !urls.isEmpty { trackDay = TrackDayRequest(urls: urls) }
                        }
                        .help("Enter a day's telemetry files and camera clips in the logbook")
                        .accessibilityIdentifier("logbook.addTrackDay")
                    }
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Circuit, car, driver, notes")
        }
        .sheet(item: $trackDay) { request in
            TrackDayImportSheet(editor: active.editor, request: request).onDisappear { model.reload() }
        }
        .onAppear { model.reload() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                let urls = await Self.urls(from: providers)
                if !urls.isEmpty { trackDay = TrackDayRequest(urls: urls) }
            }
            return true
        }
        .confirmationDialog(
            "Remove this session from the logbook?",
            isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } }),
            presenting: confirmRemoval
        ) { entry in
            Button("Remove from Logbook", role: .destructive) {
                model.remove(entry)
                if selection == entry.id { selection = nil }
            }
        } message: { entry in
            Text("\(entry.title) is taken out of the logbook. The file itself is not touched.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { scope }, set: { if let new = $0 { scope = new } })) {
            Label("All Sessions", systemImage: "book.closed").tag(LogbookScope.all)
                .accessibilityIdentifier("logbook.scope.all")
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

    // MARK: - Table and detail

    private var shown: [LogbookEntry] {
        LogbookFilter.apply(model.entries, scope: scope, search: search).sorted(using: sortOrder)
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label("No Track Days Yet", systemImage: "book.closed")
            } description: {
                Text(
                    "The logbook keeps every session the app reads: where and when, the car, every lap. "
                        + "Add a day's files or folders to begin, or add a data file to a project.")
            } actions: {
                Button("Add Track Day…") {
                    let urls = OpenPanels.chooseTrackDay()
                    if !urls.isEmpty { trackDay = TrackDayRequest(urls: urls) }
                }
            }
        } else {
            HSplitView {
                LogbookTable(entries: shown, selection: $selection, sortOrder: $sortOrder)
                    .frame(minWidth: 460)
                    .layoutPriority(1)
                if let entry = model.entries.first(where: { $0.id == selection }) {
                    LogbookDetail(
                        entry: entry, hasProject: active.editor != nil,
                        openAsProject: { openAsProject(entry) },
                        addToProject: { addToCurrentProject(entry) },
                        remove: { confirmRemoval = entry },
                        save: { model.save($0) }
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                }
            }
        }
    }

    // MARK: - Into a project

    func openAsProject(_ entry: LogbookEntry) {
        guard entry.resolveFile() != nil else { return }
        PendingLogbookOpen.shared.entry = entry
        NSDocumentController.shared.newDocument(nil)
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

/// The sessions, sortable by any column.
struct LogbookTable: View {
    let entries: [LogbookEntry]
    @Binding var selection: UUID?
    @Binding var sortOrder: [KeyPathComparator<LogbookEntry>]

    var body: some View {
        Table(entries, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date, comparator: OptionalDateComparator()) { entry in
                Text(entry.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            }
            .width(min: 90, ideal: 110)
            TableColumn("Circuit", value: \.title).width(min: 110, ideal: 150)
            TableColumn("Car", value: \.car).width(min: 70, ideal: 100)
            TableColumn("Laps", value: \.completeLapCount) { entry in Text("\(entry.completeLapCount)") }
                .width(min: 40, ideal: 50)
            TableColumn("Best", value: \.bestLap, comparator: OptionalDoubleComparator()) { entry in
                Text(entry.bestLap.map { TimeParsing.lapTimeString($0) } ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            TableColumn("Optimal", value: \.optimalLap, comparator: OptionalDoubleComparator()) { entry in
                Text(entry.optimalLap.map { TimeParsing.lapTimeString($0) } ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            TableColumn("Rolling", value: \.fastestRollingLap, comparator: OptionalDoubleComparator()) { entry in
                Text(entry.fastestRollingLap.map { TimeParsing.lapTimeString($0) } ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            TableColumn("Conditions", value: \.conditions.summary).width(min: 90, ideal: 140)
        }
        .accessibilityIdentifier("logbook.table")
    }
}

/// Sorts optionals with the unknown last whichever way the column points.
nonisolated struct OptionalDoubleComparator: SortComparator {
    var order: SortOrder = .forward
    func compare(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
        let a = lhs ?? .infinity
        let b = rhs ?? .infinity
        let result: ComparisonResult = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        return order == .forward ? result : result.reversed
    }
}

nonisolated struct OptionalDateComparator: SortComparator {
    var order: SortOrder = .forward
    func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        let a = lhs ?? .distantPast
        let b = rhs ?? .distantPast
        let result: ComparisonResult = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        return order == .forward ? result : result.reversed
    }
}

nonisolated extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

/// One session: the numbers, the laps, the projects, and the ways in.
struct LogbookDetail: View {
    let entry: LogbookEntry
    let hasProject: Bool
    let openAsProject: () -> Void
    let addToProject: () -> Void
    let remove: () -> Void
    let save: (LogbookEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    row(
                        "Best lap", entry.bestLap.map { TimeParsing.lapTimeString($0) },
                        detail: entry.bestLapNumber.map { "lap \($0)" })
                    row("Optimal lap", entry.optimalLap.map { TimeParsing.lapTimeString($0) })
                    row("Fastest rolling lap", entry.fastestRollingLap.map { TimeParsing.lapTimeString($0) })
                    row("Top speed", entry.topSpeed.map { "\(Int(($0 * 3.6).rounded())) km/h" })
                    row("Laps", "\(entry.completeLapCount) complete of \(entry.laps.count)")
                }
                .font(.callout)
                if !entry.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Laps").font(.subheadline.weight(.semibold))
                        ForEach(entry.laps, id: \.number) { lap in
                            HStack {
                                Text("Lap \(lap.number)")
                                Spacer()
                                Text(lap.seconds.map { TimeParsing.lapTimeString($0) } ?? "—").monospacedDigit()
                                    .foregroundStyle(lap.number == entry.bestLapNumber ? Color.accentColor : .primary)
                                if !lap.isComplete { Text("partial").foregroundStyle(.secondary) }
                            }
                            .font(.callout)
                        }
                    }
                }
                ConditionsEditor(entry: entry, save: save)
                if !entry.projects.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Projects").font(.subheadline.weight(.semibold))
                        ForEach(entry.projects, id: \.path) { link in
                            Button(link.name) {
                                let url = URL(fileURLWithPath: link.path)
                                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) {
                                    _, _, _ in
                                }
                            }
                            .buttonStyle(.link).font(.callout)
                        }
                    }
                }
                if !entry.exports.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exports").font(.subheadline.weight(.semibold))
                        ForEach(entry.exports, id: \.path) { link in
                            Button(link.name) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: link.path)])
                            }
                            .buttonStyle(.link).font(.callout)
                        }
                    }
                }
                Text(entry.file.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Open as Project", action: openAsProject)
                        .accessibilityIdentifier("logbook.open")
                    Button("Add to Current Project", action: addToProject)
                        .disabled(!hasProject)
                        .accessibilityIdentifier("logbook.addToProject")
                }
                HStack {
                    Button("Show in Finder") {
                        if let url = entry.resolveFile() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button("Remove from Logbook…", role: .destructive, action: remove)
                        .accessibilityIdentifier("logbook.remove")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("logbook.detail")
    }

    private var subtitle: String {
        let parts: [String?] = [
            entry.date.map { $0.formatted(date: .long, time: .shortened) },
            entry.car.isEmpty ? nil : entry.car,
            entry.driver.isEmpty ? nil : entry.driver,
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func row(_ label: String, _ value: String?, detail: String? = nil) -> some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(value).monospacedDigit()
                    if let detail { Text(detail).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

/// Weather, track, temperature, tyres, setup and notes, written to the entry as they are set:
/// pickers and the temperature at once, text when Return is pressed or the field is left (#348).
struct ConditionsEditor: View {
    let entry: LogbookEntry
    let save: (LogbookEntry) -> Void
    @State private var temperature = ""
    @State private var tyres = ""
    @State private var setup = ""
    @State private var notes = ""
    @FocusState private var focus: Field?

    enum Field: Hashable { case temperature, tyres, setup, notes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conditions").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Weather").foregroundStyle(.secondary)
                    Picker("Weather", selection: binding(\.weather)) {
                        Text("Not noted").tag(SessionConditions.Weather?.none)
                        ForEach(SessionConditions.Weather.allCases, id: \.self) {
                            Text($0.displayName).tag(Optional($0))
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("logbook.weather")
                }
                GridRow {
                    Text("Track").foregroundStyle(.secondary)
                    Picker("Track", selection: binding(\.track)) {
                        Text("Not noted").tag(SessionConditions.Track?.none)
                        ForEach(SessionConditions.Track.allCases, id: \.self) {
                            Text($0.displayName).tag(Optional($0))
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("logbook.track")
                }
                GridRow {
                    Text("Air").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField("°C", text: $temperature).frame(width: 56)
                            .focused($focus, equals: .temperature)
                            .onSubmit(commit)
                            .accessibilityIdentifier("logbook.temperature")
                        Text("°C").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Tyres").foregroundStyle(.secondary)
                    TextField("Compound, age, pressures", text: $tyres)
                        .focused($focus, equals: .tyres)
                        .onSubmit(commit)
                        .accessibilityIdentifier("logbook.tyres")
                }
                GridRow {
                    Text("Setup").foregroundStyle(.secondary)
                    TextField("What was changed", text: $setup, axis: .vertical).lineLimit(1...3)
                        .focused($focus, equals: .setup)
                        .onSubmit(commit)
                        .accessibilityIdentifier("logbook.setup")
                }
            }
            .font(.callout)
            Text("Notes").font(.subheadline.weight(.semibold)).padding(.top, 4)
            TextField("Anything worth remembering about the day", text: $notes, axis: .vertical).lineLimit(2...6)
                .focused($focus, equals: .notes)
                .onSubmit(commit)
                .accessibilityIdentifier("logbook.notes")
        }
        .onAppear(perform: load)
        .onChange(of: entry.id) { load() }
        .onChange(of: focus) { old, new in if old != nil, new != old { commit() } }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SessionConditions, Value>) -> Binding<Value> {
        Binding(
            get: { entry.conditions[keyPath: keyPath] },
            set: { value in
                var changed = entry
                changed.conditions[keyPath: keyPath] = value
                save(changed)
            })
    }

    private func load() {
        temperature = entry.conditions.ambientCelsius.map { Self.format($0) } ?? ""
        tyres = entry.conditions.tyres
        setup = entry.conditions.setup
        notes = entry.notes
    }

    /// The text fields into the entry, when any of them changed.
    private func commit() {
        var changed = entry
        let trimmed = temperature.trimmingCharacters(in: .whitespaces)
        let number = Double(trimmed.replacingOccurrences(of: ",", with: "."))
        changed.conditions.ambientCelsius = trimmed.isEmpty ? nil : number
        changed.conditions.tyres = tyres.trimmingCharacters(in: .whitespaces)
        changed.conditions.setup = setup.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if changed != entry { save(changed) }
    }

    static func format(_ celsius: Double) -> String {
        celsius == celsius.rounded() ? String(Int(celsius)) : String(format: "%.1f", celsius)
    }
}
