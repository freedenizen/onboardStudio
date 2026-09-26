import AppKit
import ProjectModel

// MARK: - Accessibility (#153)

/// The preview is drawn, not built from controls, so without this VoiceOver and Voice Control
/// see one blank picture. Each object on it is exposed as an element of its own: it can be found
/// by name, pressed to select it, and moved with the same step the arrow keys use.
extension GizmoView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Preview" }

    override func accessibilityChildren() -> [Any]? {
        if editor.pictureTool == .frame { return framingAccessibilityChildren() }
        let shown = objects.filter(\.isVisible).reversed()
        objectElements = objectElements.filter { id, _ in shown.contains { $0.id == id } }
        return shown.map { object in
            let element = objectElements[object.id] ?? PreviewObjectElement(id: object.id, in: self)
            element.update(object, selected: object.id == selectedID, in: self)
            objectElements[object.id] = element
            return element
        }
    }

    /// Selects `id` as a click on it would.
    func accessibilitySelect(_ id: DisplayObjectID) {
        editor.selectedObjectID = id
        editor.selectedInputID = nil
        editor.selectedSegmentID = nil
        editor.selectedMarkerID = nil
    }

    /// Moves `id` by `dx`, `dy` steps of the arrow keys' ⇧ nudge.
    func accessibilityMove(_ id: DisplayObjectID, _ dx: Double, _ dy: Double) -> Bool {
        // A lock holds against VoiceOver's actions as it does against the mouse and arrows (#90).
        guard let object = objects.first(where: { $0.id == id }), !object.isLocked else { return false }
        let pixels = NudgeStep.pixels(shift: true)
        let frame = ObjectGeometry.nudged(object.frame, byPixels: dx * pixels, dy * pixels, in: editor.project.settings)
        editor.moveObject(id, frame: frame)
        return true
    }
}

// AppKit asks for these off the main actor's knowledge but always on the main thread.
nonisolated final class PreviewObjectElement: NSAccessibilityElement {
    private let id: DisplayObjectID
    private weak var gizmo: GizmoView?

    @MainActor
    init(id: DisplayObjectID, in gizmo: GizmoView) {
        self.id = id
        self.gizmo = gizmo
        super.init()
        setAccessibilityParent(gizmo)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Press to select; the actions move it.")
        let moves: [(String, CGVector)] = [
            ("Move Left", CGVector(dx: -1, dy: 0)), ("Move Right", CGVector(dx: 1, dy: 0)),
            ("Move Up", CGVector(dx: 0, dy: -1)), ("Move Down", CGVector(dx: 0, dy: 1)),
        ]
        setAccessibilityCustomActions(
            moves.map { name, step in
                NSAccessibilityCustomAction(name: name) { [weak self] in
                    guard let self, let gizmo = self.gizmo else { return false }
                    return MainActor.assumeIsolated { gizmo.accessibilityMove(self.id, step.dx, step.dy) }
                }
            })
    }

    /// Brings the name, selection and place up to date with `object` as it is now.
    @MainActor
    func update(_ object: DisplayObject, selected: Bool, in gizmo: GizmoView) {
        setAccessibilityLabel(
            object.label == object.kind.typeName ? object.label : "\(object.label), \(object.kind.typeName)")
        setAccessibilityIdentifier("preview.object.\(object.label)")
        setAccessibilityValue(selected ? "Selected" : nil)
        let rect = gizmo.viewRect(object.frame).intersection(gizmo.bounds)
        if let window = gizmo.window {
            setAccessibilityFrame(window.convertToScreen(gizmo.convert(rect, to: nil)))
        }
    }

    override func accessibilityPerformPress() -> Bool {
        let id = id
        let target = gizmo
        return MainActor.assumeIsolated {
            target?.accessibilitySelect(id)
            return target != nil
        }
    }
}

/// How far one press of an arrow key moves the selected object, in output pixels.
///
/// The plain step is a preference so it can be matched to how fine the user's layouts are; ⇧
/// multiplies it, which is the gesture every editor uses for "the same thing, but coarser".
enum NudgeStep {
    static let shiftMultiplier = 10.0

    static func pixels(shift: Bool, defaults: UserDefaults = .standard) -> Double {
        // Read through `Preferences` like every other setting. It used to be `double(forKey:)`
        // here and `@AppStorage` in Settings — two mechanisms for one key, and this one needed a
        // "treat zero as unset" guard to make up for `double(forKey:)` returning zero for both.
        let step = defaults.value(for: Preferences.nudgeStepPixels)
        return shift ? step * shiftMultiplier : step
    }
}
