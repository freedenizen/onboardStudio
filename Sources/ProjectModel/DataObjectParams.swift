import Foundation

/// Map imagery drawn behind the track outline (fetched from Apple Maps and cached on disk).
public enum MapBackgroundStyle: String, Codable, Sendable, CaseIterable {
    case none
    case standard
    case satellite
    case hybrid

    public var displayName: String {
        switch self {
        case .none: "None"
        case .standard: "Map"
        case .satellite: "Satellite"
        case .hybrid: "Satellite with labels"
        }
    }
}

/// Which part of the session the track map draws its outline from.
public enum TrackMapTrace: String, Hashable, Codable, Sendable, CaseIterable {
    /// Every position in the file. Measured on a real session: nine laps overlap to within
    /// 0.9 m on a 4 km lap, so at overlay size the overdraw is invisible.
    case wholeSession
    /// Only the lap sectors and deltas are measured against — a crisper line, and one that
    /// leaves out the pit lane and the paddock because the reference lap never went there.
    case referenceLap

    public var displayName: String {
        switch self {
        case .wholeSession: "Whole session"
        case .referenceLap: "Reference lap only"
        }
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
    /// Map imagery behind the outline.
    public var background: MapBackgroundStyle
    /// A second data input whose position is shown as another dot (two-vehicle map).
    public var secondInputID: InputID?
    public var secondDotColor: RGBAColor
    /// Which part of the session the outline is drawn from.
    public var trace: TrackMapTrace
    /// Paints each sector of the outline its own colour, which is what makes a sector time
    /// legible at a glance.
    public var colorBySector: Bool
    /// Cycled across the sectors; a shorter list repeats. Empty falls back to `lineColor`.
    public var sectorColors: [RGBAColor]
    /// A short line across the track at each sector boundary, numbered. Cheaper to read than
    /// full colouring at small sizes, and the two can be used together.
    public var showSectorTicks: Bool
    /// Numbers the corners the way a circuit diagram does, found from the reference lap's
    /// curvature rather than from any published map.
    public var showCornerNumbers: Bool
    public var labelColor: RGBAColor
    /// Label size as a fraction of the map's shorter side.
    public var labelScale: Double

    public init(
        lineColor: RGBAColor = .white,
        lineWidth: Double = 3,
        dotColor: RGBAColor = .accent,
        dotRadius: Double = 7,
        rotation: Double = 0,
        backgroundColor: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0),
        background: MapBackgroundStyle = .none,
        secondInputID: InputID? = nil,
        secondDotColor: RGBAColor = RGBAColor(red: 0.25, green: 0.6, blue: 1),
        trace: TrackMapTrace = .wholeSession,
        colorBySector: Bool = false,
        sectorColors: [RGBAColor] = TrackMapParams.defaultSectorColors,
        showSectorTicks: Bool = false,
        showCornerNumbers: Bool = false,
        labelColor: RGBAColor = .white,
        labelScale: Double = 0.09
    ) {
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.dotColor = dotColor
        self.dotRadius = dotRadius
        self.rotation = rotation
        self.backgroundColor = backgroundColor
        self.background = background
        self.secondInputID = secondInputID
        self.secondDotColor = secondDotColor
        self.trace = trace
        self.colorBySector = colorBySector
        self.sectorColors = sectorColors
        self.showSectorTicks = showSectorTicks
        self.showCornerNumbers = showCornerNumbers
        self.labelColor = labelColor
        self.labelScale = labelScale
    }

    /// Three colours that stay apart on a dark video and for the common colour blindness, so a
    /// sector can be told from its neighbour without reading the numbers.
    public static let defaultSectorColors: [RGBAColor] = [
        RGBAColor(red: 0.35, green: 0.78, blue: 1),
        RGBAColor(red: 1, green: 0.84, blue: 0.2),
        RGBAColor(red: 0.95, green: 0.45, blue: 0.75),
    ]

