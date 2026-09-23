import AppKit
import ProjectModel
import RenderKit
import SwiftUI

extension TemplateLibrary {
    /// The library the app reads and writes: Application Support, or the scratch folder the UI
    /// tests give it so they never touch the templates of whoever runs them.
    static var app: TemplateLibrary {
        TemplateLibrary(
            directory: UITestSupport.templatesDirectory,
            trashesRemovedFiles: UITestSupport.templatesDirectory == nil)
    }
}

/// What a template looks like, drawn in the background: a card or a sheet shows its name at once
/// and its picture a moment later rather than holding the window up for it.
struct TemplatePicture: View {
    let template: ProjectTemplate?
    var width: CGFloat

    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        ZStack {
            shape.fill(.quaternary)
            if let image {
                Image(decorative: image, scale: displayScale).resizable().scaledToFit()
                    .clipShape(shape)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .overlay(shape.strokeBorder(.separator))
        .accessibilityHidden(true)
        .task(id: template) {
            guard let template else { return }
            let pixels = Int(width * displayScale)
            image = await Task.detached(priority: .utility) {
                TemplateThumbnail.image(of: template, width: pixels)
            }.value
        }
    }
}

/// Template actions that belong to no one project: adding a template file to the library, from
/// the File menu or by opening one in the Finder.
enum TemplateImport {
    /// Asks for a template file and adds it to the library.
    @MainActor static func chooseAndAdd() {
        guard let url = OpenPanels.chooseTemplate() else { return }
        add([url])
    }

    /// Adds template files to the library and says where they went.
    @MainActor static func add(_ urls: [URL]) {
        var added: [String] = []
        var failed: [String] = []
        for url in urls {
            do {
                added.append(try TemplateLibrary.app.importTemplate(from: url).name)
            } catch {
                failed.append(url.deletingPathExtension().lastPathComponent)
            }
        }
        NotificationCenter.default.post(name: .templatesChanged, object: nil)
        let alert = NSAlert()
        let whereToFind = "Start a project from it in the welcome window or with File ▸ New from Template."
        let unreadable = failed.map { "“\($0)”" }.joined(separator: ", ")
        switch (added.count, failed.count) {
        case (_, 0):
            alert.messageText =
                added.count == 1 ? "Added “\(added[0])” to Your Templates" : "Added \(added.count) Templates"
            alert.informativeText = whereToFind
        case (0, _):
            alert.alertStyle = .warning
            alert.messageText =
                failed.count == 1
                ? "“\(failed[0])” Is Not an Onboard Studio Template" : "These Are Not Onboard Studio Templates"
            alert.informativeText = "\(unreadable) could not be read as a template, so nothing was added."
        default:
            alert.alertStyle = .warning
            alert.messageText = "Added \(added.count) of \(added.count + failed.count) Templates"
            alert.informativeText = "\(unreadable) could not be read as a template. \(whereToFind)"
        }
        alert.runModal()
    }
}

extension Notification.Name {
    /// Posted when templates are added, renamed or removed, so open lists refresh.
    static let templatesChanged = Notification.Name("OnboardStudioTemplatesChanged")
}
