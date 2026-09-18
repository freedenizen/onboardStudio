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
    public var fillColor: RGBAColor
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
        cornerRadius: Double = 0.15
    ) {
        self.shape = shape
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
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

/// A round gauge. Speedometer and tachometer are presets of this; the Gauge Designer edits
/// every field.
public struct GaugeParams: Hashable, Codable, Sendable {
    /// Channel role identifier, e.g. `speed`, `rpm`, `aux:Oil temp`.
    public var channel: String
    public var title: String
    public var minValue: Double
    public var maxValue: Double
    /// For speed channels, the unit shown; ignored otherwise.
    public var speedUnit: SpeedDisplayUnit
    /// Text appended to the value readout (e.g. `rpm`); for speed the unit name is used.
    public var unitLabel: String
    public var majorTick: Double
    public var minorTick: Double
    /// Total arc in degrees (up to 360).
    public var sweep: Double
    /// Rotation of the arc's centre in degrees, 0 = arc centred at the bottom gap (classic 270° gauge).
    public var rotation: Double
    /// Values increase anticlockwise instead of clockwise.
    public var counterClockwise: Bool
    public var style: GaugeStyle
    /// Channel shown by the second needle in `.dualNeedle` style.
    public var secondChannel: String
    public var secondNeedleColor: RGBAColor
    public var needle: NeedleStyle
    public var ticks: TickStyle
    /// Coloured value ranges (red zone, shift band…).
    public var zones: [GaugeZone]
    public var zoneTargets: ZoneTargets
    /// Width of the filled arc in `.arc` style as a fraction of the radius.
    public var arcWidth: Double
    public var arcTrackColor: RGBAColor
    /// Paint the round face (`faceColor`) behind the scale.
    public var showFace: Bool
    /// An image input drawn as the face (aspect-fitted into the gauge square), or `nil`.
    public var faceImageInputID: InputID?
    /// Divide the channel value by this before display (e.g. 1000 for "x1000 rpm").
    public var valueDivisor: Double
    public var showValue: Bool
    public var decimals: Int
    public var faceColor: RGBAColor
    public var needleColor: RGBAColor
    public var textColor: RGBAColor

    public init(
        channel: String,
        title: String,
        minValue: Double,
        maxValue: Double,
        speedUnit: SpeedDisplayUnit = .mph,
        unitLabel: String = "",
        majorTick: Double,
        minorTick: Double,
        sweep: Double = 270,
        rotation: Double = 0,
        counterClockwise: Bool = false,
        style: GaugeStyle = .needle,
        secondChannel: String = "",
        secondNeedleColor: RGBAColor = .white,
        needle: NeedleStyle = NeedleStyle(),
        ticks: TickStyle = TickStyle(),
        zones: [GaugeZone] = [],
        zoneTargets: ZoneTargets = ZoneTargets(),
        arcWidth: Double = 0.14,
        arcTrackColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.15),
        showFace: Bool = true,
        faceImageInputID: InputID? = nil,
        valueDivisor: Double = 1,
        showValue: Bool = true,
        decimals: Int = 0,
        faceColor: RGBAColor = .faceDark,
        needleColor: RGBAColor = .accent,
        textColor: RGBAColor = .white
    ) {
        self.channel = channel
        self.title = title
        self.minValue = minValue
        self.maxValue = maxValue
        self.speedUnit = speedUnit
        self.unitLabel = unitLabel
        self.majorTick = majorTick
        self.minorTick = minorTick
        self.sweep = sweep
        self.rotation = rotation
        self.counterClockwise = counterClockwise
        self.style = style
        self.secondChannel = secondChannel
        self.secondNeedleColor = secondNeedleColor
        self.needle = needle
        self.ticks = ticks
        self.zones = zones
        self.zoneTargets = zoneTargets
        self.arcWidth = arcWidth
        self.arcTrackColor = arcTrackColor
        self.showFace = showFace
        self.faceImageInputID = faceImageInputID
        self.valueDivisor = valueDivisor
        self.showValue = showValue
        self.decimals = decimals
        self.faceColor = faceColor
        self.needleColor = needleColor
        self.textColor = textColor
    }

    private enum CodingKeys: String, CodingKey {
        case channel, title, minValue, maxValue, speedUnit, unitLabel, majorTick, minorTick, sweep, rotation
        case counterClockwise, style, secondChannel, secondNeedleColor, needle, ticks, zones, zoneTargets
        case arcWidth, arcTrackColor, showFace, faceImageInputID, valueDivisor, showValue, decimals
        case faceColor, needleColor, textColor
        // Pre-0.5 files: a single red zone.
        case redlineFrom, redlineColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GaugeParams(channel: "", title: "", minValue: 0, maxValue: 1, majorTick: 1, minorTick: 1)
        channel = try c.decode(String.self, forKey: .channel)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        minValue = try c.decodeIfPresent(Double.self, forKey: .minValue) ?? 0
        maxValue = try c.decodeIfPresent(Double.self, forKey: .maxValue) ?? 100
        speedUnit = try c.decodeIfPresent(SpeedDisplayUnit.self, forKey: .speedUnit) ?? d.speedUnit
        unitLabel = try c.decodeIfPresent(String.self, forKey: .unitLabel) ?? d.unitLabel
        majorTick = try c.decodeIfPresent(Double.self, forKey: .majorTick) ?? (maxValue - minValue) / 5
        minorTick = try c.decodeIfPresent(Double.self, forKey: .minorTick) ?? majorTick / 2
        sweep = try c.decodeIfPresent(Double.self, forKey: .sweep) ?? d.sweep
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? d.rotation
        counterClockwise = try c.decodeIfPresent(Bool.self, forKey: .counterClockwise) ?? d.counterClockwise
        style = try c.decodeIfPresent(GaugeStyle.self, forKey: .style) ?? d.style
        secondChannel = try c.decodeIfPresent(String.self, forKey: .secondChannel) ?? d.secondChannel
        secondNeedleColor = try c.decodeIfPresent(RGBAColor.self, forKey: .secondNeedleColor) ?? d.secondNeedleColor
        needle = try c.decodeIfPresent(NeedleStyle.self, forKey: .needle) ?? d.needle
        ticks = try c.decodeIfPresent(TickStyle.self, forKey: .ticks) ?? d.ticks
        if let zones = try c.decodeIfPresent([GaugeZone].self, forKey: .zones) {
            self.zones = zones
        } else if let redline = try c.decodeIfPresent(Double.self, forKey: .redlineFrom) {
            let color = try c.decodeIfPresent(RGBAColor.self, forKey: .redlineColor) ?? .red
            zones = [GaugeZone(from: redline, to: nil, color: color)]
        } else {
            zones = []
        }
        zoneTargets = try c.decodeIfPresent(ZoneTargets.self, forKey: .zoneTargets) ?? d.zoneTargets
        arcWidth = try c.decodeIfPresent(Double.self, forKey: .arcWidth) ?? d.arcWidth
        arcTrackColor = try c.decodeIfPresent(RGBAColor.self, forKey: .arcTrackColor) ?? d.arcTrackColor
        showFace = try c.decodeIfPresent(Bool.self, forKey: .showFace) ?? d.showFace
        faceImageInputID = try c.decodeIfPresent(InputID.self, forKey: .faceImageInputID)
        valueDivisor = try c.decodeIfPresent(Double.self, forKey: .valueDivisor) ?? d.valueDivisor
        showValue = try c.decodeIfPresent(Bool.self, forKey: .showValue) ?? d.showValue
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals
        faceColor = try c.decodeIfPresent(RGBAColor.self, forKey: .faceColor) ?? d.faceColor
        needleColor = try c.decodeIfPresent(RGBAColor.self, forKey: .needleColor) ?? d.needleColor
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(channel, forKey: .channel)
        try c.encode(title, forKey: .title)
        try c.encode(minValue, forKey: .minValue)
        try c.encode(maxValue, forKey: .maxValue)
        try c.encode(speedUnit, forKey: .speedUnit)
        try c.encode(unitLabel, forKey: .unitLabel)
        try c.encode(majorTick, forKey: .majorTick)
        try c.encode(minorTick, forKey: .minorTick)
        try c.encode(sweep, forKey: .sweep)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(counterClockwise, forKey: .counterClockwise)
        try c.encode(style, forKey: .style)
        try c.encode(secondChannel, forKey: .secondChannel)
        try c.encode(secondNeedleColor, forKey: .secondNeedleColor)
        try c.encode(needle, forKey: .needle)
        try c.encode(ticks, forKey: .ticks)
        try c.encode(zones, forKey: .zones)
        try c.encode(zoneTargets, forKey: .zoneTargets)
        try c.encode(arcWidth, forKey: .arcWidth)
        try c.encode(arcTrackColor, forKey: .arcTrackColor)
        try c.encode(showFace, forKey: .showFace)
        try c.encodeIfPresent(faceImageInputID, forKey: .faceImageInputID)
        try c.encode(valueDivisor, forKey: .valueDivisor)
        try c.encode(showValue, forKey: .showValue)
        try c.encode(decimals, forKey: .decimals)
        try c.encode(faceColor, forKey: .faceColor)
        try c.encode(needleColor, forKey: .needleColor)
        try c.encode(textColor, forKey: .textColor)
    }

    /// The start of the first zone that runs to the maximum (the classic red line), if any.
    public var redlineFrom: Double? {
        zones.first { $0.to == nil }?.from
    }

    public static func speedometer(unit: SpeedDisplayUnit = .mph, max: Double = 160) -> GaugeParams {
        GaugeParams(
            channel: "speed", title: "SPEED", minValue: 0, maxValue: max, speedUnit: unit, majorTick: 20, minorTick: 10)
    }

    public static func tachometer(max: Double = 8000, redline: Double = 6500) -> GaugeParams {
        GaugeParams(
            channel: "rpm", title: "RPM", minValue: 0, maxValue: max, unitLabel: "rpm", majorTick: 1000, minorTick: 500,
            zones: [GaugeZone(from: redline, to: nil, color: .red)])
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

    public init(
        id: DisplayObjectID = DisplayObjectID(),
        label: String,
        inputID: InputID?,
        frame: UnitRect,
        opacity: Double = 1,
        isVisible: Bool = true,
        kind: DisplayObjectKind
    ) {
        self.id = id
        self.label = label
        self.inputID = inputID
        self.frame = frame
        self.opacity = opacity
        self.isVisible = isVisible
        self.kind = kind
    }
}
