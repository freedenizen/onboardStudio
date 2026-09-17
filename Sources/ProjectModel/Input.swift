import Foundation

/// A path to a media or data file. Relative paths resolve against the project's directory.
public struct MediaReference: Hashable, Codable, Sendable {
    public var path: String

    public init(path: String) { self.path = path }

    public func resolved(relativeTo base: URL?) -> URL {
        if path.hasPrefix("/") || base == nil { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }
}

public struct VideoInputSettings: Hashable, Codable, Sendable {
    public var trim: TrimRange
    public var includeAudio: Bool
    /// Degrees, clockwise; any value, normally 0 / 90 / 180 / 270.
    public var rotation: Double
    public var mirror: Mirror
    public var crop: CropInsets
    public var color: ColorAdjustments
    public var chromaKey: ChromaKey?
    public var audio: AudioSettings

    public init(
        trim: TrimRange = .none,
        includeAudio: Bool = true,
        rotation: Double = 0,
        mirror: Mirror = .none,
        crop: CropInsets = .none,
        color: ColorAdjustments = .neutral,
        chromaKey: ChromaKey? = nil,
        audio: AudioSettings = .neutral
    ) {
        self.trim = trim
        self.includeAudio = includeAudio
        self.rotation = rotation
        self.mirror = mirror
        self.crop = crop
        self.color = color
        self.chromaKey = chromaKey
        self.audio = audio
    }

    // Older documents lack the picture/audio fields; decode them as neutral.
    private enum CodingKeys: String, CodingKey {
        case trim, includeAudio, rotation, mirror, crop, color, chromaKey, audio
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim) ?? .none
        includeAudio = try c.decodeIfPresent(Bool.self, forKey: .includeAudio) ?? true
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        mirror = try c.decodeIfPresent(Mirror.self, forKey: .mirror) ?? .none
        crop = try c.decodeIfPresent(CropInsets.self, forKey: .crop) ?? .none
        color = try c.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .neutral
        chromaKey = try c.decodeIfPresent(ChromaKey.self, forKey: .chromaKey)
        audio = try c.decodeIfPresent(AudioSettings.self, forKey: .audio) ?? .neutral
    }
}

public struct ImageInputSettings: Hashable, Codable, Sendable {
    public init() {}
}

public struct DataInputSettings: Hashable, Codable, Sendable {
    /// Importer id to force (e.g. `racechrono-csv`); `nil` auto-detects.
    public var importerID: String?
    /// Column name → channel role identifier (e.g. `"Coolant": "obd:Coolant"`, `"KPH": "speed"`).
    public var roleOverrides: [String: String]
    public var deriveSpeedFromPosition: Bool
    public var deriveHeadingFromPosition: Bool

    public init(
        importerID: String? = nil,
        roleOverrides: [String: String] = [:],
        deriveSpeedFromPosition: Bool = true,
        deriveHeadingFromPosition: Bool = true
    ) {
        self.importerID = importerID
        self.roleOverrides = roleOverrides
        self.deriveSpeedFromPosition = deriveSpeedFromPosition
        self.deriveHeadingFromPosition = deriveHeadingFromPosition
    }
}

public enum InputKind: Hashable, Codable, Sendable {
    case video(VideoInputSettings)
    case audio
    case image(ImageInputSettings)
    case data(DataInputSettings)

    public var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    public var isData: Bool {
        if case .data = self { return true }
        return false
    }

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

/// A source file (video, audio, image or telemetry) with its own sync settings.
public struct Input: Identifiable, Hashable, Codable, Sendable {
    public var id: InputID
    public var label: String
    public var source: MediaReference
    public var kind: InputKind
    public var sync: SyncSettings

    public init(
        id: InputID = InputID(), label: String, source: MediaReference, kind: InputKind, sync: SyncSettings = .identity
    ) {
        self.id = id
        self.label = label
        self.source = source
        self.kind = kind
        self.sync = sync
    }
}