    private enum CodingKeys: String, CodingKey {
        case lineColor, lineWidth, dotColor, dotRadius, rotation, backgroundColor
        case background, secondInputID, secondDotColor
        case trace, colorBySector, sectorColors, showSectorTicks, showCornerNumbers, labelColor, labelScale
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TrackMapParams()
        lineColor = try c.decodeIfPresent(RGBAColor.self, forKey: .lineColor) ?? d.lineColor
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? d.lineWidth
        dotColor = try c.decodeIfPresent(RGBAColor.self, forKey: .dotColor) ?? d.dotColor
        dotRadius = try c.decodeIfPresent(Double.self, forKey: .dotRadius) ?? d.dotRadius
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? d.rotation
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        background = try c.decodeIfPresent(MapBackgroundStyle.self, forKey: .background) ?? .none
        secondInputID = try c.decodeIfPresent(InputID.self, forKey: .secondInputID)
        secondDotColor = try c.decodeIfPresent(RGBAColor.self, forKey: .secondDotColor) ?? d.secondDotColor
        // All absent from projects saved before these options existed, and all default to off,
        // so such a project draws exactly the outline it drew before.
        trace = try c.decodeIfPresent(TrackMapTrace.self, forKey: .trace) ?? d.trace
        colorBySector = try c.decodeIfPresent(Bool.self, forKey: .colorBySector) ?? d.colorBySector
        sectorColors = try c.decodeIfPresent([RGBAColor].self, forKey: .sectorColors) ?? d.sectorColors
        showSectorTicks = try c.decodeIfPresent(Bool.self, forKey: .showSectorTicks) ?? d.showSectorTicks
        showCornerNumbers = try c.decodeIfPresent(Bool.self, forKey: .showCornerNumbers) ?? d.showCornerNumbers
        labelColor = try c.decodeIfPresent(RGBAColor.self, forKey: .labelColor) ?? d.labelColor
        labelScale = try c.decodeIfPresent(Double.self, forKey: .labelScale) ?? d.labelScale
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
    /// Channel driving the horizontal axis; empty uses the standard `lateralG` role.
    public var lateralChannel: String
    /// Channel driving the vertical axis; empty uses the standard `longitudinalG` role.
    public var longitudinalChannel: String
    /// Loggers disagree on which way is positive: RaceRender calls a right turn positive, while
    /// ISO 8855 vehicle axes (which RaceChrono follows) make a left turn positive.
    public var invertLateral: Bool
    /// As `invertLateral`, for braking versus accelerating.
    public var invertLongitudinal: Bool

    public init(
        maxG: Double = 2,
        ringStep: Double = 0.5,
        trailSeconds: Double = 1.5,
        dotColor: RGBAColor = .accent,
        gridColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.5),
        faceColor: RGBAColor = .faceDark,
        showValues: Bool = true,
        lateralChannel: String = "",
        longitudinalChannel: String = "",
        invertLateral: Bool = false,
        invertLongitudinal: Bool = false
    ) {
        self.maxG = maxG
        self.ringStep = ringStep
        self.trailSeconds = trailSeconds
        self.dotColor = dotColor
        self.gridColor = gridColor
        self.faceColor = faceColor
        self.showValues = showValues
        self.lateralChannel = lateralChannel
        self.longitudinalChannel = longitudinalChannel
        self.invertLateral = invertLateral
        self.invertLongitudinal = invertLongitudinal
    }

    private enum CodingKeys: String, CodingKey {
        case maxG, ringStep, trailSeconds, dotColor, gridColor, faceColor, showValues
        case lateralChannel, longitudinalChannel, invertLateral, invertLongitudinal
    }

    /// Decoded field by field so projects saved before the axis settings existed still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GForceParams()
        maxG = try c.decodeIfPresent(Double.self, forKey: .maxG) ?? d.maxG
        ringStep = try c.decodeIfPresent(Double.self, forKey: .ringStep) ?? d.ringStep
        trailSeconds = try c.decodeIfPresent(Double.self, forKey: .trailSeconds) ?? d.trailSeconds
        dotColor = try c.decodeIfPresent(RGBAColor.self, forKey: .dotColor) ?? d.dotColor
        gridColor = try c.decodeIfPresent(RGBAColor.self, forKey: .gridColor) ?? d.gridColor
        faceColor = try c.decodeIfPresent(RGBAColor.self, forKey: .faceColor) ?? d.faceColor
        showValues = try c.decodeIfPresent(Bool.self, forKey: .showValues) ?? d.showValues
        lateralChannel = try c.decodeIfPresent(String.self, forKey: .lateralChannel) ?? d.lateralChannel
        longitudinalChannel =
            try c.decodeIfPresent(String.self, forKey: .longitudinalChannel) ?? d.longitudinalChannel
        invertLateral = try c.decodeIfPresent(Bool.self, forKey: .invertLateral) ?? d.invertLateral
        invertLongitudinal = try c.decodeIfPresent(Bool.self, forKey: .invertLongitudinal) ?? d.invertLongitudinal
    }

    /// The signed value for an axis: the chosen channel if it names one, else the standard role.
    public func axisValue(_ raw: Double?, invert: Bool) -> Double {
        guard let raw, raw.isFinite else { return 0 }
        return invert ? -raw : raw
    }

    /// Points the lateral axis the right way when the session measured which way the car turned.
    /// The channel it checks is whichever one drives that axis: the object's own if it names one,
    /// otherwise the standard `lateralG` role.
    public func adapted(to channels: [ChannelSummary]) -> GForceParams {
        var result = self
        let identifier = lateralChannel.isEmpty ? "lateralG" : lateralChannel
        guard let summary = channels.first(where: { $0.identifier == identifier }),
            let correlation = summary.rightTurnCorrelation
        else { return result }
        result.invertLateral = correlation < 0
        return result
    }
}

