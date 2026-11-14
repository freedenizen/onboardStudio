import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

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
                    Text("Surface").foregroundStyle(.secondary)
                    Picker("Surface", selection: binding(\.track)) {
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
