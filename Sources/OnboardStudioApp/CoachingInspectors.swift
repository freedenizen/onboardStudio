import ProjectModel
import SwiftUI

/// The Corner Callout's inspector (#323): when the card appears and leaves, what it says, and its
/// colours. What it compares with is the project's coaching reference, set in Project ▸ Coaching….
struct CornerCalloutInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: CornerCalloutParams

    /// What the card measures against, in the words the Coaching window uses.
    private var reference: String {
        guard let settings = editor.project.coaching, settings.dataInputID == object.inputID else {
            return "your best lap"
        }
        switch settings.reference {
        case .sessionBest: return "your best lap"
        case .lap(let number): return "lap \(number)"
        case .fastestRolling: return "the fastest rolling lap"
        case .compositeOptimal: return "the optimal lap"
        case .otherInput(let id, let lap): return "\(editor.project.input(id)?.label ?? "another file") lap \(lap)"
        }
    }

    var body: some View {
        Section("Corner Callout") {
            NumberField(
                "Appears before the brake point (s)", value: field(\.leadSeconds, "Lead"), fractionDigits: 0...1,
                step: 0.5)
            NumberField(
                "Stays after the corner (s)", value: field(\.holdSeconds, "Hold"), fractionDigits: 0...1, step: 0.5)
            Toggle("Evidence lines", isOn: field(\.showEvidence, "Evidence"))
            Toggle("What to try", isOn: field(\.showSuggestion, "Suggestion"))
            Toggle("Only corners that lost time", isOn: field(\.onlyOpportunities, "Only Opportunities"))
            Text("Each corner is read against \(reference). Choose the lap and the reference in Project ▸ Coaching….")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Look") {
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
            ColorPicker("What to try", selection: color(\.secondaryColor, "Suggestion Colour"))
            ColorPicker("Time gained", selection: color(\.aheadColor, "Ahead Colour"))
            ColorPicker("Time lost", selection: color(\.behindColor, "Behind Colour"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"), supportsOpacity: true)
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<CornerCalloutParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<CornerCalloutParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout CornerCalloutParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .cornerCallout(new) }
    }
}
