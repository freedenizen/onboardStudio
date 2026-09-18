/// Fractions (0…0.5) of the picture removed from each edge before placement.
public struct CropInsets: Hashable, Codable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let none = CropInsets()
    public var isEmpty: Bool { top == 0 && left == 0 && bottom == 0 && right == 0 }
}

/// Picture adjustments. 1 (or 0 for hue) means "unchanged".
public struct ColorAdjustments: Hashable, Codable, Sendable {
    /// 0…2, 1 = unchanged.
    public var brightness: Double
    /// 0…2, 1 = unchanged.
    public var contrast: Double
    /// 0…2, 1 = unchanged (0 = greyscale).
    public var saturation: Double
    /// Degrees, −180…180, 0 = unchanged.
    public var hue: Double
    /// 0…2, 1 = unchanged (>1 sharpens, <1 softens).
    public var sharpness: Double

    public init(
        brightness: Double = 1, contrast: Double = 1, saturation: Double = 1, hue: Double = 0, sharpness: Double = 1
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
        self.sharpness = sharpness
    }

    public static let neutral = ColorAdjustments()
    public var isNeutral: Bool { self == .neutral }
}

/// Makes a colour (and colours near it) transparent.
public struct ChromaKey: Hashable, Codable, Sendable {
    public var color: RGBAColor
    /// 0…1: how far (in hue/saturation/value distance) from `color` still counts as key.
    public var tolerance: Double
    /// 0…1: width of the soft edge beyond `tolerance`.
    public var softness: Double

    public init(
        color: RGBAColor = RGBAColor(red: 0, green: 1, blue: 0), tolerance: Double = 0.3, softness: Double = 0.1
    ) {
        self.color = color
        self.tolerance = tolerance
        self.softness = softness
    }
}

public struct Mirror: Hashable, Codable, Sendable {
    public var horizontal: Bool
    public var vertical: Bool

    public init(horizontal: Bool = false, vertical: Bool = false) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let none = Mirror()
}

/// Which colour channels are drawn.
public struct RGBMask: Hashable, Codable, Sendable {
    public var red: Bool
    public var green: Bool
    public var blue: Bool

    public init(red: Bool = true, green: Bool = true, blue: Bool = true) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let all = RGBMask()
    public var isAll: Bool { red && green && blue }
}

public enum AudioChannelSelection: String, Codable, Sendable, CaseIterable {
    case stereo
    case mono
    case left
    case right
}

public struct AudioSettings: Hashable, Codable, Sendable {
    /// 0…2, 1 = unchanged.
    public var volume: Double
    /// −1 (left) … 1 (right), 0 = centre.
    public var balance: Double
    public var channels: AudioChannelSelection
    public var isMuted: Bool

    public init(
        volume: Double = 1, balance: Double = 0, channels: AudioChannelSelection = .stereo, isMuted: Bool = false
    ) {
        self.volume = volume
        self.balance = balance
        self.channels = channels
        self.isMuted = isMuted
    }

    public static let neutral = AudioSettings()
    public var isNeutral: Bool { self == .neutral }
    /// Effective gain applied to the track.
    public var effectiveVolume: Double { isMuted ? 0 : volume }
}

/// How a wide-angle or 360° source is mapped to a flat (rectilinear) picture.
public enum LensMode: String, Codable, Sendable, CaseIterable {
    /// Use the picture as recorded.
    case none
    /// Equidistant fisheye with the optical axis at the picture centre and `fov` across its width.
    case fisheye
    /// A 360° equirectangular (2:1) panorama.
    case equirectangular

    public var displayName: String {
        switch self {
        case .none: "Off"
        case .fisheye: "Fisheye"
        case .equirectangular: "360° (equirectangular)"
        }
    }
}

/// Lens unwrap settings for a video input: a virtual rectilinear camera looking into the source.
public struct LensSettings: Hashable, Codable, Sendable {
    public var mode: LensMode
    /// Horizontal field of view of a fisheye source in degrees (ignored for 360° sources).
    public var fov: Double
    /// Horizontal field of view of the unwrapped picture in degrees.
    public var outputFov: Double
    /// Camera direction in degrees: yaw turns right, pitch looks up, roll tilts clockwise.
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(
        mode: LensMode = .none, fov: Double = 180, outputFov: Double = 90, yaw: Double = 0, pitch: Double = 0,
        roll: Double = 0
    ) {
        self.mode = mode
        self.fov = fov
        self.outputFov = outputFov
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public static let none = LensSettings()
    public var isActive: Bool { mode != .none }
}
