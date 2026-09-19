import AppKit
import ProjectModel
import UniformTypeIdentifiers

enum OpenPanels {
    static func chooseVideo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add Video"
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2TransportStream, .data]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Several video files at once.
    static func chooseVideos(
        title: String = "Add Clips", message: String = "Choose the files to play after the current video, in order."
    ) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2TransportStream, .data]
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent } : []
    }

    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add Image"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseData() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add Data File"
        panel.allowedContentTypes = [
            .commaSeparatedText, .plainText, .xml, UTType(filenameExtension: "gpx") ?? .xml, .data,
        ]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static let styleType = UTType(exportedAs: "com.freedenizen.overlaygen.style", conformingTo: .json)

    static func chooseStyle() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Object Style"
        panel.allowedContentTypes = [styleType, .json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseStyleDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Object Style"
        panel.allowedContentTypes = [styleType]
        panel.nameFieldStringValue = suggestedName + "." + ObjectStyle.fileExtension
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static let templateType = UTType(exportedAs: "com.freedenizen.overlaygen.template", conformingTo: .json)

    static func chooseTemplate() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Template"
        panel.allowedContentTypes = [templateType, .json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for a template name; returns nil when cancelled.
    static func askTemplateName(default name: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Save as Template"
        alert.informativeText = "The objects, timeline and export settings are saved; inputs are not."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func chooseExportDestination(suggestedName: String, fileExtension: String = "mp4") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.allowedContentTypes = [fileExtension == "mov" ? .quickTimeMovie : .mpeg4Movie]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
