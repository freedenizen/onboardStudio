import AppKit
import ProjectModel
import SwiftUI
import UniformTypeIdentifiers

// Kept out of `LogbookWindow`'s body, which SwiftLint holds to 250 lines.
extension LogbookWindow {
    // MARK: - Taking it with you (#350)

    /// What goes out: the sessions shown, which is the whole logbook unless it is narrowed.
    var exported: [LogbookEntry] { shown }

    func exportLogbook(includingFiles: Bool) {
        guard
            let folder = OpenPanels.chooseExportFolder(
                title: "Export Logbook", message: "Each session is written here as its own file.")
        else { return }
        do {
            let destination = folder.appending(path: "Logbook")
            let summary = try LogbookTransfer.export(
                exported, days: model.days, cars: model.cars, goals: model.goals, to: destination,
                includingFiles: includingFiles)
            let files = includingFiles ? ", \(summary.filesCopied) data files copied" : ""
            message = "Wrote \(summary.written) sessions to \(destination.lastPathComponent)\(files)."
        } catch {
            message = "Could not export the logbook: \(error.localizedDescription)"
        }
    }

    func exportCSV(laps: Bool) {
        let name = laps ? "Logbook laps" : "Logbook"
        guard
            let url = OpenPanels.chooseDocumentDestination(
                title: "Export as CSV", suggestedName: name, type: .commaSeparatedText, fileExtension: "csv")
        else { return }
        let text = laps ? LogbookTransfer.lapsCSV(exported) : LogbookTransfer.sessionsCSV(exported, days: model.days)
        write(text, to: url, what: laps ? "the laps" : "\(exported.count) sessions")
    }

    func exportMarkdown() {
        guard
            let url = OpenPanels.chooseDocumentDestination(
                title: "Export Logbook as Markdown", suggestedName: "Logbook",
                type: UTType(filenameExtension: "md") ?? .plainText, fileExtension: "md")
        else { return }
        write(LogbookTransfer.markdown(exported, title: scope.title), to: url, what: "\(exported.count) sessions")
    }

    func write(_ text: String, to url: URL, what: String) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            message = "Wrote \(what) to \(url.lastPathComponent)."
        } catch {
            message = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func importLogbook() {
        guard let folder = OpenPanels.chooseLogbookFolder() else { return }
        // A folder written by Export Logbook… holds its sessions in "Logbook"; either is fine.
        let inner = folder.appending(path: "Logbook")
        let source = FileManager.default.fileExists(atPath: inner.path) ? inner : folder
        do {
            // One step of Undo, as an import of files is (#454).
            let before = AppLogbook.shared.snapshot()
            let summary = try LogbookTransfer.import(from: source, into: AppLogbook.shared)
            model.reload()
            model.record("Import Logbook Export", since: before, undo: undoManager)
            message =
                "\(summary.added) sessions added, \(summary.updated) updated, \(summary.skipped) already here."
        } catch {
            message = "Could not read that folder: \(error.localizedDescription)"
        }
    }
}
