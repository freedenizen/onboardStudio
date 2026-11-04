import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// The sessions, sortable by any column.
struct LogbookTable: View {
    let entries: [LogbookEntry]
    /// The sessions that set a personal best when they were driven (#351).
    var bests: Set<UUID> = []
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
            TableColumn("PB") { entry in
                if bests.contains(entry.id) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                        .accessibilityLabel("Personal best")
                        .help("This session set a personal best at its circuit, overall or in its car")
                }
            }
            .width(min: 28, ideal: 32)
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
    /// The clips of its day that are its picture (#394).
    var clips: [ClipRecord] = []
    let hasProject: Bool
    /// What New Project from Template offers, read when the menu opens.
    var templates: () -> [ProjectTemplate] = { ProjectTemplate.builtIn }
    /// A new project from the session, laid out with the template (`nil`: blank).
    let newProject: (ProjectTemplate?) -> Void
    let addToProject: () -> Void
    let remove: () -> Void
    let save: (LogbookEntry) -> Void
    /// The personal best at this session's circuit and how many visits the logbook has (#351).
    var personalBest: PersonalBest?
    var visits = 0
    /// The template the last New Project used; the next one uses it too.
    @AppStorage("logbook.projectTemplate") private var templateName = "Classic Dash"

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
                    row("Personal best here", personalBestText, detail: visits > 1 ? "\(visits) visits" : nil)
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
                if !clips.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video").font(.subheadline.weight(.semibold))
                        ForEach(clips) { clip in
                            HStack(spacing: 6) {
                                Image(systemName: "video").foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(clip.name)
                                Text(ClipMatcher.describe(clip)).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("logbook.clip.\(clip.name)")
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
                HStack(spacing: 4) {
                    Button("New Project") { newProject(templates().first { $0.name == templateName }) }
                        .help(newProjectHelp)
                        .accessibilityIdentifier("logbook.open")
                    Menu {
                        Button("Blank Project") {
                            templateName = ""
                            newProject(nil)
                        }
                        Divider()
                        ForEach(templates(), id: \.name) { template in
                            Button(template.name) {
                                templateName = template.name
                                newProject(template)
                            }
                        }
                    } label: {
                        Label("New Project from Template", systemImage: "chevron.down")
                    }
                    .labelStyle(.iconOnly).fixedSize()
                    .accessibilityLabel("New Project from Template")
                    .help("A new project from this session, laid out with the template you choose")
                    .accessibilityIdentifier("logbook.openFrom")
                    Spacer().frame(width: 8)
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

    /// "A new project with this session's data file, 2 clips and the Classic Dash layout".
    private var newProjectHelp: String {
        var parts = ["this session's data file"]
        if !clips.isEmpty { parts.append("\(clips.count) clip\(clips.count == 1 ? "" : "s")") }
        let layout = templateName.isEmpty ? "no layout" : "the \(templateName) layout"
        return "A new project with \(parts.joined(separator: ", ")) and \(layout)"
    }

    /// "1:56.88 · lap 4 · 23 Aug 2026 · Miata", or "this session" when it is the one.
    private var personalBestText: String? {
        guard let personalBest else { return nil }
        var parts = [TimeParsing.lapTimeString(personalBest.seconds)]
        if personalBest.entryID == entry.id {
            parts.append("this session")
        } else {
            if let lap = personalBest.lapNumber { parts.append("lap \(lap)") }
            if let date = personalBest.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
            if !personalBest.car.isEmpty { parts.append(personalBest.car) }
        }
        return parts.joined(separator: " · ")
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
    /// Whose conditions these are, so a change of session or day reloads the fields.
    let identity: UUID
    let conditions: SessionConditions
    let notes: String
    let save: (SessionConditions, String) -> Void
    @State private var temperature = ""
    @State private var tyres = ""
    @State private var setup = ""
    @State private var notesText = ""
    @FocusState private var focus: Field?

    enum Field: Hashable { case temperature, tyres, setup, notes }

    /// A session's conditions and notes (#348).
    init(entry: LogbookEntry, save: @escaping (LogbookEntry) -> Void) {
        identity = entry.id
        conditions = entry.conditions
        notes = entry.notes
        self.save = { conditions, notes in
            var changed = entry
            changed.conditions = conditions
            changed.notes = notes
            save(changed)
        }
    }

    /// A track day's conditions and notes (#393): the default for the sessions added to it.
    init(day: TrackDay, save: @escaping (TrackDay) -> Void) {
        identity = day.id
        conditions = day.conditions
        notes = day.notes
        self.save = { conditions, notes in
            var changed = day
            changed.conditions = conditions
            changed.notes = notes
            save(changed)
        }
    }

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
            TextField("Anything worth remembering about the day", text: $notesText, axis: .vertical).lineLimit(2...6)
                .focused($focus, equals: .notes)
                .onSubmit(commit)
                .accessibilityIdentifier("logbook.notes")
        }
        .onAppear(perform: load)
        .onChange(of: identity) { load() }
        .onChange(of: focus) { old, new in if old != nil, new != old { commit() } }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SessionConditions, Value>) -> Binding<Value> {
        Binding(
            get: { conditions[keyPath: keyPath] },
            set: { value in
                var changed = conditions
                changed[keyPath: keyPath] = value
                save(changed, notes)
            })
    }

    private func load() {
        temperature = conditions.ambientCelsius.map { Self.format($0) } ?? ""
        tyres = conditions.tyres
        setup = conditions.setup
        notesText = notes
    }

    /// The text fields into the entry, when any of them changed.
    private func commit() {
        var changed = conditions
        let trimmed = temperature.trimmingCharacters(in: .whitespaces)
        let number = Double(trimmed.replacingOccurrences(of: ",", with: "."))
        changed.ambientCelsius = trimmed.isEmpty ? nil : number
        changed.tyres = tyres.trimmingCharacters(in: .whitespaces)
        changed.setup = setup.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if changed != conditions || changedNotes != notes { save(changed, changedNotes) }
    }

    static func format(_ celsius: Double) -> String {
        celsius == celsius.rounded() ? String(Int(celsius)) : String(format: "%.1f", celsius)
    }
}
