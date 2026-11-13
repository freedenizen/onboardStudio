import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// A track day above its sessions (#393): where and when, the car and driver, its conditions
/// and notes, and the ways to fill it. Edits go straight to the day's file, as a session's
/// conditions do — library files, not a document — and each is a step of the Logbook window's
/// Undo (#454).
struct TrackDayHeader: View {
    let day: TrackDay
    /// The day's sessions, newest first, for the clips to be assigned to (#394).
    let sessions: [LogbookEntry]
    let save: (TrackDay) -> Void
    let addSessions: () -> Void
    let remove: () -> Void
    /// The circuit names typed into the logbook before (#455).
    var knownCircuits: [String] = []
    @State private var car = ""
    @State private var driver = ""
    /// The circuit as it is being chosen; the day's until Change is pressed, and the day's again
    /// once something is chosen.
    @State private var circuit: Circuit?
    @State private var typedName = ""
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
                Button("Remove Track Day", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .help(
                        "Take the day and its sessions out of the logbook; no file is touched, and Edit ▸ Undo "
                            + "brings them back"
                    )
                    .accessibilityIdentifier("trackday.header.remove")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("Circuit").foregroundStyle(.secondary)
                    circuitRow
                }
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
        .onChange(of: day.circuitKey) { loadCircuit() }
        .onChange(of: focus) { old, new in if old != nil, new != old { commit() } }
    }

    private var sessionCount: Int { sessions.count }

    /// Where the day was driven, which can be named or corrected after the day exists (#455): a
    /// day made for files from a place the catalogue does not know begins with no circuit, and
    /// its sessions were stuck under a circuit named after each file. The choice goes to the
    /// sessions that had what the day had.
    private var circuitRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // As wide as Car and Driver under it.
            CircuitChooser(
                circuit: $circuit, typedName: $typedName, knownNames: knownCircuits, identifier: "trackday.header",
                fieldWidth: 240)
            // Change was pressed and nothing chosen yet: the way back, without choosing again.
            if circuit == nil, typedName.isEmpty, !day.circuitKey.isEmpty {
                Button("Keep \(day.title)") { loadCircuit() }.buttonStyle(.link)
                    .accessibilityIdentifier("trackday.header.circuit.keep")
            }
        }
        .onChange(of: circuit) { commitCircuit() }
        .onChange(of: typedName) { commitCircuit() }
    }

    private func loadCircuit() {
        circuit = day.circuitID.flatMap(CircuitCatalog.circuit(id:))
        typedName = circuit == nil ? day.trackName ?? "" : ""
    }

    /// Saves the circuit once one is chosen; while the field is empty the day keeps what it had.
    private func commitCircuit() {
        guard circuit != nil || !typedName.isEmpty else { return }
        var changed = day
        changed.circuitID = circuit?.id
        changed.trackName = circuit == nil ? typedName : nil
        if changed.circuitKey != day.circuitKey { save(changed) }
    }

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
        loadCircuit()
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
    /// The circuit names typed into the logbook before (#455).
    var knownCircuits: [String] = []
    let lastDay: TrackDay?
    let create: (TrackDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
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
                // "Surface", not "Track": two rows under Circuit, "Track" asked which track (#468).
                Picker("Surface", selection: $track) {
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
    private var circuitField: some View {
        CircuitChooser(circuit: $circuit, typedName: $typedName, knownNames: knownCircuits, identifier: "trackday.new")
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
    /// The years folded open. The window opens the chosen day's (#485): with no state of their
    /// own the years all started shut, and the day being worked on lost its row in the sidebar
    /// the moment a file from another year arrived.
    @Binding var openYears: Set<Int>
    /// Sessions dragged from the table onto a day (#454).
    var moveSessions: ([UUID], TrackDay) -> Void = { _, _ in }
    var remove: (TrackDay) -> Void = { _ in }
    /// The day sessions are being dragged over, drawn as the place they will go.
    @State private var target: UUID?

    var body: some View {
        Section("Track Days") {
            let years = Set(days.map(\.year))
            if years.count > 1 {
                ForEach(years.sorted(by: >), id: \.self) { year in
                    DisclosureGroup(isExpanded: isOpen(year)) {
                        ForEach(groups.filter { yearOf($0) == year }, id: \.scope) { group in row(group) }
                    } label: {
                        // On the label alone: on the group it would name every day inside it.
                        Text(String(year)).accessibilityIdentifier("logbook.year.\(year)")
                    }
                }
            } else {
                ForEach(groups, id: \.scope) { group in row(group) }
            }
        }
    }

    private func yearOf(_ group: LogbookFilter.Group) -> Int? { day(of: group)?.year }

    private func isOpen(_ year: Int) -> Binding<Bool> {
        Binding(
            get: { openYears.contains(year) },
            set: { open in
                if open { openYears.insert(year) } else { openYears.remove(year) }
            })
    }

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
        .contextMenu {
            if let day = day(of: group) { Button("Remove Track Day") { remove(day) } }
        }
        // Sessions dropped on the day are moved to it (#454).
        .dropDestination(for: LogbookSessionDrag.self) { items, _ in
            guard let day = day(of: group), !items.isEmpty else { return false }
            moveSessions(items.map(\.id), day)
            return true
        } isTargeted: { over in
            let id = day(of: group)?.id
            if over { target = id } else if target == id { target = nil }
        }
        .listRowBackground(
            day(of: group)?.id == target && target != nil
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)) : nil)
    }

    private func day(of group: LogbookFilter.Group) -> TrackDay? {
        guard case .day(let id, _) = group.scope else { return nil }
        return days.first { $0.id == id }
    }
}
