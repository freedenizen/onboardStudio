import ProjectModel
import RenderKit
import SwiftUI

/// An object's speed unit, which may defer to the project, the app, or the data (#75).
struct SpeedUnitPicker: View {
    let editor: EditorModel
    let object: DisplayObject
    @Binding var selection: SpeedUnitSetting
    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset

    /// What *Automatic* currently works out to, and which level decided it, so choosing to
    /// inherit does not mean losing sight of what is drawn. Asked of the same resolver the
    /// renderer uses, so the caption cannot disagree with the picture.
    private var resolver: UnitResolver {
        RenderPlanner.unitResolver(
            for: object, in: editor.project, sessions: editor.sessions,
            appSpeedUnit: SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic)
    }

    var body: some View {
        Picker("Speed unit", selection: $selection) {
            ForEach(SpeedUnitSetting.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .accessibilityIdentifier("object.speedUnit")
        if selection == .automatic, let from = resolver.source(.automatic).describedAsInherited {
            Text("Showing \(resolver.speed(.automatic).rawValue) \(from).")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("object.speedUnitResolved")
        }
    }
}
