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

    static func chooseExportDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
