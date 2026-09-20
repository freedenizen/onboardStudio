import Foundation

/// Reads and writes the `.onboardproj` package as `FileWrapper`s, for use by document-based apps.
public enum ProjectPackage {
    public static let contentTypeIdentifier = "com.freedenizen.onboardstudio.project"
    /// The identifier used before the app was renamed from OverlayGen. Still read, never written.
    public static let legacyContentTypeIdentifier = "com.freedenizen.overlaygen.project"

    public static func read(_ wrapper: FileWrapper) throws -> Project {
        if wrapper.isDirectory {
            guard let json = wrapper.fileWrappers?[ProjectLocation.fileName], let data = json.regularFileContents else {
                throw ProjectError.notAProject("package without \(ProjectLocation.fileName)")
            }
            return try Project.decode(data)
        }
        guard let data = wrapper.regularFileContents else { throw ProjectError.notAProject("empty file") }
        return try Project.decode(data)
    }

    public static func write(_ project: Project, existing: FileWrapper? = nil) throws -> FileWrapper {
        let json = FileWrapper(regularFileWithContents: try project.encoded())
        json.preferredFilename = ProjectLocation.fileName
        let directory: FileWrapper
        if let existing, existing.isDirectory {
            directory = existing
        } else {
            directory = FileWrapper(directoryWithFileWrappers: [:])
        }
        if let old = directory.fileWrappers?[ProjectLocation.fileName] { directory.removeFileWrapper(old) }
        directory.addFileWrapper(json)
        return directory
    }
}

extension MediaReference {
    /// Builds a reference for `url`, relative to `base` when the file lives inside it, else absolute.
    public static func make(for url: URL, relativeTo base: URL?) -> MediaReference {
        let target = url.standardizedFileURL.path
        if let base {
            let basePath =
                base.standardizedFileURL.path.hasSuffix("/")
                ? base.standardizedFileURL.path : base.standardizedFileURL.path + "/"
            if target.hasPrefix(basePath) {
                return MediaReference(path: String(target.dropFirst(basePath.count)))
            }
        }
        return MediaReference(path: target)
    }
}
