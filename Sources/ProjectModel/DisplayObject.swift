/// Which unit a speed-like value is shown in.
public enum SpeedDisplayUnit: String, Codable, Sendable, CaseIterable {
    case mph
    case kph
    case metersPerSecond = "m/s"

    /// Multiplier from the canonical m/s.
    public var factorFromMetersPerSecond: Double {
        switch self {
        case .mph: 2.236_936_29
        case .kph: 3.6
        case .metersPerSecond: 1
        }
    }
}

public struct VideoObjectParams: Hashable, Codable, Sendable {
    public var mirror: Mirror
    public var channelMask: RGBMask

    public init(mirror: Mirror = .none, channelMask: RGBMask = .all) {
        self.mirror = mirror
        self.channelMask = channelMask
    }

    private enum CodingKeys: String, CodingKey {
        case mirror, channelMask
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mirror = try c.decodeIfPresent(Mirror.self, forKey: .mirror) ?? .none
        channelMask = try c.decodeIfPresent(RGBMask.self, forKey: .channelMask) ?? .all
    }
}

public enum ShapeKind: String, Codable, Sendable, CaseIterable {
    case rectangle
    case roundedRectangle
    case ellipse
}

public struct ShapeParams: Hashable, Codable, Sendable {
    public var shape: ShapeKind
    /// The fill, or the start of the gradient (top or left) when `gradientEndColor` is set.
    public var fillColor: RGBAColor
    /// The colour at the bottom (or right) edge; `nil` = a plain fill. A clear start fading to a
    /// dark end makes the band track-day apps put behind their gauges.
    public var gradientEndColor: RGBAColor?
    /// Left to right instead of top to bottom.
    public var gradientHorizontal: Bool
    public var strokeColor: RGBAColor
    /// Stroke width as a fraction of the output height (0 = none).
    public var strokeWidth: Double
    /// Corner radius as a fraction of the shorter object side (rounded rectangles only).
    public var cornerRadius: Double

    public init(
        shape: ShapeKind = .roundedRectangle,
        fillColor: RGBAColor = .translucentBlack,
        strokeColor: RGBAColor = .white,
        strokeWidth: Double = 0,
        cornerRadius: Double = 0.15,
        gradientEndColor: RGBAColor? = nil,
        gradientHorizontal: Bool = false
    ) {
        self.shape = shape
        self.fillColor = fillColor
        self.gradientEndColor = gradientEndColor
        self.gradientHorizontal = gradientHorizontal
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
    }

    private enum CodingKeys: String, CodingKey {
        case shape, fillColor, strokeColor, strokeWidth, cornerRadius, gradientEndColor, gradientHorizontal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShapeParams()
        shape = try c.decodeIfPresent(ShapeKind.self, forKey: .shape) ?? d.shape
        fillColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fillColor) ?? d.fillColor
        strokeColor = try c.decodeIfPresent(RGBAColor.self, forKey: .strokeColor) ?? d.strokeColor
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? d.strokeWidth
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        gradientEndColor = try c.decodeIfPresent(RGBAColor.self, forKey: .gradientEndColor)
        gradientHorizontal = try c.decodeIfPresent(Bool.self, forKey: .gradientHorizontal) ?? false
    }
}

public struct TextParams: Hashable, Codable, Sendable {
    public var text: String
    /// Font size as a fraction of the object's height (0…1).
    public var fontScale: Double
    public var fontName: String
    public var bold: Bool
    public var color: RGBAColor
    public var backgroundColor: RGBAColor
    public var alignment: TextAlignment
    /// Outline width as a fraction of the font size (0 = none).
    public var outlineWidth: Double
    public var outlineColor: RGBAColor

