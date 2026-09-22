import SwiftUI

/// The editor whose document the user is looking at, for windows that are not part of that
/// document's own scene.
///
/// `@FocusedValue(\.editor)` reaches the front document from the menu bar, because the menu bar
/// belongs to whichever scene is focused. A separate window is its own scene and has no such
/// relationship, so the attribute window would otherwise have no way to know which project it is
/// mapping. This is that relationship, made explicit.
///
/// Weak on purpose: a document that closes must be able to go, and the window shows its empty
/// state rather than holding the last project open in memory.
@MainActor @Observable final class ActiveEditor {
    static let shared = ActiveEditor()

    private weak var storage: EditorModel?

    var editor: EditorModel? {
        get { storage }
        set { storage = newValue }
    }

    private init() {}
}
