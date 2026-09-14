import Foundation

public struct ProjectSettings: Hashable, Codable, Sendable {
    public var outputWidth: Int
    public var outputHeight: Int
    public var frameRate: Double
    /// Explicit project length in seconds; `nil` means "until the last video input ends".
    public var duration: Double?

    public init(outputWidth: Int = 1920, outputHeight: Int = 1080, frameRate: Double = 30, duration: Double? = nil) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.frameRate = frameRate
        self.duration = duration
    }
}

/// The document model. Pure data; saved as `project.json` inside a `.overlayproj` package.
public struct Project: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var settings: ProjectSettings
    public var inputs: [Input]
    /// Bottom-to-top draw order.
    public var displayObjects: [DisplayObject]
    public var export: ExportSettings

    public init(
        schemaVersion: Int = Project.currentSchemaVersion,
        settings: ProjectSettings = ProjectSettings(),
        inputs: [Input] = [],
        displayObjects: [DisplayObject] = [],
        export: ExportSettings = .hd1080
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.inputs = inputs
        self.displayObjects = displayObjects
        self.export = export
    }

    public func input(_ id: InputID) -> Input? { inputs.first { $0.id == id } }
    public func displayObject(_ id: DisplayObjectID) -> DisplayObject? { displayObjects.first { $0.id == id } }

    public var videoInputs: [Input] { inputs.filter(\.kind.isVideo) }
    public var dataInputs: [Input] { inputs.filter(\.kind.isData) }

    // MARK: - Serialisation

    public static func decode(_ data: Data) throws -> Project {
        let decoder = JSONDecoder()
        var project = try decoder.decode(Project.self, from: data)
        try project.migrateIfNeeded()
        return project
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Upgrades older schema versions in place. Throws for versions newer than this build knows.
    public mutating func migrateIfNeeded() throws {
        guard schemaVersion != Self.currentSchemaVersion else { return }
        guard schemaVersion < Self.currentSchemaVersion else {
            throw ProjectError.unsupportedSchemaVersion(schemaVersion)
        }
        // Future migrations go here, stepping schemaVersion up one at a time.
        schemaVersion = Self.currentSchemaVersion
    }
}

public enum ProjectError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case notAProject(String)
    case missingInput(InputID)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "This project was saved by a newer version of OverlayGen (schema \(version))."
        case .notAProject(let path): "\(path) is not an OverlayGen project."
        case .missingInput(let id): "The project references an input that does not exist (\(id))."
        }
    }
}

/// Locates `project.json` for either a `.overlayproj` package directory or a bare JSON file, and
/// resolves relative media paths against the right base directory.
public struct ProjectLocation: Sendable, Equatable {
    public static let packageExtension = "overlayproj"
    public static let fileName = "project.json"

    public let jsonURL: URL
    /// Base for relative `MediaReference` paths.
    public let baseDirectory: URL

    public init(_ url: URL) {
        if url.pathExtension == Self.packageExtension {
            let directory = URL(fileURLWithPath: url.path, isDirectory: true)
            jsonURL = directory.appending(path: Self.fileName)
            baseDirectory = directory
        } else {
            jsonURL = url
            baseDirectory = URL(fileURLWithPath: url.deletingLastPathComponent().path, isDirectory: true)
        }
    }

    public func load() throws -> Project {
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { throw ProjectError.notAProject(jsonURL.path) }
        return try Project.decode(try Data(contentsOf: jsonURL))
    }

    public func save(_ project: Project) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try project.encoded().write(to: jsonURL, options: .atomic)
    }

    public func resolve(_ reference: MediaReference) -> URL {
        reference.resolved(relativeTo: baseDirectory)
    }
}
