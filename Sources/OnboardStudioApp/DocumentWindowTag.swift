import AppKit
import SwiftUI

/// Marks the window this sits in as one that edits the front document from outside it, so Edit ▸
/// Undo and Redo there act on the document's edits (`UndoMenuState`). Put it in the background of
/// such a window's content; it draws nothing.
struct DocumentWindowTag: NSViewRepresentable {
    func makeNSView(context: Context) -> TagView { TagView() }
    func updateNSView(_ nsView: TagView, context: Context) {}

    final class TagView: NSView {
        private weak var tagged: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let tagged, tagged !== window { UndoMenuState.shared.unregister(tagged) }
            tagged = window
            if let window { UndoMenuState.shared.register(window) }
        }

        override var isHidden: Bool {
            get { true }
            set {}
        }
    }
}
