import ProjectModel
import RenderKit
import SwiftUI
import TelemetryKit

/// An object's own display unit, the bottom level of #89's chain: what this one object shows its
/// channel in, whatever the project and the global mapping chose.
///
/// Offers only units the channel's values can actually be converted into, so a temperature gauge
/// is never asked whether it would like to be in bar. Shown in place of `SpeedUnitPicker` for
/// every channel that is not a speed — speed keeps its own control, because #75's setting is what
/// saved projects carry and what spells km/h `kph`.
struct DisplayUnitPicker: View {
    let editor: EditorModel
    let object: DisplayObject

    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    @AppStorage(Preferences.attributeMappings.key) private var globalMappings = Preferences.attributeMappings.unset

    /// The channel this object draws. The first, for a graph: a display unit applies to every
    /// series it can convert, and the rest are simply not convertible into it.
    private var channel: String? { object.kind.displayChannels.first }

    /// The unit the channel's values are stored in, which is what they would convert *from* and
    /// therefore what decides the choices. `nil` when there is no data loaded to ask.
    private var storedUnit: TelemetryUnit? {
        guard let channel, let role = ChannelRole(identifier: channel),
            let inputID = object.inputID ?? editor.project.dataInputs.first?.id
        else { return nil }
        return editor.sessions[inputID]?[role]?.unit
    }

    private var options: [TelemetryUnit] { storedUnit?.convertibleUnits ?? [] }

    /// Asked of the same resolver the renderer uses, so the caption cannot disagree with the
    /// picture.
    private var resolved: DisplayUnits {
        RenderPlanner.displayUnits(
            for: object, in: editor.project, sessions: editor.sessions,
            appSpeedUnit: SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic,
            globalAttributeMappings: AttributeMappingTable(json: globalMappings))
    }

    var body: some View {
        // One convertible unit is the unit it is already in; offering a choice of one is noise.
        if options.count > 1 {
            Picker("Unit", selection: selection) {
                Text("Automatic").tag("")
                ForEach(options, id: \.self) { Text($0.symbol).tag($0.symbol) }
            }
            .accessibilityIdentifier("object.displayUnit")
            if object.displayUnit == nil, let channel, let shown = resolved.label(for: channel) {
                Text("Showing \(shown), from the attribute's default.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("object.displayUnitResolved")
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { object.displayUnit ?? "" },
            set: { chosen in
                editor.updateObject(object.id, name: "Change Display Unit") {
                    $0.displayUnit = chosen.isEmpty ? nil : chosen
                }
            })
    }
}

extension DisplayObject {
    /// Whether this object's unit is chosen with `SpeedUnitPicker` rather than `DisplayUnitPicker`.
    /// Speed is the one attribute with a control of its own, kept because #75's setting is what
    /// saved projects carry.
    var usesSpeedUnitPicker: Bool {
        kind.displayChannels.contains { ChannelRole(identifier: $0) == .speed }
    }
}