public enum TimerMode: String, Codable, Sendable, CaseIterable {
    /// Time since the current lap started.
    case currentLap
    case lastLap
    case bestLap
    /// Time since the data session started.
    case session
    /// Time since the start of the project (the video's own clock).
    case projectTime
    /// Wall-clock time of day at the data's timestamp.
    case timeOfDay
    /// Current lap time ahead (−) or behind (+) the best lap at the same distance into the lap.
    case deltaToBest

    public var displayName: String {
        switch self {
        case .currentLap: "Current lap"
        case .lastLap: "Last lap"
        case .bestLap: "Best lap"
        case .session: "Session time"
        case .projectTime: "Video time"
        case .timeOfDay: "Time of day"
        case .deltaToBest: "Delta to best lap"
        }
    }
}

public struct TimerParams: Hashable, Codable, Sendable {
    public var mode: TimerMode
    public var showLapNumber: Bool
    public var label: String?
    public var textColor: RGBAColor
    public var backgroundColor: RGBAColor
    /// Fractional digits shown (1…3).
    public var decimals: Int
    /// Colours for a delta readout: ahead of / behind the best lap.
    public var aheadColor: RGBAColor
    public var behindColor: RGBAColor
    /// The lap a delta readout compares with. Files from before 0.17 used the best lap so far.
    public var deltaReference: LapReference

    public init(
        mode: TimerMode = .currentLap,
        showLapNumber: Bool = true,
        label: String? = nil,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .translucentBlack,
        decimals: Int = 2,
        aheadColor: RGBAColor = RGBAColor(red: 0.25, green: 0.85, blue: 0.35),
        behindColor: RGBAColor = .red,
        deltaReference: LapReference = .sessionBest
    ) {
        self.mode = mode
        self.showLapNumber = showLapNumber
        self.label = label
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.decimals = decimals
        self.aheadColor = aheadColor
        self.behindColor = behindColor
        self.deltaReference = deltaReference
    }

    private enum CodingKeys: String, CodingKey {
        case mode, showLapNumber, label, textColor, backgroundColor, decimals, aheadColor, behindColor
        case deltaReference
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TimerParams()
        mode = try c.decodeIfPresent(TimerMode.self, forKey: .mode) ?? d.mode
        showLapNumber = try c.decodeIfPresent(Bool.self, forKey: .showLapNumber) ?? d.showLapNumber
        label = try c.decodeIfPresent(String.self, forKey: .label)
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals
        aheadColor = try c.decodeIfPresent(RGBAColor.self, forKey: .aheadColor) ?? d.aheadColor
        behindColor = try c.decodeIfPresent(RGBAColor.self, forKey: .behindColor) ?? d.behindColor
        deltaReference = try c.decodeIfPresent(LapReference.self, forKey: .deltaReference) ?? .bestLap
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
    /// Applied before display: `shown = value × multiplier + offset`.
    public var multiplier: Double
    public var offset: Double
    /// Text placed before the number (after the caption).
    public var prefix: String
    public var thousandsSeparator: Bool
    /// Show `+` for positive values.
    public var showPlusSign: Bool
    /// Zero-pad the integer part to this many digits.
    public var minimumIntegerDigits: Int
    public var absoluteValue: Bool
    /// Value font size as a fraction of the object height.
    public var fontScale: Double
    /// Caption font size as a fraction of the object height.
    public var labelScale: Double
    /// Font for the value; empty = monospaced digits (Menlo).
    public var fontName: String
    /// Value ranges that recolour the number (warning thresholds); empty = always `textColor`.
    public var zones: [GaugeZone]