    public init(
        text: String = "Title",
        fontScale: Double = 0.6,
        fontName: String = "Helvetica Neue",
        bold: Bool = true,
        color: RGBAColor = .white,
        backgroundColor: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0),
        alignment: TextAlignment = .center,
        outlineWidth: Double = 0,
        outlineColor: RGBAColor = .black
    ) {
        self.text = text
        self.fontScale = fontScale
        self.fontName = fontName
        self.bold = bold
        self.color = color
        self.backgroundColor = backgroundColor
        self.alignment = alignment
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
    }
}

/// An embedded still image whose rotation, opacity and visibility can follow data channels.
public struct ImageObjectParams: Hashable, Codable, Sendable {
    /// Channel role identifier driving rotation, or `nil` for a static image.
    public var rotationChannel: String?
    /// Degrees of rotation per unit of the channel value (e.g. 1 for a heading channel).
    public var degreesPerUnit: Double
    /// Static rotation in degrees added to any channel-driven rotation.
    public var rotation: Double
    /// Channel whose value (0…1 after scaling) drives opacity, or `nil`.
    public var opacityChannel: String?
    public var opacityScale: Double
    /// Channel that makes the image flash when above `flashThreshold`, or `nil`.
    public var flashChannel: String?
    public var flashThreshold: Double
    public var flashHertz: Double
    public var keepAspect: Bool

    public init(
        rotationChannel: String? = nil,
        degreesPerUnit: Double = 1,
        rotation: Double = 0,
        opacityChannel: String? = nil,
        opacityScale: Double = 1,
        flashChannel: String? = nil,
        flashThreshold: Double = 0,
        flashHertz: Double = 3,
        keepAspect: Bool = true
    ) {
        self.rotationChannel = rotationChannel
        self.degreesPerUnit = degreesPerUnit
        self.rotation = rotation
        self.opacityChannel = opacityChannel
        self.opacityScale = opacityScale
        self.flashChannel = flashChannel
        self.flashThreshold = flashThreshold
        self.flashHertz = flashHertz
        self.keepAspect = keepAspect
    }
}

/// The type-specific part of a display object.
public enum DisplayObjectKind: Hashable, Codable, Sendable {
    case video(VideoObjectParams)
    case speedometer(GaugeParams)
    case tachometer(GaugeParams)
    case gauge(GaugeParams)
    case trackMap(TrackMapParams)
    case gForce(GForceParams)
    case timer(TimerParams)
    case textData(TextDataParams)
    case shape(ShapeParams)
    case text(TextParams)
    case image(ImageObjectParams)
    case bar(BarParams)
    case graph(GraphParams)
    case gear(GearParams)
    case lapCounter(LapCounterParams)
    case scripted(ScriptedParams)
    case indicator(IndicatorParams)
    case lapPanel(LapPanelParams)
    case sectorPanel(SectorPanelParams)
    case steeringWheel(SteeringWheelParams)

    public var typeName: String {
        switch self {
        case .video: "Video"
        case .speedometer: "Speedometer"
        case .tachometer: "Tachometer"
        case .gauge: "Gauge"
        case .trackMap: "Track Map"
        case .gForce: "G-Force"
        case .timer: "Timer"
        case .textData: "Text Data"
        case .shape: "Shape"
        case .text: "Text"
        case .image: "Image"
        case .bar: "Bar"
        case .graph: "Graph"
        case .gear: "Gear"
        case .lapCounter: "Lap Counter"
        case .scripted: "Script"
        case .indicator: "Indicator"
        case .lapPanel: "Timing Panel"
        case .sectorPanel: "Sector Times"
        case .steeringWheel: "Steering Wheel"
        }
    }

    /// Objects fed by a telemetry input.
    public var needsData: Bool {
        switch self {
        case .video, .shape, .text, .image: false
        default: true
        }
    }

    /// The gauge parameters for the three round-gauge kinds.
    public var gaugeParams: GaugeParams? {
        switch self {
        case .speedometer(let p), .tachometer(let p), .gauge(let p): p
        default: nil
        }
    }

