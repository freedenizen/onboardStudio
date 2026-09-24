import Foundation

/// What sits behind the overlays in the output.
public enum ExportBackground: Hashable, Codable, Sendable {
    /// The project's video layers (normal output).
    case video
    /// No video: a flat key colour behind the overlays, for chroma-keying in another editor.
    case keyColor(RGBAColor)
    /// No video: transparent pixels behind the overlays; needs a codec with an alpha channel.
    case transparent

    public var isOverlayOnly: Bool {
        if case .video = self { return false }
        return true
    }
}

/// Which part of the project to export.
public enum ExportRange: Hashable, Codable, Sendable {
    case whole
    /// Project seconds.
    case span(start: Double, end: Double)
    /// Inclusive lap numbers of the first data input, mapped to project time through its sync.
    case laps(first: Int, last: Int)
    /// One file per lap of the first data input (#150). `completeOnly` leaves out the laps whose
    /// start or end was not at the line — the out-lap and the in-lap; `slowerThanBest`, when set,
    /// leaves out laps slower than the best complete lap by more than that fraction (0.1 = 10 %).
    case eachLap(completeOnly: Bool, slowerThanBest: Double?)
}

/// Output video encoding settings.
public struct ExportSettings: Hashable, Codable, Sendable {
    public enum VideoCodec: String, Codable, Sendable, CaseIterable {
        case h264
        case hevc
        /// HEVC with an alpha channel (QuickTime container).
        case hevcAlpha
        /// Apple ProRes 4444 with alpha (QuickTime container, large files, editing-friendly).
        case proRes4444

        public var supportsAlpha: Bool { self == .hevcAlpha || self == .proRes4444 }
        /// Whether the encoder takes a target bitrate (ProRes is constant quality).
        public var usesBitrate: Bool { self != .proRes4444 }
        public var fileExtension: String { self == .h264 || self == .hevc ? "mp4" : "mov" }
        public var displayName: String {
            switch self {
            case .h264: "H.264"
            case .hevc: "HEVC (H.265)"
            case .hevcAlpha: "HEVC with alpha"
            case .proRes4444: "ProRes 4444 (alpha)"
            }
        }
    }

    public var codec: VideoCodec
    public var width: Int
    public var height: Int
    public var frameRate: Double
    /// Average video bitrate in bits per second.
    public var videoBitrate: Int
    /// AAC audio bitrate in bits per second. `nil` disables audio.
    public var audioBitrate: Int?
    public var audioSampleRate: Double
    public var audioChannels: Int
    public var background: ExportBackground
    public var range: ExportRange
    /// Tag the output as a 360° equirectangular video (Google spherical metadata) so players and
    /// YouTube show it as a panorama. Only meaningful when the picture is a full equirectangular frame.
    public var spherical: Bool

    public init(
        codec: VideoCodec = .h264,
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Double = 30,
        videoBitrate: Int = 16_000_000,
        audioBitrate: Int? = 192_000,
        audioSampleRate: Double = 48000,
        audioChannels: Int = 2,
        background: ExportBackground = .video,
        range: ExportRange = .whole,
        spherical: Bool = false
    ) {
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.videoBitrate = videoBitrate
        self.audioBitrate = audioBitrate
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.background = background
        self.range = range
        self.spherical = spherical
    }

    private enum CodingKeys: String, CodingKey {
        case codec, width, height, frameRate, videoBitrate, audioBitrate, audioSampleRate, audioChannels
        case background, range, spherical
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportSettings()
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? d.codec
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? d.width
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? d.height
        frameRate = try c.decodeIfPresent(Double.self, forKey: .frameRate) ?? d.frameRate
        videoBitrate = try c.decodeIfPresent(Int.self, forKey: .videoBitrate) ?? d.videoBitrate
        audioBitrate = try c.decodeIfPresent(Int.self, forKey: .audioBitrate)
        audioSampleRate = try c.decodeIfPresent(Double.self, forKey: .audioSampleRate) ?? d.audioSampleRate
        audioChannels = try c.decodeIfPresent(Int.self, forKey: .audioChannels) ?? d.audioChannels
        background = try c.decodeIfPresent(ExportBackground.self, forKey: .background) ?? .video
        range = try c.decodeIfPresent(ExportRange.self, forKey: .range) ?? .whole
        spherical = try c.decodeIfPresent(Bool.self, forKey: .spherical) ?? false
    }

    /// The file extension the container needs.
    public var fileExtension: String { codec.fileExtension }

    /// A transparent background only works with an alpha codec; returns settings that agree.
    public var reconciled: ExportSettings {
        var s = self
        if case .transparent = s.background, !s.codec.supportsAlpha { s.codec = .proRes4444 }
        return s
    }

    public static let hd1080 = ExportSettings()
    public static let hd720 = ExportSettings(width: 1280, height: 720, videoBitrate: 8_000_000)
    public static let qhd1440 = ExportSettings(codec: .hevc, width: 2560, height: 1440, videoBitrate: 24_000_000)
    public static let uhd4k = ExportSettings(codec: .hevc, width: 3840, height: 2160, videoBitrate: 45_000_000)
    public static let vertical1080 = ExportSettings(width: 1080, height: 1920, videoBitrate: 12_000_000)
    public static let overlayAlpha = ExportSettings(
        codec: .proRes4444, audioBitrate: nil, background: .transparent)
    public static let overlayKeyed = ExportSettings(
        audioBitrate: nil, background: .keyColor(RGBAColor(red: 0, green: 0, blue: 1)))

    /// Presets keyed by a short name usable from the CLI.
    public static let presets: [String: ExportSettings] = [
        "720p": .hd720, "1080p": .hd1080, "1440p": .qhd1440, "4k": .uhd4k, "vertical": .vertical1080,
        "overlay-alpha": .overlayAlpha, "overlay-key": .overlayKeyed,
    ]

    /// A preset with a menu name and its CLI key.
    public struct Preset: Hashable, Sendable, Identifiable {
        public let name: String
        public let key: String
        public let settings: ExportSettings
        public var id: String { key }
    }

    /// Presets in menu order with display names.
    public static let namedPresets: [Preset] = [
        Preset(name: "1280 × 720 · H.264", key: "720p", settings: .hd720),
        Preset(name: "1920 × 1080 · H.264", key: "1080p", settings: .hd1080),
        Preset(name: "2560 × 1440 · HEVC", key: "1440p", settings: .qhd1440),
        Preset(name: "3840 × 2160 · HEVC", key: "4k", settings: .uhd4k),
        Preset(name: "1080 × 1920 vertical · H.264", key: "vertical", settings: .vertical1080),
        Preset(name: "Overlay only · transparent ProRes 4444", key: "overlay-alpha", settings: .overlayAlpha),
        Preset(name: "Overlay only · blue key · H.264", key: "overlay-key", settings: .overlayKeyed),
    ]
}
