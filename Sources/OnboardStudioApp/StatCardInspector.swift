import ProjectModel
import SwiftUI

/// The stat card's title, what it counts over and which numbers it shows (#151).
struct StatCardInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: StatCardParams

    var body: some View {
        Section("Stat Card") {
            CommittingTextField("Title", text: field(\.title, "Title"))
                .accessibilityIdentifier("statCard.title")
            InsertDetailMenu(details: editor.project.details) { token in
                update("Title") { $0.title += ($0.title.isEmpty || $0.title.hasSuffix(" ") ? "" : " ") + token }
            }
            Picker("Counts", selection: field(\.scope, "Stat Card Scope")) {
                Text("The whole session").tag(StatCardScope.session)
                Text("The lap at the playhead").tag(StatCardScope.lapAtPlayhead)
            }
            .accessibilityIdentifier("statCard.scope")
            Toggle(
                params.scope == .session ? "Best lap" : "Difference to the best",
                isOn: field(\.showBestLap, "Best Lap"))
            Toggle("Top speed", isOn: field(\.showTopSpeed, "Top Speed"))
            if params.showTopSpeed {
                SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit, "Speed Unit"))
            }
            Toggle("Optimal lap", isOn: field(\.showOptimalLap, "Optimal Lap"))
                .help("The best sectors of the session spliced into one lap; shown when the data has sectors")
            if params.scope == .session { Toggle("Laps completed", isOn: field(\.showLapCount, "Laps Completed")) }
            Text(
                params.scope == .session
                    ? "Numbers for the whole session, from the data file this card reads."
                    : "Numbers for whichever lap is playing: its time, how far off the best it is, its top speed."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("Colours") {
            ColorPicker("Numbers", selection: color(\.textColor, "Text Colour"))
            ColorPicker("Labels", selection: color(\.labelColor, "Label Colour"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<StatCardParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<StatCardParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout StatCardParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .statCard(new) }
    }
}
