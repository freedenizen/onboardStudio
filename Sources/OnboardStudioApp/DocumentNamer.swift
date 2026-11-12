import AppKit
import ProjectModel
import SwiftUI

/// Gives a project that has not been saved the name `name` (#481) — its window's title, its entry
/// in the Window menu and what Save suggests — in place of "Untitled", numbered as Untitled is when
/// another open project has it already. Once the project has a file, AppKit calls it by the file.
/// It also tells the editor which window is its own, so an export can take the project's name
/// (#467). Put it in the background of the editor; it draws nothing.
struct DocumentNamer: NSViewRepresentable {
    let name: String?
    let editor: EditorModel

    func makeNSView(context: Context) -> NamerView {
        let view = NamerView()
        view.editor = editor
        return view
    }

    func updateNSView(_ view: NamerView, context: Context) {
        view.editor = editor
        view.name = name
        view.apply()
    }

    final class NamerView: NSView {
        weak var editor: EditorModel?
        var name: String?
        /// The name the document was given, and the name it was numbered from: a new name replaces
        /// it, the same one leaves its number alone.
        private var given: (shown: String, from: String)?

        override var isHidden: Bool {
            get { true }
            set {}
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            editor?.window = window
            // The window has its document a moment after the editor's view joins it.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let window, let document = NSDocumentController.shared.document(for: window) else { return }
            if editor?.window !== window { editor?.window = window }
            // Saved, the document is called by its file: AppKit takes the name it was given back
            // as it saves. Clearing it after that would make it a draft again — "Untitled -1".
            guard document.fileURL == nil else {
                given = nil
                return
            }
            let others = Set(NSDocumentController.shared.documents.filter { $0 !== document }.compactMap(\.displayName))
            guard let name, !name.isEmpty else {
                // Nothing to call it by any more: Untitled again, numbered as AppKit numbers it.
                if given != nil {
                    given = nil
                    document.displayName = ProjectNaming.numbered(document.defaultDraftName(), taken: others)
                    Self.retitle(document)
                }
                return
            }
            guard given?.from != name else { return }
            let shown = ProjectNaming.numbered(name, taken: others)
            given = (shown, name)
            document.displayName = shown
            Self.retitle(document)
        }

        private static func retitle(_ document: NSDocument) {
            for controller in document.windowControllers { controller.synchronizeWindowTitleWithDocumentName() }
        }
    }
}
