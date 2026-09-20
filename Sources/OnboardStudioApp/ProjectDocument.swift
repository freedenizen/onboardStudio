import Combine
import ProjectModel
import SwiftUI
import UniformTypeIdentifiers

/// The document: a value-type `Project` with undo via snapshots.
///
/// SwiftUI's document machinery calls `init(configuration:)`, `snapshot` and `fileWrapper` off the
/// main actor, so the stored value is `nonisolated(unsafe)`; every mutation goes through `apply`,
/// which is main-actor only, and reads from SwiftUI happen on the main actor via `project`.
@MainActor
final class ProjectDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = Project

    /// Pre-rename projects stay readable; saving always writes the current type, so opening an
    /// old project and saving it migrates the document in place.
    nonisolated static let readableContentTypes: [UTType] = [.onboardProject, .legacyOverlayProject]
    nonisolated static let writableContentTypes: [UTType] = [.onboardProject]

    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    nonisolated(unsafe) private var storage: Project

    var project: Project {
        get { storage }
        set {
            objectWillChange.send()
            storage = newValue
        }
    }

    nonisolated init(project: Project = Project()) {
        storage = project
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        storage = try ProjectPackage.read(configuration.file)
    }

    nonisolated func snapshot(contentType: UTType) throws -> Project { storage }

    nonisolated func fileWrapper(snapshot: Project, configuration: WriteConfiguration) throws -> FileWrapper {
        try ProjectPackage.write(snapshot, existing: configuration.existingFile)
    }

    /// Applies an edit and registers its inverse with the undo manager.
    func apply(_ undoManager: UndoManager?, name: String, _ edit: (inout Project) -> Void) {
        let before = project
        var after = project
        edit(&after)
        guard after != before else { return }
        project = after
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.apply(undoManager, name: name) { $0 = before }
            }
        }
        undoManager?.setActionName(name)
    }
}
