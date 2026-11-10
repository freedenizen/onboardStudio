import AppKit
import ProjectModel
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
        set {
            storage = newValue
            guard let newValue else { return }
            let window = window(of: newValue)
            opened.removeAll { $0.editor == nil || $0.editor === newValue }
            opened.insert(Opened(editor: newValue, window: window), at: 0)
        }
    }

    /// Every project that has been the active one, the latest first, with the window it is in.
    /// Weak for the same reason: this is a way to find a project, not a reason for one to stay.
    private var opened: [Opened] = []

    private struct Opened {
        weak var editor: EditorModel?
        weak var window: NSWindow?
    }

    /// The window `editor` is in, as `EditorWindowLink` told it.
    func window(of editor: EditorModel) -> NSWindow? { opened.first { $0.editor === editor }?.window }

    func link(_ editor: EditorModel, to window: NSWindow?) {
        if let index = opened.firstIndex(where: { $0.editor === editor }) {
            if opened[index].window !== window { opened[index].window = window }
        } else if let window {
            opened.append(Opened(editor: editor, window: window))
        }
    }

    /// The open project whose coaching reads the logbook session `entry` (#462): Coach… in the
    /// Logbook reads that project rather than the session's numbers alone, and Make a Project
    /// follows it rather than making a second beside it. The project is asked first and its
    /// window second, so a view that draws from this is drawn again when a project changes.
    func editor(coaching entry: LogbookEntry) -> EditorModel? {
        opened.first { item in
            guard let editor = item.editor, editor.coaches(entry) else { return false }
            // On screen or in the Dock: a window that has closed is not an open project.
            return item.window?.isVisible == true || item.window?.isMiniaturized == true
        }?.editor
    }

    private init() {}
}

/// Tells `ActiveEditor` which window an editor is in, so a window that is not the document's own
/// can tell whether the project is still open and bring it forward (#462). Put it in the
/// background of the editor's content; it draws nothing.
struct EditorWindowLink: NSViewRepresentable {
    let editor: EditorModel

    func makeNSView(context: Context) -> LinkView {
        let view = LinkView()
        view.editor = editor
        return view
    }

    func updateNSView(_ view: LinkView, context: Context) { view.editor = editor }

    final class LinkView: NSView {
        weak var editor: EditorModel?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let editor { ActiveEditor.shared.link(editor, to: window) }
        }

        override var isHidden: Bool {
            get { true }
            set {}
        }
    }
}