    /// What this object's own speed-unit setting says, or `automatic` for a kind that has none
    /// to say it with. The five kinds that draw a speed are the five that carry the setting.
    public var speedUnit: SpeedUnitSetting {
        switch self {
        case .speedometer(let p), .tachometer(let p), .gauge(let p): p.speedUnit
        case .bar(let p): p.speedUnit
        case .graph(let p): p.speedUnit
        case .textData(let p): p.speedUnit
        case .lapPanel(let p): p.speedUnit
        default: .automatic
        }
    }

    /// The channels this object draws a *value* of, and so the ones an object-level display unit
    /// applies to. A light and a steering wheel read a channel too, but they draw a lamp and an
    /// angle rather than a number in a unit, so neither has a unit to choose.
    public var displayChannels: [String] {
        switch self {
        case .speedometer(let p), .tachometer(let p), .gauge(let p): [p.channel]
        case .bar(let p): [p.channel]
        case .textData(let p): [p.channel]
        case .graph(let p): p.series.map(\.channel)
        // The timing panel has no channel to name: it always draws speed and the delta from it.
        case .lapPanel: ["speed", "speedDelta"]
        default: []
        }
    }

    /// Objects that draw text, and so the ones a font can be chosen for (#118). A script chooses
    /// its own fonts in its code, so it is not one of them.
    public var drawsText: Bool {
        switch self {
        case .video, .shape, .image, .scripted, .steeringWheel: false
        default: true
        }
    }

    /// Objects whose params already size their text, so a second size control would compete with
    /// the first.
    public var sizesOwnText: Bool {
        switch self {
        case .text, .textData, .gear: true
        default: false
        }
    }

    /// Objects fed by an image input.
    public var needsImage: Bool {
        if case .image = self { return true }
        return false
    }

    /// Objects drawn by the overlay renderer (everything except video layers).
    public var isOverlay: Bool {
        if case .video = self { return false }
        return true
    }
}

/// Something drawn on the output frame: a video layer or a data visualisation.
public struct DisplayObject: Identifiable, Hashable, Codable, Sendable {
    public var id: DisplayObjectID
    public var label: String
    /// The input feeding this object (a video for `.video`, a data file for everything else).
    public var inputID: InputID?
    public var frame: UnitRect
    public var opacity: Double
    public var isVisible: Bool
    public var kind: DisplayObjectKind
    /// The unit this object draws its channel in, whatever the levels above it chose (#89).
    /// `nil` follows the attribute's display unit, and through it the unit the data is read in.
    ///
    /// One field on the object rather than one per params struct, because it says something about
    /// how the object presents its channel rather than about what kind of object it is — and
    /// because a temperature gauge wants it just as much as a speedometer does. Speed keeps its
    /// own `speedUnit` on the params: #75 shipped that, projects are saved with it, and it spells
    /// km/h `kph` where this would spell it `km/h`.
    ///
    /// Text, for the same reason `AttributeMapping`'s units are: `ProjectModel` holds the document
    /// schema and does not depend on `TelemetryKit`.
    public var displayUnit: String?
    /// The font every piece of this object's text is drawn in (#118). `nil` follows the project's
    /// font, and without one the object's built-in fonts — so a project saved before fonts could
    /// be chosen draws exactly as it did.
    public var typeface: Typeface?
    /// This object's text drawn larger or smaller than it lays it out, as a multiple (#118):
    /// `nil` is 1. Objects whose params already size their text (Text, Text Data, Gear) keep
    /// their own size controls; this scales on top of them.
    public var textScale: Double?

    public init(
        id: DisplayObjectID = DisplayObjectID(),
        label: String,
        inputID: InputID?,
        frame: UnitRect,
        opacity: Double = 1,
        isVisible: Bool = true,
        kind: DisplayObjectKind,
        displayUnit: String? = nil,
        typeface: Typeface? = nil,
        textScale: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.inputID = inputID
        self.frame = frame
        self.opacity = opacity
        self.isVisible = isVisible
        self.kind = kind
        self.displayUnit = displayUnit
        self.typeface = typeface
        self.textScale = textScale
    }
}
