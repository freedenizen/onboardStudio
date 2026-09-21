import Foundation

// MARK: - Bar / level

public enum BarOrientation: String, Codable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

/// A linear bar that fills from the minimum to the current value.
public struct BarParams: Hashable, Codable, Sendable {
    public var channel: String
    public var label: String
    public var minValue: Double
    public var maxValue: Double
    public var orientation: BarOrientation
    public var fillColor: RGBAColor
    public var trackColor: RGBAColor
    public var textColor: RGBAColor
    public var zones: [GaugeZone]
    /// Colour the fill by the zone the current value is in (otherwise zones paint the track).
    public var zoneColorsFill: Bool
    /// Number of discrete segments (0 = continuous).
    public var segments: Int
    public var showValue: Bool
    public var decimals: Int
    public var speedUnit: SpeedUnitSetting
    public var unitLabel: String
    /// Corner radius as a fraction of the bar thickness.
    public var cornerRadius: Double
    /// Fill from zero towards the value instead of from the minimum: a ± bar for deltas, steering
    /// or lateral g. Needs a range that spans zero.
    public var fillFromZero: Bool

    public init(
        channel: String,
        label: String = "",
        minValue: Double = 0,
        maxValue: Double = 100,
        orientation: BarOrientation = .horizontal,
        fillColor: RGBAColor = .accent,
        trackColor: RGBAColor = .faceDark,
        textColor: RGBAColor = .white,
        zones: [GaugeZone] = [],
        zoneColorsFill: Bool = true,
        segments: Int = 0,
        showValue: Bool = true,
        decimals: Int = 0,
        speedUnit: SpeedUnitSetting = .automatic,
        unitLabel: String = "",
        cornerRadius: Double = 0.25,
        fillFromZero: Bool = false
    ) {
        self.channel = channel
        self.label = label
        self.minValue = minValue
        self.maxValue = maxValue
        self.orientation = orientation
        self.fillColor = fillColor
        self.trackColor = trackColor
        self.textColor = textColor
        self.zones = zones
        self.zoneColorsFill = zoneColorsFill
        self.segments = segments
        self.showValue = showValue
        self.decimals = decimals
        self.speedUnit = speedUnit
        self.unitLabel = unitLabel
        self.cornerRadius = cornerRadius
        self.fillFromZero = fillFromZero
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarParams(channel: "")
        channel = try c.decode(String.self, forKey: .channel)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        minValue = try c.decodeIfPresent(Double.self, forKey: .minValue) ?? d.minValue
        maxValue = try c.decodeIfPresent(Double.self, forKey: .maxValue) ?? d.maxValue
        orientation = try c.decodeIfPresent(BarOrientation.self, forKey: .orientation) ?? d.orientation
        fillColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fillColor) ?? d.fillColor
        trackColor = try c.decodeIfPresent(RGBAColor.self, forKey: .trackColor) ?? d.trackColor
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        zones = try c.decodeIfPresent([GaugeZone].self, forKey: .zones) ?? d.zones
        zoneColorsFill = try c.decodeIfPresent(Bool.self, forKey: .zoneColorsFill) ?? d.zoneColorsFill
        segments = try c.decodeIfPresent(Int.self, forKey: .segments) ?? d.segments
        showValue = try c.decodeIfPresent(Bool.self, forKey: .showValue) ?? d.showValue
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals
        speedUnit = try c.decodeIfPresent(SpeedUnitSetting.self, forKey: .speedUnit) ?? .mph
        unitLabel = try c.decodeIfPresent(String.self, forKey: .unitLabel) ?? d.unitLabel
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        fillFromZero = try c.decodeIfPresent(Bool.self, forKey: .fillFromZero) ?? d.fillFromZero
    }
}

// MARK: - 2D graph

/// What the horizontal axis of a graph represents.
public enum GraphAxis: String, Codable, Sendable, CaseIterable {
    /// The last `window` seconds.
    case time
    /// The last `window` metres travelled.
    case distance
    /// Distance into the current lap, from the start line; optionally with the best lap as a ghost.
    case lap
}

public struct GraphSeries: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var channel: String
    public var color: RGBAColor
    /// Line width in pixels at 1080p; scaled with the output.
    public var lineWidth: Double

    public init(id: UUID = UUID(), channel: String, color: RGBAColor = .accent, lineWidth: Double = 3) {
        self.id = id
        self.channel = channel
        self.color = color
        self.lineWidth = lineWidth
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        channel = try c.decode(String.self, forKey: .channel)
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .accent
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 3
    }
}

/// A scrolling line graph of one or more channels against time or distance.
public struct GraphParams: Hashable, Codable, Sendable {
    public var series: [GraphSeries]
    public var axis: GraphAxis
    /// Seconds (`.time`) or metres (`.distance`) of history shown; ignored for `.lap`.
    public var window: Double
    /// Fixed vertical range, or `nil` to fit the visible data.
    public var minValue: Double?
    public var maxValue: Double?
    public var speedUnit: SpeedUnitSetting
    public var label: String
    public var backgroundColor: RGBAColor
    public var gridColor: RGBAColor
    public var textColor: RGBAColor
    /// Horizontal grid lines (0 = none).
    public var gridLines: Int
    /// Shade the area under the first series.
    public var fillUnderLine: Bool
    /// Mark the current value with a dot and readout.
    public var showCursor: Bool
    /// Show the axis range labels.
    public var showLabels: Bool
    /// For `.lap`: also draw the best lap's trace in `ghostColor`.
    public var compareBestLap: Bool
    public var ghostColor: RGBAColor

