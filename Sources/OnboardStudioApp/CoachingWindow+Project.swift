import AppKit
import ProjectModel
import SwiftUI

/// The project behind a logbook session's coaching (#396, #462).
extension CoachingWindow {
    /// The Logbook's Coach… (#462). A project already open on the session has what the session's
    /// numbers alone do not — the plan, Show Me on the picture, Compare in Video — so the window
    /// reads that project, which comes forward behind it; with none open it reads the session
    /// with no project (#396).
    static func open(_ openWindow: OpenWindowAction, coaching entry: LogbookEntry) {
        guard let editor = ActiveEditor.shared.editor(coaching: entry) else { return open(openWindow, entry: entry) }
        ActiveEditor.shared.window(of: editor)?.orderFront(nil)
        ActiveEditor.shared.editor = editor
        open(openWindow)
    }
}

extension CoachingContent {
    /// The project open on the session this window reads from the logbook, when there is one.
    private var openProject: EditorModel? {
        (source as? LogbookCoachingSource).flatMap { ActiveEditor.shared.editor(coaching: $0.entry) }
    }

    /// In place of the plan and the picture for a logbook session: a project from it, which the
    /// window then follows (#396) — the one already open on the session when there is one, rather
    /// than a second beside it (#462).
    var makeProject: some View {
        let open = openProject
        return VStack(alignment: .leading, spacing: 6) {
            Text("Next Session").font(.subheadline.weight(.semibold))
            Text(Self.projectNeeded(openTitle: open.map { ActiveEditor.shared.window(of: $0)?.title ?? "A project" }))
                .font(.callout).foregroundStyle(.secondary)
            if open != nil {
                Button("Use the Open Project") { followOrMakeProject() }
                    .accessibilityIdentifier("coaching.useOpenProject")
            } else {
                Button("Make a Project") { followOrMakeProject() }
                    .accessibilityIdentifier("coaching.makeProject")
            }
        }
    }

    /// Why there is no plan here, and what the button does about it.
    static func projectNeeded(openTitle: String?) -> String {
        let need = "A plan, Show Me on the picture and Compare in Video need a project. "
        guard let openTitle else {
            return need
                + "Make one from this session — its data file, its clips and the last layout used — and the "
                + "window follows it."
        }
        return need + "“\(openTitle)” is open on this session, and the window can follow it."
    }

    /// Looked for again when the button is pressed: a project may have opened or closed since the
    /// window was drawn. The project goes behind this window, not over it.
    private func followOrMakeProject() {
        guard let source = source as? LogbookCoachingSource else { return }
        guard let editor = ActiveEditor.shared.editor(coaching: source.entry) else {
            LogbookModel.shared.openAsProject(source.entry, template: LogbookModel.lastTemplate(), then: .coaching)
            return
        }
        if let own = NSApp.keyWindow {
            ActiveEditor.shared.window(of: editor)?.order(.below, relativeTo: own.windowNumber)
        }
        ActiveEditor.shared.editor = editor
        CoachingTarget.shared.showFrontProject()
    }
}
