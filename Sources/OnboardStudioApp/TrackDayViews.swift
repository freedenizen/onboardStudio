import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// A track day above its sessions (#393): where and when, the car and driver, its conditions
/// and notes, and the ways to fill it. Edits go straight to the day's file, as a session's
/// conditions do — library files, not a document, so they are not undoable.
struct TrackDayHeader: View {
    let day: TrackDay
    /// The day's sessions, newest first, for the clips to be assigned to (#394).
    let sessions: [LogbookEntry]
    let save: (TrackDay) -> Void
    let addSessions: () -> Void
    let remove: () -> Void
    @State private var car = ""
    @State private var driver = ""
    @State private var showConditions = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case car, driver }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.title).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("trackday.header.title")
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("trackday.header.subtitle")
                }
                Spacer()
                Button("Add Files…", systemImage: "doc.badge.plus", action: addSessions)
                    .help("Enter the day's telemetry files and camera clips, or the folders holding them")
                    .accessibilityIdentifier("trackday.header.addSessions")
                Button("Remove Track Day…", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .help("Take the day and its sessions out of the logbook; no file is touched")
                    .accessibilityIdentifier("trackday.header.remove")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Car").foregroundStyle(.secondary)
                    TextField("What was driven", text: $car)
                        .focused($focus, equals: .car)
                        .onSubmit(commit)
                        .frame(maxWidth: 240)
                        .accessibilityIdentifier("trackday.header.car")
                }
                GridRow {
                    Text("Driver").foregroundStyle(.secondary)
                    TextField("Who drove", text: $driver)
                        .focused($focus, equals: .driver)
                        .onSubmit(commit)
                        .frame(maxWidth: 240)
                        .accessibilityIdentifier("trackday.header.driver")
                }
            }
            .font(.callout)
            DisclosureGroup(isExpanded: $showConditions) {
                ConditionsEditor(day: day, save: save).padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Text("Conditions and Notes").font(.subheadline.weight(.semibold))
                    if !day.conditions.summary.isEmpty {
                        Text(day.conditions.summary).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("trackday.header.conditions")
            if !day.clips.isEmpty { clipList }
            if sessionCount == 0 {
                Text("No sessions yet. Add Files… or drop the day's files here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("trackday.header.empty")
            }
        }
        .padding()
        .onAppear(perform: load)
        .onChange(of: day.id) { load() }
        .onChange(of: focus) { old, new in if old != nil, new != old { commit() } }
    }

    private var sessionCount: Int { sessions.count }

    /// The camera's clips, each with the session it is the picture of — matched by the clocks,
    /// or chosen here.
    private var clipList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clips").font(.subheadline.weight(.semibold))
            ForEach(day.clips) { clip in
                HStack(spacing: 8) {
                    Image(systemName: "video").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(clip.name)
                    Text(ClipMatcher.describe(clip)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Session", selection: sessionBinding(for: clip)) {
                        Text("Not assigned").tag(UUID?.none)
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            Text(Self.sessionLabel(session, index: sessions.count - index)).tag(Optional(session.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    .help(
                        clip.matchedBy == .clock
                            ? "Matched by the camera's clock and the log's" : "The session this clip is the picture of"
                    )
                    .accessibilityLabel("Session of \(clip.name)")
                    .accessibilityIdentifier("trackday.clip.\(clip.name)")
                }
                .font(.callout)
            }
        }
    }

    /// "Session 2 · 12:04 · 12 laps".
    static func sessionLabel(_ session: LogbookEntry, index: Int) -> String {
        var parts = ["Session \(index)"]
        if let date = session.date { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        parts.append("\(session.completeLapCount) laps")
        return parts.joined(separator: " · ")
    }

    private func sessionBinding(for clip: ClipRecord) -> Binding<UUID?> {
        Binding(
            get: { clip.sessionID },
            set: { chosen in
                guard let index = day.clips.firstIndex(where: { $0.id == clip.id }) else { return }
                var changed = day
                changed.clips[index].sessionID = chosen
                changed.clips[index].matchedBy = chosen == nil ? nil : .byHand
                save(changed)
            })
    }

    /// "Saturday, 23 August 2026 · 3 sessions".
    private var subtitle: String {
        let when = day.date.formatted(date: .complete, time: .omitted)
        let count = "\(sessionCount) session\(sessionCount == 1 ? "" : "s")"
        return "\(when) · \(count)"
    }

    private func load() {
        car = day.car
        driver = day.driver
    }

    private func commit() {
        var changed = day
        changed.car = car.trimmingCharacters(in: .whitespaces)
        changed.driver = driver.trimmingCharacters(in: .whitespaces)
        if changed != day { save(changed) }
    }
}

/// Where a track day begins (#393): the date, the circuit, the car and driver, what the day was
/// like — before a single file exists. Create saves the day and shows it.
struct NewTrackDaySheet: View {
    let knownCars: [String]
    let lastDay: TrackDay?
    let create: (TrackDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var circuitSearch = ""
    @State private var circuit: Circuit?
    @State private var typedName = ""
    @State private var car = ""
    @State private var driver = ""
    @State private var weather: SessionConditions.Weather?
    @State private var track: SessionConditions.Track?
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Track Day").font(.title2)
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .accessibilityIdentifier("trackday.new.date")
                LabeledContent("Circuit") { circuitField }
                LabeledContent("Car") {
                    HStack {
                        // The row is labelled already: a second title would be drawn beside it as
                        // "Car · What you drove" (#457). The prompt is the hint inside the field.
                        TextField("Car", text: $car, prompt: Text("What you drove")).labelsHidden()
                            .accessibilityIdentifier("trackday.new.car")
                        if !knownCars.isEmpty {
                            Menu {
                                ForEach(knownCars, id: \.self) { known in Button(known) { car = known } }
                            } label: {
                                Label("Cars in the Logbook", systemImage: "car")
                            }
                            .labelStyle(.iconOnly).fixedSize()
                            .accessibilityLabel("Cars in the Logbook")
                            .help("A car the logbook already knows")
                        }
                    }
                }
                TextField("Driver", text: $driver).accessibilityIdentifier("trackday.new.driver")
                Picker("Weather", selection: $weather) {
                    Text("Not noted").tag(SessionConditions.Weather?.none)
                    ForEach(SessionConditions.Weather.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Track", selection: $track) {
                    Text("Not noted").tag(SessionConditions.Track?.none)
                    ForEach(SessionConditions.Track.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                    .accessibilityIdentifier("trackday.new.notes")
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("trackday.new.cancel")
                Button("Create", action: commit).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("trackday.new.create")
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            car = lastDay?.car ?? ""
            driver = lastDay?.driver ?? ""
        }
    }

    /// The circuit chosen, or a search of the catalogue; a name the catalogue lacks is kept as typed.
    @ViewBuilder private var circuitField: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let circuit {
                HStack {
                    Text(circuit.displayName).accessibilityIdentifier("trackday.new.circuit.chosen")
                    Button("Change") { self.circuit = nil }.buttonStyle(.link)
                }
            } else if !typedName.isEmpty {
                HStack {
                    Text("“\(typedName)”, as typed").accessibilityIdentifier("trackday.new.circuit.chosen")
                    Button("Change") { typedName = "" }.buttonStyle(.link)
                }
            } else {
                TextField("Circuit", text: $circuitSearch, prompt: Text("Search circuits")).labelsHidden()
                    .accessibilityIdentifier("trackday.new.circuit")
                ForEach(CircuitCatalog.search(circuitSearch, limit: 5)) { match in
                    Button(match.displayName) {
                        circuit = match
                        circuitSearch = ""
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("trackday.new.match.\(match.name)")
                }
                if !circuitSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Use “\(circuitSearch.trimmingCharacters(in: .whitespaces))” as Typed") {
                        typedName = circuitSearch.trimmingCharacters(in: .whitespaces)
                        circuitSearch = ""
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("trackday.new.useTyped")
                }
            }
        }
    }

    private func commit() {
        let day = TrackDay(
            date: date, circuitID: circuit?.id, trackName: circuit == nil && !typedName.isEmpty ? typedName : nil,
            car: car.trimmingCharacters(in: .whitespaces), driver: driver.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            conditions: SessionConditions(weather: weather, track: track))
        create(day)
        dismiss()
    }
}

/// The sidebar's days (#393): newest first, under their year when there is more than one.
struct TrackDaySidebarSection: View {
    let groups: [LogbookFilter.Group]
    let days: [TrackDay]

    var body: some View {
        Section("Track Days") {
            let years = Set(days.map(\.year))
            if years.count > 1 {
                ForEach(years.sorted(by: >), id: \.self) { year in
                    DisclosureGroup(String(year)) {
                        ForEach(groups.filter { yearOf($0) == year }, id: \.scope) { group in row(group) }
                    }
                }
            } else {
                ForEach(groups, id: \.scope) { group in row(group) }
            }
        }
    }

    private func yearOf(_ group: LogbookFilter.Group) -> Int? { day(of: group)?.year }

    /// The date over the circuit. On one line — "Aug 23, 2026 · Sonoma Raceway" — the sidebar cut
    /// the circuit off after a letter or two once the count was beside it, and two days on one
    /// date could not be told apart (#457).
    private func row(_ group: LogbookFilter.Group) -> some View {
        Label {
            if let day = day(of: group) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.date.formatted(date: .abbreviated, time: .omitted))
                    Text(day.title).font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
            } else {
                Text(group.scope.title)
            }
        } icon: {
            Image(systemName: "calendar.day.timeline.left")
        }
        .badge(group.count).tag(group.scope)
        .help(group.scope.title)
        // One element, read as the day was on one line: "Aug 23, 2026 · Sonoma Raceway".
        .accessibilityElement(children: .combine)
        .accessibilityLabel(group.scope.title)
        .accessibilityIdentifier("logbook.day.\(group.scope.title)")
    }

    private func day(of group: LogbookFilter.Group) -> TrackDay? {
        guard case .day(let id, _) = group.scope else { return nil }
        return days.first { $0.id == id }
    }
}
