import AppKit
import ProjectModel

/// What a project is called, before it is saved and in what it exports (#481, #467).
extension EditorModel {
    /// What this project is called until it is saved: the session it was made from, else its
    /// Details when they say where or when; `nil` leaves it "Untitled" (#481).
    var untitledName: String? { sessionName ?? ProjectNaming.name(details: project.details) }

    /// What a video exported from this project is called, before its extension (#467): the
    /// project's file once it is saved, else what its window is called.
    var exportBaseName: String {
        let document = window.flatMap { NSDocumentController.shared.document(for: $0) }
        if let url = document?.fileURL ?? fileURL {
            return ProjectNaming.fileName(url.deletingPathExtension().lastPathComponent)
        }
        return ProjectNaming.fileName(document?.displayName ?? untitledName ?? "Untitled")
    }
}
