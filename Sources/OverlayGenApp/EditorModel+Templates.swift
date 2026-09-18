import Foundation
import ProjectModel

/// Templates and media relinking.
extension EditorModel {
    // MARK: - Templates and relinking

    func apply(_ template: ProjectTemplate) {
        edit("Apply Template \(template.name)") { template.apply(to: &$0) }
        selectedObjectID = nil
        selectedSegmentID = nil
    }

    func applyTemplate(at url: URL) {
        do { apply(try TemplateStore.load(url)) } catch { errorMessage = "\(error)" }
    }

    func importTemplate() {
        guard let url = OpenPanels.chooseTemplate() else { return }
        applyTemplate(at: url)
    }

    func saveAsTemplate() {
        let suggested = fileURL?.deletingPathExtension().lastPathComponent ?? "My Template"
        guard let name = OpenPanels.askTemplateName(default: suggested) else { return }
        do {
            let url = try TemplateStore.save(ProjectTemplate(name: name, project: project), name: name)
            statusMessage = "Saved template \(url.lastPathComponent)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Points a missing or unreadable input at a new file.
    func relink(_ id: InputID) {
        guard let input = project.input(id) else { return }
        let url: URL? =
            switch input.kind {
            case .video, .audio: OpenPanels.chooseVideo()
            case .image: OpenPanels.chooseImage()
            case .data: OpenPanels.chooseData()
            }
        guard let url else { return }
        updateInput(id, name: "Relink Input") { $0.source = MediaReference.make(for: url, relativeTo: fileURL) }
    }
}
