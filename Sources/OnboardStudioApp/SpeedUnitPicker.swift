import ProjectModel
import SwiftUI

/// An object's speed unit, which may defer to the project, the app, or the data (#75).
struct SpeedUnitPicker: View {
    @Binding var selection: SpeedUnitSetting
    /// What *Automatic* currently works out to, and which level decided it, so choosing to
    /// inherit does not mean losing sight of what is drawn.
    var resolved: (unit: SpeedDisplayUnit, source: UnitSource)?

    var body: some View {
        Picker("Speed unit", selection: $selection) {
            ForEach(SpeedUnitSetting.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .accessibilityIdentifier("object.speedUnit")
        if selection == .automatic, let resolved, let from = resolved.source.describedAsInherited {
            Text("Showing \(resolved.unit.rawValue) \(from).")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("object.speedUnitResolved")
        }
    }
}