    public init(
        series: [GraphSeries],
        axis: GraphAxis = .time,
        window: Double = 10,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        speedUnit: SpeedUnitSetting = .automatic,
        label: String = "",
        backgroundColor: RGBAColor = .faceDark,
        gridColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.25),
        textColor: RGBAColor = .white,
        gridLines: Int = 3,
        fillUnderLine: Bool = true,
        showCursor: Bool = true,
        showLabels: Bool = true,
        compareBestLap: Bool = true,
        ghostColor: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.45)
    ) {
        self.series = series
        self.axis = axis
        self.window = window
        self.minValue = minValue
        self.maxValue = maxValue
        self.speedUnit = speedUnit
        self.label = label
        self.backgroundColor = backgroundColor
        self.gridColor = gridColor
        self.textColor = textColor
        self.gridLines = gridLines
        self.fillUnderLine = fillUnderLine
        self.showCursor = showCursor
        self.showLabels = showLabels
        self.compareBestLap = compareBestLap
        self.ghostColor = ghostColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GraphParams(series: [])
        series = try c.decodeIfPresent([GraphSeries].self, forKey: .series) ?? d.series
        axis = try c.decodeIfPresent(GraphAxis.self, forKey: .axis) ?? d.axis
        window = try c.decodeIfPresent(Double.self, forKey: .window) ?? d.window
        minValue = try c.decodeIfPresent(Double.self, forKey: .minValue)
        maxValue = try c.decodeIfPresent(Double.self, forKey: .maxValue)
        speedUnit = try c.decodeIfPresent(SpeedUnitSetting.self, forKey: .speedUnit) ?? .mph
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        gridColor = try c.decodeIfPresent(RGBAColor.self, forKey: .gridColor) ?? d.gridColor
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        gridLines = try c.decodeIfPresent(Int.self, forKey: .gridLines) ?? d.gridLines
        fillUnderLine = try c.decodeIfPresent(Bool.self, forKey: .fillUnderLine) ?? d.fillUnderLine
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? d.showCursor
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? d.showLabels
        compareBestLap = try c.decodeIfPresent(Bool.self, forKey: .compareBestLap) ?? d.compareBestLap
        ghostColor = try c.decodeIfPresent(RGBAColor.self, forKey: .ghostColor) ?? d.ghostColor
    }
}

// MARK: - Gear

/// The current gear as a large glyph. Gear channel convention: 0 = neutral, −1 = reverse, −99 = park.
public struct GearParams: Hashable, Codable, Sendable {
    public var channel: String
    public var label: String
    public var showLabel: Bool
    public var neutralText: String
    public var reverseText: String
    public var parkText: String
    public var textColor: RGBAColor
    public var backgroundColor: RGBAColor
    /// Glyph size as a fraction of the object height.
    public var fontScale: Double

    public init(
        channel: String = "gear",
        label: String = "GEAR",
        showLabel: Bool = true,
        neutralText: String = "N",
        reverseText: String = "R",
        parkText: String = "P",
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .translucentBlack,
        fontScale: Double = 0.7
    ) {
        self.channel = channel
        self.label = label
        self.showLabel = showLabel
        self.neutralText = neutralText
        self.reverseText = reverseText
        self.parkText = parkText
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.fontScale = fontScale
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GearParams()
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? d.channel
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        showLabel = try c.decodeIfPresent(Bool.self, forKey: .showLabel) ?? d.showLabel
        neutralText = try c.decodeIfPresent(String.self, forKey: .neutralText) ?? d.neutralText
        reverseText = try c.decodeIfPresent(String.self, forKey: .reverseText) ?? d.reverseText
        parkText = try c.decodeIfPresent(String.self, forKey: .parkText) ?? d.parkText
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? d.fontScale
    }

    /// Text shown for a gear value.
    public func text(for value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        let gear = Int(min(max(value.rounded(), -1_000_000), 1_000_000))
        switch gear {
        case 0: return neutralText
        case -1: return reverseText
        case -99: return parkText
        case ..<0: return reverseText
        default: return String(gear)
        }
    }
}

// MARK: - Lap counter

/// The current lap number, optionally "of N".
public struct LapCounterParams: Hashable, Codable, Sendable {
    public var label: String
    public var showTotal: Bool
    /// Added to the lap number before display (e.g. 1 when the file numbers laps from 0).
    public var numberOffset: Int
    public var textColor: RGBAColor
    public var backgroundColor: RGBAColor

    public init(
        label: String = "LAP",
        showTotal: Bool = false,
        numberOffset: Int = 0,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .translucentBlack
    ) {
        self.label = label
        self.showTotal = showTotal
        self.numberOffset = numberOffset
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LapCounterParams()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        showTotal = try c.decodeIfPresent(Bool.self, forKey: .showTotal) ?? d.showTotal
        numberOffset = try c.decodeIfPresent(Int.self, forKey: .numberOffset) ?? d.numberOffset
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
    }
}
