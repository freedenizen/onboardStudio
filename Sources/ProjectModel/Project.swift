import Foundation

public struct ProjectSettings: Hashable, Codable, Sendable {
    public var outputWidth: Int
    public var outputHeight: Int
    public var frameRate: Double
    /// Explicit project length in seconds; `nil` means "until the last video input ends".
    public var duration: Double?
    /// Zoom, pan and crop applied to every video input (M15).
    public var framing: CameraFraming
    /// Opacity of the whole overlay layer (every object except videos), on top of each object's
    /// own opacity: one knob for a more see-through dashboard.
    public var overlayOpacity: Double
    /// Speed unit for every object in this project that has not pinned its own (#75). `automatic`
    /// follows the app-wide preference, which in turn follows the data.
    public var speedUnit: SpeedUnitSetting
    /// This project's attribute mapping (#111, #89): where each attribute comes from, what its
    /// numbers are in and what objects show it in. Deviations from the global mapping in
    /// preferences; a single input can deviate again.
    public var attributeMappings: AttributeMappingTable
    /// The font for every object in this project that has not chosen its own (#118). `nil` leaves
    /// each object in its built-in fonts, which is what a project saved before fonts could be
    /// chosen always did.
    public var typeface: Typeface?

    public init(
        outputWidth: Int = 1920, outputHeight: Int = 1080, frameRate: Double = 30, duration: Double? = nil,
        framing: CameraFraming = .none, overlayOpacity: Double = 1, speedUnit: SpeedUnitSetting = .automatic,
        attributeMappings: AttributeMappingTable = AttributeMappingTable(), typeface: Typeface? = nil
    ) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.frameRate = frameRate
        self.duration = duration
        self.framing = framing
        self.overlayOpacity = overlayOpacity
        self.speedUnit = speedUnit
        self.attributeMappings = attributeMappings
        self.typeface = typeface
    }

    private enum CodingKeys: String, CodingKey {
        case outputWidth, outputHeight, frameRate, duration, framing, overlayOpacity, speedUnit
        case attributeMappings, typeface
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProjectSettings()
        outputWidth = try c.decodeIfPresent(Int.self, forKey: .outputWidth) ?? d.outputWidth
        outputHeight = try c.decodeIfPresent(Int.self, forKey: .outputHeight) ?? d.outputHeight
        frameRate = try c.decodeIfPresent(Double.self, forKey: .frameRate) ?? d.frameRate
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        framing = try c.decodeIfPresent(CameraFraming.self, forKey: .framing) ?? .none
        overlayOpacity = try c.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? 1
        // A project saved before the chain existed had every object asserting its own unit, so
        // there was nothing for a project level to mean. `automatic` is therefore both the new
        // default and the right reading of an absent key: it changes nothing, because every object
        // in such a file pins its own unit anyway.
        speedUnit = try c.decodeIfPresent(SpeedUnitSetting.self, forKey: .speedUnit) ?? .automatic
        // Absent before the attribute table existed. An empty table is automatic on every field,
        // and automatic on every field is precisely what such a project already did.
        attributeMappings =
            try c.decodeIfPresent(AttributeMappingTable.self, forKey: .attributeMappings) ?? AttributeMappingTable()
        // Absent before fonts could be chosen, and absent means the built-in fonts it always drew.
        typeface = try c.decodeIfPresent(Typeface.self, forKey: .typeface)
    }

    /// The same settings with the framing removed (framing is applied by the compositor, so it
    /// never needs the media composition rebuilt).
    public var withoutFraming: ProjectSettings {
        var copy = self
        copy.framing = .none
        copy.overlayOpacity = 1
        return copy
    }
}

/// The document model. Pure data; saved as `project.json` inside a `.onboardproj` package.
public struct Project: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var settings: ProjectSettings
    public var inputs: [Input]
    /// Bottom-to-top draw order, as they are before the first timeline segment.
    public var displayObjects: [DisplayObject]
    public var export: ExportSettings
    /// Time-based changes to object visibility, position and opacity (camera switches, layouts).
    public var timeline: Timeline
    /// Named points and ranges worth coming back to. Unordered here; use `markersInProjectTime()`.
    public var markers: [Marker]

    public init(
        schemaVersion: Int = Project.currentSchemaVersion,
        settings: ProjectSettings = ProjectSettings(),
        inputs: [Input] = [],
        displayObjects: [DisplayObject] = [],
        export: ExportSettings = .hd1080,
        timeline: Timeline = .empty,
        markers: [Marker] = []
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.inputs = inputs
        self.displayObjects = displayObjects
        self.export = export
        self.timeline = timeline
        self.markers = markers
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, settings, inputs, displayObjects, export, timeline, markers
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        settings = try c.decodeIfPresent(ProjectSettings.self, forKey: .settings) ?? ProjectSettings()
        inputs = try c.decodeIfPresent([Input].self, forKey: .inputs) ?? []
        displayObjects = try c.decodeIfPresent([DisplayObject].self, forKey: .displayObjects) ?? []
        export = try c.decodeIfPresent(ExportSettings.self, forKey: .export) ?? .hd1080
        timeline = try c.decodeIfPresent(Timeline.self, forKey: .timeline) ?? .empty
        // Absent in projects saved before markers existed; an empty list is the right reading.
        markers = try c.decodeIfPresent([Marker].self, forKey: .markers) ?? []
    }

    /// The objects as they appear at project `time`, with timeline overrides applied.
    public func displayObjects(at time: Double) -> [DisplayObject] {
        timeline.resolve(displayObjects, at: time)
    }

    /// Video objects in draw order.
    public var videoObjects: [DisplayObject] {
        displayObjects.filter { if case .video = $0.kind { return true } else { return false } }
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
            "This project was saved by a newer version of Onboard Studio (schema \(version))."
        case .notAProject(let path): "\(path) is not an Onboard Studio project."
        case .missingInput(let id): "The project references an input that does not exist (\(id))."
        }
    }
}

/// Locates `project.json` for either a `.onboardproj` package directory or a bare JSON file, and
/// resolves relative media paths against the right base directory.
public struct ProjectLocation: Sendable, Equatable {
    public static let packageExtension = "onboardproj"
    /// The extension used before the app was renamed from OverlayGen. Still opened, never written.
    public static let legacyPackageExtension = "overlayproj"
    public static let fileName = "project.json"

    /// True for a path this app treats as a project package, under either the current or the
    /// pre-rename extension.
    public static func isPackageExtension(_ ext: String) -> Bool {
        ext == packageExtension || ext == legacyPackageExtension
    }

    public let jsonURL: URL
    /// Base for relative `MediaReference` paths.
    public let baseDirectory: URL

    public init(_ url: URL) {
        if Self.isPackageExtension(url.pathExtension) {
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
