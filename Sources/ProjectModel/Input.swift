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

/// One file of a clip sequence: where it comes from, which part of it plays, and how much
/// (black) gap precedes it.
public struct VideoClip: Hashable, Codable, Sendable {
    public var source: MediaReference
    /// Seconds inside this file; `nil` ends mean the whole file.
    public var trim: TrimRange
    /// Seconds of black before the clip starts (0 = back to back with the previous one).
    public var gapBefore: Double
    /// Playback speed of this clip alone (1 = as recorded; 2 = twice as fast), multiplied with
    /// the input's own play speed.
    public var speed: Double

    public init(source: MediaReference, trim: TrimRange = .none, gapBefore: Double = 0, speed: Double = 1) {
        self.source = source
        self.trim = trim
        self.gapBefore = gapBefore
        self.speed = speed
    }

    /// Seconds this clip occupies on the sequence axis when its file plays `played` seconds.
    public func sequenceDuration(played: Double) -> Double { max(0, played) / max(speed, 0.01) }

    private enum CodingKeys: String, CodingKey {
        case source, trim, gapBefore, speed
    }

    /// Accepts both the M15 form (`{ "path": … }`) and the full form.
    public init(from decoder: any Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.source) {
            source = try c.decode(MediaReference.self, forKey: .source)
            trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim) ?? .none
            gapBefore = try c.decodeIfPresent(Double.self, forKey: .gapBefore) ?? 0
            speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        } else {
            source = try MediaReference(from: decoder)
            trim = .none
            gapBefore = 0
            speed = 1
        }
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
    /// chapters); trim, sync and picture settings apply to the whole sequence. Each clip can be
    /// trimmed on its own and preceded by a gap.
    public var clips: [VideoClip]
    /// Steadying the picture (#262). Absent in files saved before it, which is off: as recorded.
    public var stabilisation: StabilisationSettings

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
        clips: [VideoClip] = [],
        stabilisation: StabilisationSettings = .off
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
        self.stabilisation = stabilisation
    }

    // Older documents lack the picture/audio fields; decode them as neutral.
    private enum CodingKeys: String, CodingKey {
        case trim, includeAudio, rotation, mirror, crop, color, chromaKey, audio, lens, clips, stabilisation
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
        clips = try c.decodeIfPresent([VideoClip].self, forKey: .clips) ?? []
        stabilisation = try c.decodeIfPresent(StabilisationSettings.self, forKey: .stabilisation) ?? .off
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

/// How this data file's laps are divided into sectors.
///
/// Sector geometry cannot be fetched — no open source publishes it under a usable licence and no
/// logger format surveyed carries it (`docs/tracks-and-sectors.md`) — so it is derived from the
/// driving or drawn here.
public struct SectorSpec: Hashable, Codable, Sendable {
    public enum Mode: String, Hashable, Codable, Sendable, CaseIterable {
        /// Equal parts of the reference lap's distance.
        case equalDistance
        /// Equal parts, with each boundary moved onto the nearest straight.
        case cornerAware
        /// The gate lines in `lines`.
        case manual

        public var displayName: String {
            switch self {
            case .equalDistance: "Equal distances"
            case .cornerAware: "On the straights"
            case .manual: "Gates I place"
            }
        }
    }

    public var mode: Mode
    /// Sectors per lap for `equalDistance` and `cornerAware`. Three is the convention.
    public var count: Int
    /// Gate lines for `manual`, in the order the track runs them.
    public var lines: [LapLineSpec]

    public init(mode: Mode = .equalDistance, count: Int = 3, lines: [LapLineSpec] = []) {
        self.mode = mode
        self.count = count
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey { case mode, count, lines }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .equalDistance
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 3
        lines = try c.decodeIfPresent([LapLineSpec].self, forKey: .lines) ?? []
    }
}

extension Input {
    /// This input's data settings, or `nil` when it is not a data input.
    public var dataSettings: DataInputSettings? {
        if case .data(let settings) = kind { return settings }
        return nil
    }
}

public struct DataInputSettings: Hashable, Codable, Sendable {
    /// Importer id to force (e.g. `racechrono-csv`); `nil` auto-detects.
    public var importerID: String?
    /// Column name → channel role identifier (e.g. `"Coolant": "obd:Coolant"`, `"KPH": "speed"`).
    public var roleOverrides: [String: String]
    /// Column name → unit text (`km/h`, `mph`, `ft`, …) when the file's unit is missing or wrong.
    public var unitOverrides: [String: String]
    /// This input's deviations from the project's attribute mapping (#111) — the bottom level of
    /// the chain, for when one file is the exception. Attribute-keyed, where `roleOverrides` and
    /// `unitOverrides` above are column-keyed; both are applied, and this one wins.
    public var attributeMappings: AttributeMappingTable
    public var deriveSpeedFromPosition: Bool
    public var deriveHeadingFromPosition: Bool
    /// Resample linear channels to this rate (Hz); `nil` keeps the recorded rate.
    public var resampleHertz: Double?
    /// Moving-average window in seconds (0 = off).
    public var smoothingSeconds: Double
    public var calculatedFields: [CalculatedFieldSpec]
    /// When set, laps come from crossings of this line instead of the file's lap markers.
    public var lapLine: LapLineSpec?
    /// How each lap is divided for sector times.
    public var sectors: SectorSpec
    /// The circuit this file was recorded at, as a Wikidata id (`Q112563`) or a track-definition
    /// key. Set when the file is added and correctable; `nil` means nothing has been decided.
    public var circuitID: String?
    /// What this circuit calls its corners, in driving order from the start/finish, one per
    /// corner the detector finds. Strings, because circuits number 3, 3a, 4, 4a. Empty leaves
    /// the map counting them instead.
    public var cornerLabels: [String]
    /// Seconds of the data file to keep, in its own time. Applied before laps are detected, so a
    /// trimmed-away out-lap is not counted and does not compete for the best lap.
    public var trim: TrimRange

    public init(
        importerID: String? = nil,
        roleOverrides: [String: String] = [:],
        unitOverrides: [String: String] = [:],
        attributeMappings: AttributeMappingTable = AttributeMappingTable(),
        deriveSpeedFromPosition: Bool = true,
        deriveHeadingFromPosition: Bool = true,
        resampleHertz: Double? = nil,
        smoothingSeconds: Double = 0,
        calculatedFields: [CalculatedFieldSpec] = [],
        lapLine: LapLineSpec? = nil,
        sectors: SectorSpec = SectorSpec(),
        circuitID: String? = nil,
        cornerLabels: [String] = [],
        trim: TrimRange = .none
    ) {
        self.importerID = importerID
        self.roleOverrides = roleOverrides
        self.unitOverrides = unitOverrides
        self.attributeMappings = attributeMappings
        self.deriveSpeedFromPosition = deriveSpeedFromPosition
        self.deriveHeadingFromPosition = deriveHeadingFromPosition
        self.resampleHertz = resampleHertz
        self.smoothingSeconds = smoothingSeconds
        self.calculatedFields = calculatedFields
        self.lapLine = lapLine
        self.sectors = sectors
        self.circuitID = circuitID
        self.cornerLabels = cornerLabels
        self.trim = trim
    }

    private enum CodingKeys: String, CodingKey {
        case importerID, roleOverrides, unitOverrides, attributeMappings
        case deriveSpeedFromPosition, deriveHeadingFromPosition
        case resampleHertz, smoothingSeconds, calculatedFields, lapLine, sectors, circuitID
        case cornerLabels, trim
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        importerID = try c.decodeIfPresent(String.self, forKey: .importerID)
        roleOverrides = try c.decodeIfPresent([String: String].self, forKey: .roleOverrides) ?? [:]
        unitOverrides = try c.decodeIfPresent([String: String].self, forKey: .unitOverrides) ?? [:]
        // Absent before the attribute table existed. An empty table is automatic on every field,
        // which is exactly what such a project did: only `roleOverrides` and `unitOverrides` spoke.
        attributeMappings =
            try c.decodeIfPresent(AttributeMappingTable.self, forKey: .attributeMappings) ?? AttributeMappingTable()
        deriveSpeedFromPosition = try c.decodeIfPresent(Bool.self, forKey: .deriveSpeedFromPosition) ?? true
        deriveHeadingFromPosition = try c.decodeIfPresent(Bool.self, forKey: .deriveHeadingFromPosition) ?? true
        resampleHertz = try c.decodeIfPresent(Double.self, forKey: .resampleHertz)
        smoothingSeconds = try c.decodeIfPresent(Double.self, forKey: .smoothingSeconds) ?? 0
        calculatedFields = try c.decodeIfPresent([CalculatedFieldSpec].self, forKey: .calculatedFields) ?? []
        lapLine = try c.decodeIfPresent(LapLineSpec.self, forKey: .lapLine)
        // Absent in projects saved before sectors existed. Nothing drew a sector time then, so
        // measuring them now cannot change how such a project renders.
        sectors = try c.decodeIfPresent(SectorSpec.self, forKey: .sectors) ?? SectorSpec()
        // Absent before circuits were identified. Left nil rather than worked out on open: a
        // saved project keeps the lap line and sectors it was saved with, whatever the circuit
        // library has learned since.
        circuitID = try c.decodeIfPresent(String.self, forKey: .circuitID)
        cornerLabels = try c.decodeIfPresent([String].self, forKey: .cornerLabels) ?? []
        // Absent in projects saved before data could be trimmed; no trim is the right reading.
        trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim) ?? .none
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
