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

    /// The crop that results from applying `self` and then `inner` to what remains.
    public func composed(with inner: CropInsets) -> CropInsets {
        let width = max(0, 1 - left - right)
        let height = max(0, 1 - top - bottom)
        return CropInsets(
            top: top + height * inner.top, left: left + width * inner.left, bottom: bottom + height * inner.bottom,
            right: right + width * inner.right)
    }
}

/// A picture window shared by every video in the project (zoom and pan into the frame plus an
/// outer crop), so clips from one camera stay framed identically and can be reframed together.
public struct CameraFraming: Hashable, Codable, Sendable {
    /// 1 = the whole picture; 2 shows the central half of each axis.
    public var zoom: Double
    /// Centre of the zoom window as fractions of the picture (0.5, 0.5 = middle).
    public var centerX: Double
    public var centerY: Double
    /// Removed from every edge before zooming.
    public var crop: CropInsets

    public init(zoom: Double = 1, centerX: Double = 0.5, centerY: Double = 0.5, crop: CropInsets = .none) {
        self.zoom = zoom
        self.centerX = centerX
        self.centerY = centerY
        self.crop = crop
    }

    public static let none = CameraFraming()
    public var isIdentity: Bool { self == .none }

    /// The zoom window as a crop: a 1/zoom-sized box around the centre, kept inside the picture.
    public var zoomCrop: CropInsets {
        let z = min(max(zoom.isFinite ? zoom : 1, 1), 8)
        let size = 1 / z
        let x = min(max(centerX - size / 2, 0), 1 - size)
        let y = min(max(centerY - size / 2, 0), 1 - size)
        return CropInsets(top: y, left: x, bottom: 1 - y - size, right: 1 - x - size)
    }

    /// The whole framing as one crop applied on top of `inner` (an input's own crop).
    public func effectiveCrop(over inner: CropInsets) -> CropInsets {
        inner.composed(with: crop).composed(with: zoomCrop)
    }
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

/// Steadying a shaky picture (#262): each frame moved so the camera seems to follow a smooth path.
public struct StabilisationSettings: Hashable, Codable, Sendable {
    public enum Method: String, Codable, Sendable, CaseIterable {
        /// The picture as recorded.
        case off
        /// From the orientation the camera recorded alongside the picture (GoPro HERO8 and later).
        case motionData
        /// A copy of the picture stabilised by Gyroflow (#263), a separate app the user installs,
        /// shown in place of the recording's picture. Everything else still comes from the recording.
        case gyroflow
        /// From the picture's own movement, measured frame to frame (#264): for cameras that record no
        /// motion data. Weaker than motion data — blur, low light and a picture with little in it
        /// defeat it, and it cannot tell turning from moving sideways — but it needs nothing else.
        case picture

        public var displayName: String {
            switch self {
            case .off: "Off"
            case .motionData: "From camera motion data"
            case .gyroflow: "With Gyroflow"
            case .picture: "From the picture"
            }
        }
    }

    public var method: Method
    /// Seconds the smoothed path takes to follow the camera: short keeps more of the movement,
    /// long floats. The time constant of the smoothing.
    public var smoothing: Double
    /// How far the picture is enlarged so the frames' moved edges stay out of view; also the most a
    /// frame can be moved.
    public var zoom: Double
    /// With Gyroflow: the stabilised copy of each file of the video, in order — the first file, then
    /// each chapter. Empty until they have been made. Only the picture is taken from them: telemetry,
    /// clocks and chapters still come from the recording, and the timing is identical, so the
    /// project's sync is unchanged.
    public var gyroflowFiles: [MediaReference]

    public init(
        method: Method = .off, smoothing: Double = 0.5, zoom: Double = 1.15, gyroflowFiles: [MediaReference] = []
    ) {
        self.method = method
        self.smoothing = smoothing
        self.zoom = zoom
        self.gyroflowFiles = gyroflowFiles
    }

    private enum CodingKeys: String, CodingKey { case method, smoothing, zoom, gyroflowFiles }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StabilisationSettings()
        method = try c.decodeIfPresent(Method.self, forKey: .method) ?? d.method
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? d.smoothing
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? d.zoom
        gyroflowFiles = try c.decodeIfPresent([MediaReference].self, forKey: .gyroflowFiles) ?? []
    }

    public static let off = StabilisationSettings()
    public var isActive: Bool { method != .off }
    public static let smoothingRange = 0.1...3.0
    public static let zoomRange = 1.0...1.5

    /// The largest move of a frame, in picture heights, that the zoom still hides.
    public var maxShift: Double { max(zoom - 1, 0) / (2 * zoom) }
}
