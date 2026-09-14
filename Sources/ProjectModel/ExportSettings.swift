/// Output video encoding settings.
public struct ExportSettings: Hashable, Codable, Sendable {
    public enum VideoCodec: String, Codable, Sendable, CaseIterable {
        case h264
        case hevc
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

    public init(
        codec: VideoCodec = .h264,
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Double = 30,
        videoBitrate: Int = 16_000_000,
        audioBitrate: Int? = 192_000,
        audioSampleRate: Double = 48000,
        audioChannels: Int = 2
    ) {
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.videoBitrate = videoBitrate
        self.audioBitrate = audioBitrate
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
    }

    public static let hd1080 = ExportSettings()
    public static let hd720 = ExportSettings(width: 1280, height: 720, videoBitrate: 8_000_000)
    public static let uhd4k = ExportSettings(codec: .hevc, width: 3840, height: 2160, videoBitrate: 45_000_000)

    /// Presets keyed by a short name usable from the CLI.
    public static let presets: [String: ExportSettings] = ["1080p": .hd1080, "720p": .hd720, "4k": .uhd4k]
}
