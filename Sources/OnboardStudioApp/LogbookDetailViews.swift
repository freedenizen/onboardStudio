import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// The sessions, sortable by any column. Several can be selected, right-clicked and dragged onto a
/// day in the sidebar (#454).
struct LogbookTable<RowMenu: View>: View {
    let entries: [LogbookEntry]
    /// The sessions that set a personal best when they were driven (#351), and whether each still
    /// holds it (#422).
    var bests: [UUID: PersonalBestBadge] = [:]
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<LogbookEntry>]
    /// The right-click menu of the sessions clicked: the selection, when the row is in it.
    @ViewBuilder let menu: (Set<UUID>) -> RowMenu

    var body: some View {
        Table(of: LogbookEntry.self, selection: $selection, sortOrder: $sortOrder) {
            columns
        } rows: {
            ForEach(entries) { entry in
                TableRow(entry).draggable(LogbookSessionDrag(id: entry.id))
            }
        }
        .contextMenu(forSelectionType: UUID.self, menu: menu)
        .accessibilityIdentifier("logbook.table")
    }

    @TableColumnBuilder<LogbookEntry, KeyPathComparator<LogbookEntry>> private var columns:
        some TableColumnContent<LogbookEntry, KeyPathComparator<LogbookEntry>>
    {
        // First, as Mail's flags are: a personal best stays in view however narrow the
        // table is; last, it was the first column a narrow table scrolled away (#503).
        TableColumn("PB") { entry in
            switch bests[entry.id] {
            case .current:
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                    .accessibilityLabel("Personal best")
                    .help("Your personal best at this circuit, overall or in this car")
            case .former:
                Image(systemName: "star").foregroundStyle(.secondary)
                    .accessibilityLabel("Former personal best")
                    .help("A personal best at this circuit when it was driven, since beaten")
            case nil:
                EmptyView()
            }
        }
        .width(min: 28, ideal: 32)
        // The time too: a day's sessions all share its date, and only the time tells them apart (#564).
        TableColumn("Date", value: \.date, comparator: OptionalDateComparator()) { entry in
            Text(entry.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
        }
        .width(min: 130, ideal: 160)
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
    /// The Coaching window on this session, with no project (#396).
    var coach: () -> Void = {}
    /// The Coaching window on this session against another of the logbook's (#397).
    var compare: (LogbookEntry) -> Void = { _ in }
    /// The logbook's other sessions at this circuit: the personal best and the last visit, first.
    var comparisons: [(title: String, entry: LogbookEntry)] = []
    /// A project from the session laid out for a debrief, with the sheet up (#397).
    var debrief: () -> Void = {}
    /// The session's laps raced round the circuit in 3D (#415).
    var replay: () -> Void = {}
    let addToProject: () -> Void
    let remove: () -> Void
    let save: (LogbookEntry) -> Void
    /// The cars the logbook names, for correcting this session's without retyping (#453).
    var knownCars: [String] = []
    /// The personal best at this session's circuit (#351) and how many track days the logbook has
    /// there (#426).
    var personalBest: PersonalBest?
    var visits = 0
    /// For a session in runs (#552): the logbook's other courses, and what renaming the course,
    /// joining another or starting a new one does.
    var otherCourses: [CourseTag] = []
    var renameCourse: (String) -> Void = { _ in }
    var joinCourse: (CourseTag) -> Void = { _ in }
    var separateCourse: () -> Void = {}
    /// The template the last New Project used; the next one uses it too.
    @AppStorage("logbook.projectTemplate") private var templateName = "Classic Dash"
    /// Settings ▸ Units ▸ Speed; with nothing chosen there, the region's (#464).
    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    private var speedUnit: SpeedDisplayUnit { (SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic).shown() }

    /// "lap", or "run" for a point-to-point course (#552).
    private var noun: String { entry.isRuns ? "run" : "lap" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    // What was driven and by whom first, as the day's header has them, in the same
                    // columns as the numbers under them (#453).
                    SessionCarFields(entry: entry, knownCars: knownCars, save: save)
                    if let course = entry.course {
                        SessionCourseField(
                            entry: entry, course: course, otherCourses: otherCourses, rename: renameCourse,
                            join: joinCourse, separate: separateCourse)
                    }
                    row(
                        "Best \(noun)", entry.bestLap.map { TimeParsing.lapTimeString($0) },
                        detail: entry.bestLapNumber.map { "\(noun) \($0)" })
                    row("Optimal \(noun)", entry.optimalLap.map { TimeParsing.lapTimeString($0) })
                    // A run's course ends at the finish: there is no rolling lap (#552).
                    if !entry.isRuns {
                        row("Fastest rolling lap", entry.fastestRollingLap.map { TimeParsing.lapTimeString($0) })
                    }
                    row(
                        "Top speed", entry.topSpeed.map { speedUnit.text(metersPerSecond: $0) },
                        identifier: "logbook.detail.topSpeed")
                    row(
                        entry.isRuns ? "Runs" : "Laps",
                        "\(entry.completeLapCount) \(entry.isRuns ? "finished" : "complete") of \(entry.laps.count)",
                        identifier: "logbook.detail.laps")
                    row("Personal best here", personalBestText, detail: visits > 1 ? "\(visits) visits" : nil)
                }
                .font(.callout)
                if !entry.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.isRuns ? "Runs" : "Laps").font(.subheadline.weight(.semibold))
                        ForEach(entry.laps, id: \.number) { lap in
                            HStack {
                                Text("\(entry.isRuns ? "Run" : "Lap") \(lap.number)")
                                Spacer()
                                Text(lap.seconds.map { TimeParsing.lapTimeString($0) } ?? "—").monospacedDigit()
                                    .foregroundStyle(lap.number == entry.bestLapNumber ? Color.accentColor : .primary)
                                if !lap.isComplete {
                                    Text(entry.isRuns ? "DNF" : "partial").foregroundStyle(.secondary)
                                }
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
                SelectableText(entry.file.path).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("logbook.detail")
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
    }

    /// What can be done with the session. Under the detail rather than at the end of it, so the
    /// buttons are in view however many laps there are, and in rows that wrap, so each keeps its
    /// whole title however narrow the pane is (#448).
    private var actions: some View {
        VStack(alignment: .leading) {
            FlowLayout {
                Menu {
                    Button("Blank Project") {
                        templateName = ""
                        newProject(nil)
                    }
                    Section("From a Template") {
                        ForEach(templates(), id: \.name) { template in
                            Button(template.name) {
                                templateName = template.name
                                newProject(template)
                            }
                        }
                    }
                } label: {
                    Text("New Project")
                } primaryAction: {
                    newProject(templates().first { $0.name == templateName })
                }
                .fixedSize()
                .help(newProjectHelp)
                .accessibilityIdentifier("logbook.open")
                Button("Add to Current Project", action: addToProject)
                    .disabled(!hasProject)
                    .help(
                        hasProject
                            ? "Add this session's data file to the project in front"
                            : "Adds this session to the project in front: open or make one first"
                    )
                    .accessibilityIdentifier("logbook.addToProject")
            }
            FlowLayout {
                Button("Coach…", action: coach)
                    .help("Where this session's laps lost time, with no project needed")
                    .accessibilityIdentifier("logbook.coach")
                Button("Replay…", action: replay)
                    .help("Race this session's laps round the circuit in 3D, with the logbook's other laps here")
                    .accessibilityIdentifier("logbook.replay")
                Menu("Compare With") {
                    ForEach(comparisons, id: \.entry.id) { choice in
                        Button(choice.title) { compare(choice.entry) }
                    }
                }
                .fixedSize()
                .disabled(comparisons.isEmpty)
                .help("Coach this session against another of the logbook's at this circuit")
                .accessibilityIdentifier("logbook.compareWith")
                Button("Export Coaching Debrief…", action: debrief)
                    .disabled(clips.isEmpty)
                    .help(
                        clips.isEmpty
                            ? "A debrief video needs the session's clip: assign one on its day first"
                            : "A project laid out for a debrief from this session, with the export sheet up"
                    )
                    .accessibilityIdentifier("logbook.debrief")
            }
            FlowLayout {
                Button("Show in Finder") {
                    if let url = entry.resolveFile() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .help("Show this session's data file in the Finder")
                .accessibilityIdentifier("logbook.showInFinder")
                Button("Remove from Logbook", role: .destructive, action: remove)
                    .help(
                        "Take this session out of the logbook; its file is not touched, and Edit ▸ Undo brings "
                            + "it back"
                    )
                    .accessibilityIdentifier("logbook.remove")
            }
        }
        .controlSize(.small)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// "A new project with this session's data file, 2 clips and the Classic Dash layout; the
    /// arrow offers the other templates, or a blank project".
    private var newProjectHelp: String {
        var parts = ["this session's data file"]
        if !clips.isEmpty { parts.append("\(clips.count) clip\(clips.count == 1 ? "" : "s")") }
        let layout = templateName.isEmpty ? "no layout" : "the \(templateName) layout"
        return "A new project with \(parts.joined(separator: ", ")) and \(layout); "
            + "the arrow offers the other templates, or a blank project"
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

    @ViewBuilder private func row(
        _ label: String, _ value: String?, detail: String? = nil, identifier: String = ""
    ) -> some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(value).monospacedDigit().accessibilityIdentifier(identifier)
                    if let detail { Text(detail).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
