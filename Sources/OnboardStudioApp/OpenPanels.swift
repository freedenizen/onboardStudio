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

    static let styleType = UTType(exportedAs: "com.freedenizen.onboardstudio.style", conformingTo: .json)
    /// Styles exported under the app's former name, OverlayGen.
    static let legacyStyleType = UTType(importedAs: ObjectStyle.legacyPasteboardType, conformingTo: .json)

    static func chooseStyle() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Object Style"
        panel.allowedContentTypes = [styleType, legacyStyleType, .json]
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

    /// A track definition: one circuit's start/finish line, sectors and corner names.
    ///
    /// Worth its own file type because no licence can give us sector geometry, so a definition one
    /// driver works out and hands to another is the only route there is to a shared library.
    static let trackType = UTType(exportedAs: "com.freedenizen.onboardstudio.track", conformingTo: .json)

    static func chooseTrack() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Track Definition"
        panel.allowedContentTypes = [trackType, .json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseTrackDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Track Definition"
        panel.allowedContentTypes = [trackType]
        panel.nameFieldStringValue = suggestedName + "." + TrackLibrary.fileExtension
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static let templateType = UTType(exportedAs: "com.freedenizen.onboardstudio.template", conformingTo: .json)
    /// Templates exported under the app's former name, OverlayGen.
    static let legacyTemplateType = UTType(
        importedAs: "com.freedenizen.overlaygen.template", conformingTo: .json)

    static func chooseTemplate(title: String = "Import Template") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [templateType, legacyTemplateType, .json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Where to export one of the user's templates for sharing.
    static func chooseTemplateDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Template"
        panel.allowedContentTypes = [templateType]
        panel.nameFieldStringValue = suggestedName + "." + ProjectTemplate.fileExtension
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for a marker's name; returns nil when cancelled.
    static func askMarkerName(default name: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name Marker"
        alert.informativeText = "Markers you cannot tell apart are markers you lose."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// The folder an every-lap export writes its files into (#150).
    static func chooseExportFolder() -> URL? {
        if let directory = UITestSupport.exportDirectory { return directory }
        let panel = NSOpenPanel()
        panel.title = "Export Every Lap"
        panel.message = "Each lap is written here as its own file."
        panel.prompt = "Export Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportDestination(suggestedName: String, fileExtension: String = "mp4") -> URL? {
        if let directory = UITestSupport.exportDirectory {
            return directory.appending(path: suggestedName).appendingPathExtension(fileExtension)
        }
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.allowedContentTypes = [fileExtension == "mov" ? .quickTimeMovie : .mpeg4Movie]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