    public init(
        channel: String,
        label: String,
        decimals: Int = 0,
        speedUnit: SpeedDisplayUnit = .mph,
        unitLabel: String = "",
        alignment: TextAlignment = .leading,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .translucentBlack,
        multiplier: Double = 1,
        offset: Double = 0,
        prefix: String = "",
        thousandsSeparator: Bool = false,
        showPlusSign: Bool = false,
        minimumIntegerDigits: Int = 1,
        absoluteValue: Bool = false,
        fontScale: Double = 0.5,
        labelScale: Double = 0.3,
        fontName: String = "",
        zones: [GaugeZone] = []
    ) {
        self.channel = channel
        self.label = label
        self.decimals = decimals
        self.speedUnit = speedUnit
        self.unitLabel = unitLabel
        self.alignment = alignment
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.multiplier = multiplier
        self.offset = offset
        self.prefix = prefix
        self.thousandsSeparator = thousandsSeparator
        self.showPlusSign = showPlusSign
        self.minimumIntegerDigits = minimumIntegerDigits
        self.absoluteValue = absoluteValue
        self.fontScale = fontScale
        self.labelScale = labelScale
        self.fontName = fontName
        self.zones = zones
    }

    private enum CodingKeys: String, CodingKey {
        case channel, label, decimals, speedUnit, unitLabel, alignment, textColor, backgroundColor
        case multiplier, offset, prefix, thousandsSeparator, showPlusSign, minimumIntegerDigits, absoluteValue
        case fontScale, labelScale, fontName, zones
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TextDataParams(channel: "", label: "")
        channel = try c.decode(String.self, forKey: .channel)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals
        speedUnit = try c.decodeIfPresent(SpeedDisplayUnit.self, forKey: .speedUnit) ?? d.speedUnit
        unitLabel = try c.decodeIfPresent(String.self, forKey: .unitLabel) ?? d.unitLabel
        alignment = try c.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? d.alignment
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        multiplier = try c.decodeIfPresent(Double.self, forKey: .multiplier) ?? d.multiplier
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? d.offset
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? d.prefix
        thousandsSeparator = try c.decodeIfPresent(Bool.self, forKey: .thousandsSeparator) ?? d.thousandsSeparator
        showPlusSign = try c.decodeIfPresent(Bool.self, forKey: .showPlusSign) ?? d.showPlusSign
        minimumIntegerDigits = try c.decodeIfPresent(Int.self, forKey: .minimumIntegerDigits) ?? d.minimumIntegerDigits
        absoluteValue = try c.decodeIfPresent(Bool.self, forKey: .absoluteValue) ?? d.absoluteValue
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? d.fontScale
        labelScale = try c.decodeIfPresent(Double.self, forKey: .labelScale) ?? d.labelScale
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        zones = try c.decodeIfPresent([GaugeZone].self, forKey: .zones) ?? []
    }
}

/// A JavaScript-drawn object: `background(canvas)` runs once per output size for static parts,
/// `frame(canvas, data)` runs every frame. See `docs/scripting.md`.
public struct ScriptedParams: Hashable, Codable, Sendable {
    public var source: String

    public init(source: String = ScriptedParams.defaultSource) {
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? Self.defaultSource
    }

    // swiftlint:disable line_length
    public static let defaultSource = """
        // Drawn once: a translucent rounded panel.
        function background(canvas) {
            canvas.fill("#00000088");
            canvas.roundRect(0, 0, canvas.width, canvas.height, canvas.height * 0.15);
        }

        // Drawn every frame: the speed in big digits.
        function frame(canvas, data) {
            const speed = data.speed("mph");
            canvas.fill("#ffffff");
            canvas.text(speed === null ? "--" : speed.toFixed(0), canvas.width * 0.5, canvas.height * 0.55,
                        { size: canvas.height * 0.6, align: "center", bold: true, mono: true });
            canvas.text("mph", canvas.width * 0.5, canvas.height * 0.9, { size: canvas.height * 0.18, align: "center" });
        }
        """
    // swiftlint:enable line_length
}
