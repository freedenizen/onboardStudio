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
    /// Fisheye / 360° unwrap (M12); `.none` leaves the picture as recorded.
    public var lens: LensSettings
    /// Further files played back to back after `source` as one continuous video (camera
    /// chapters); trim, sync and picture settings apply to the whole sequence.
    public var clips: [MediaReference]

    public init(
        trim: TrimRange = .none,
        includeAudio: Bool = true,
        rotation: Double = 0,
        mirror: Mirror = .none,
        crop: CropInsets = .none,
        color: ColorAdjustments = .neutral,
        chromaKey: ChromaKey? = nil,
        audio: AudioSettings = .neutral,
        lens: LensSettings = .none,
        clips: [MediaReference] = []
    ) {
        self.trim = trim
        self.includeAudio = includeAudio
        self.rotation = rotation
        self.mirror = mirror
        self.crop = crop
        self.color = color
        self.chromaKey = chromaKey
        self.audio = audio
        self.lens = lens
        self.clips = clips
    }

    // Older documents lack the picture/audio fields; decode them as neutral.
    private enum CodingKeys: String, CodingKey {
        case trim, includeAudio, rotation, mirror, crop, color, chromaKey, audio, lens, clips
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
        lens = try c.decodeIfPresent(LensSettings.self, forKey: .lens) ?? .none
        clips = try c.decodeIfPresent([MediaReference].self, forKey: .clips) ?? []
    }
}

public struct ImageInputSettings: Hashable, Codable, Sendable {
    public init() {}
}

/// A user-defined channel: `name` becomes `aux:<name>`, `expression` uses the calculated-field
/// language (`speed * 3.6`, `if(rpm > 6500, 1, 0)`, `[aux:Oil temp] - coolant`).
public struct CalculatedFieldSpec: Hashable, Codable, Sendable {
    public var name: String
    public var expression: String
    public var unit: String

    public init(name: String, expression: String, unit: String = "") {
        self.name = name
        self.expression = expression
        self.unit = unit
    }
}

/// Start/finish line for lap detection.
public struct LapLineSpec: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Direction of travel across the line in degrees, or `nil` for any direction.
    public var headingDegrees: Double?
    public var halfWidthMeters: Double
    public var headingToleranceDegrees: Double
    /// Warm-up crossings to skip before lap 1 starts.
    public var ignoreFirstCrossings: Int

    public init(
        latitude: Double,
        longitude: Double,
        headingDegrees: Double? = nil,
        halfWidthMeters: Double = 25,
        headingToleranceDegrees: Double = 60,
        ignoreFirstCrossings: Int = 0
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.headingDegrees = headingDegrees
        self.halfWidthMeters = halfWidthMeters
        self.headingToleranceDegrees = headingToleranceDegrees
        self.ignoreFirstCrossings = ignoreFirstCrossings
    }
}

public struct DataInputSettings: Hashable, Codable, Sendable {
    /// Importer id to force (e.g. `racechrono-csv`); `nil` auto-detects.
    public var importerID: String?
    /// Column name → channel role identifier (e.g. `"Coolant": "obd:Coolant"`, `"KPH": "speed"`).
    public var roleOverrides: [String: String]
    /// Column name → unit text (`km/h`, `mph`, `ft`, …) when the file's unit is missing or wrong.
    public var unitOverrides: [String: String]
    public var deriveSpeedFromPosition: Bool
    public var deriveHeadingFromPosition: Bool
    /// Resample linear channels to this rate (Hz); `nil` keeps the recorded rate.
    public var resampleHertz: Double?
    /// Moving-average window in seconds (0 = off).
    public var smoothingSeconds: Double
    public var calculatedFields: [CalculatedFieldSpec]
    /// When set, laps come from crossings of this line instead of the file's lap markers.
    public var lapLine: LapLineSpec?

    public init(
        importerID: String? = nil,
        roleOverrides: [String: String] = [:],
        unitOverrides: [String: String] = [:],
        deriveSpeedFromPosition: Bool = true,
        deriveHeadingFromPosition: Bool = true,
        resampleHertz: Double? = nil,
        smoothingSeconds: Double = 0,
        calculatedFields: [CalculatedFieldSpec] = [],
        lapLine: LapLineSpec? = nil
    ) {
        self.importerID = importerID
        self.roleOverrides = roleOverrides
        self.unitOverrides = unitOverrides
        self.deriveSpeedFromPosition = deriveSpeedFromPosition
        self.deriveHeadingFromPosition = deriveHeadingFromPosition
        self.resampleHertz = resampleHertz
        self.smoothingSeconds = smoothingSeconds
        self.calculatedFields = calculatedFields
        self.lapLine = lapLine
    }

    private enum CodingKeys: String, CodingKey {
        case importerID, roleOverrides, unitOverrides, deriveSpeedFromPosition, deriveHeadingFromPosition
        case resampleHertz, smoothingSeconds, calculatedFields, lapLine
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        importerID = try c.decodeIfPresent(String.self, forKey: .importerID)
        roleOverrides = try c.decodeIfPresent([String: String].self, forKey: .roleOverrides) ?? [:]
        unitOverrides = try c.decodeIfPresent([String: String].self, forKey: .unitOverrides) ?? [:]
        deriveSpeedFromPosition = try c.decodeIfPresent(Bool.self, forKey: .deriveSpeedFromPosition) ?? true
        deriveHeadingFromPosition = try c.decodeIfPresent(Bool.self, forKey: .deriveHeadingFromPosition) ?? true
        resampleHertz = try c.decodeIfPresent(Double.self, forKey: .resampleHertz)
        smoothingSeconds = try c.decodeIfPresent(Double.self, forKey: .smoothingSeconds) ?? 0
        calculatedFields = try c.decodeIfPresent([CalculatedFieldSpec].self, forKey: .calculatedFields) ?? []
        lapLine = try c.decodeIfPresent(LapLineSpec.self, forKey: .lapLine)
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
