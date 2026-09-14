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
    public init() {}
}

/// A round gauge. Speedometer and tachometer are presets of this.
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
    /// Total arc in degrees.
    public var sweep: Double
    /// Rotation of the arc's centre in degrees, 0 = arc centred at the bottom gap (classic 270° gauge).
    public var rotation: Double
    /// Start of the red zone in channel units, or `nil` for none.
    public var redlineFrom: Double?
    /// Divide the channel value by this before display (e.g. 1000 for "x1000 rpm").
    public var valueDivisor: Double
    public var showValue: Bool
    public var decimals: Int
    public var faceColor: RGBAColor
    public var needleColor: RGBAColor
    public var textColor: RGBAColor
    public var redlineColor: RGBAColor

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
        redlineFrom: Double? = nil,
        valueDivisor: Double = 1,
        showValue: Bool = true,
        decimals: Int = 0,
        faceColor: RGBAColor = .faceDark,
        needleColor: RGBAColor = .accent,
        textColor: RGBAColor = .white,
        redlineColor: RGBAColor = .red
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
        self.redlineFrom = redlineFrom
        self.valueDivisor = valueDivisor
        self.showValue = showValue
        self.decimals = decimals
        self.faceColor = faceColor
        self.needleColor = needleColor
        self.textColor = textColor
        self.redlineColor = redlineColor
    }

    public static func speedometer(unit: SpeedDisplayUnit = .mph, max: Double = 160) -> GaugeParams {
        GaugeParams(
            channel: "speed", title: "SPEED", minValue: 0, maxValue: max, speedUnit: unit, majorTick: 20, minorTick: 10)
    }

    public static func tachometer(max: Double = 8000, redline: Double = 6500) -> GaugeParams {
        GaugeParams(
            channel: "rpm", title: "RPM", minValue: 0, maxValue: max, unitLabel: "rpm", majorTick: 1000, minorTick: 500,
            redlineFrom: redline)
    }
}

public struct TrackMapParams: Hashable, Codable, Sendable {
    public var lineColor: RGBAColor
    public var lineWidth: Double
    public var dotColor: RGBAColor
    public var dotRadius: Double
    /// Rotate the map clockwise in degrees (0 = north up).
    public var rotation: Double
    public var backgroundColor: RGBAColor

    public init(
        lineColor: RGBAColor = .white,
        lineWidth: Double = 3,
        dotColor: RGBAColor = .accent,
        dotRadius: Double = 7,
        rotation: Double = 0,
        backgroundColor: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
    ) {
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.dotColor = dotColor
        self.dotRadius = dotRadius
        self.rotation = rotation
        self.backgroundColor = backgroundColor
    }
}

public struct GForceParams: Hashable, Codable, Sendable {
    /// Radius of the plot in G.
    public var maxG: Double
    /// Ring spacing in G.
    public var ringStep: Double
    /// Seconds of history drawn as a fading trail; 0 disables.
    public var trailSeconds: Double
    public var dotColor: RGBAColor
    public var gridColor: RGBAColor
    public var faceColor: RGBAColor
    public var showValues: Bool

    public init(
        maxG: Double = 2,
        ringStep: Double = 0.5,
        trailSeconds: Double = 1.5,
        dotColor: RGBAColor = .accent,
        gridColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.5),
        faceColor: RGBAColor = .faceDark,
        showValues: Bool = true
    ) {
        self.maxG = maxG
        self.ringStep = ringStep
        self.trailSeconds = trailSeconds
        self.dotColor = dotColor
        self.gridColor = gridColor
        self.faceColor = faceColor
        self.showValues = showValues
    }
}

public enum TimerMode: String, Codable, Sendable, CaseIterable {
    /// Time since the current lap started.
    case currentLap
    case lastLap
    case bestLap
    /// Time since the data session started.
    case session
}

public struct TimerParams: Hashable, Codable, Sendable {
    public var mode: TimerMode
    public var showLapNumber: Bool
    public var label: String?
    public var textColor: RGBAColor
    public var backgroundColor: RGBAColor

    public init(
        mode: TimerMode = .currentLap,
        showLapNumber: Bool = true,
        label: String? = nil,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .translucentBlack
    ) {
        self.mode = mode
        self.showLapNumber = showLapNumber
        self.label = label
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

public enum TextAlignment: String, Codable, Sendable, CaseIterable {
    case leading
    case center
    case trailing
}

public struct TextDataParams: Hashable, Codable, Sendable {
    public var channel: String
    public var label: String
    public var decimals: Int
    public var speedUnit: SpeedDisplayUnit
    public var unitLabel: String
    public var alignment: TextAlignment
    public var textColor: RGBAColor
    public var backgroundColor: RGBAColor

    public init(
        channel: String,
        label: String,
        decimals: Int = 0,
        speedUnit: SpeedDisplayUnit = .mph,
        unitLabel: String = "",
        alignment: TextAlignment = .leading,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .translucentBlack
    ) {
        self.channel = channel
        self.label = label
        self.decimals = decimals
        self.speedUnit = speedUnit
        self.unitLabel = unitLabel
        self.alignment = alignment
        self.textColor = textColor
        self.backgroundColor = backgroundColor
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
        }
    }

    public var needsData: Bool {
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
