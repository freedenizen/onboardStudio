import Foundation

/// A round gauge. Speedometer and tachometer are presets of this; the Gauge Designer edits
/// every field.
public struct GaugeParams: Hashable, Codable, Sendable {
    /// Channel role identifier, e.g. `speed`, `rpm`, `aux:Oil temp`.
    public var channel: String
    public var title: String
    public var minValue: Double
    public var maxValue: Double
    /// For speed channels, the unit shown; ignored otherwise.
    public var speedUnit: SpeedUnitSetting
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
    /// The scale is still the preset's and waits for a data file to be fitted to (#487): a
    /// speedometer is made 0–160, which is a dial in miles per hour and stops the needle at 99 mph
    /// when it is shown in km/h. Set by the speedometer preset, and cleared when the scale has
    /// been fitted — or found to have been changed by hand. Absent from a file saved before the
    /// field existed, which reads as `false`: such a dial keeps the scale it was saved with.
    public var scaleAwaitsData = false

    public init(
        channel: String,
        title: String,
        minValue: Double,
        maxValue: Double,
        speedUnit: SpeedUnitSetting = .automatic,
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
        case faceColor, needleColor, textColor, scaleAwaitsData
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
        speedUnit = try c.decodeIfPresent(SpeedUnitSetting.self, forKey: .speedUnit) ?? .mph
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
        scaleAwaitsData = try c.decodeIfPresent(Bool.self, forKey: .scaleAwaitsData) ?? false
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
        try c.encode(scaleAwaitsData, forKey: .scaleAwaitsData)
    }

    /// The start of the first zone that runs to the maximum (the classic red line), if any.
    public var redlineFrom: Double? {
        zones.first { $0.to == nil }?.from
    }

    public static func speedometer(unit: SpeedUnitSetting = .automatic, max: Double = 160) -> GaugeParams {
        var params = GaugeParams(
            channel: "speed", title: "SPEED", minValue: 0, maxValue: max, speedUnit: unit, majorTick: 20, minorTick: 10)
        // 0–160 by 20 is a guess until there is a file and a unit to fit the dial to (#487).
        params.scaleAwaitsData = true
        return params
    }

    /// A speedometer's dial for a car that reaches `top`, in the unit the dial shows (#487): the
    /// smallest round step between labels that keeps them to a dozen or so, and a maximum that is
    /// a whole number of steps with a little room above the top speed — 0–160 by 20 for 130 mph,
    /// 0–240 by 20 for 210 km/h, 0–65 by 5 for 58 m/s.
    public static func speedScale(top: Double) -> SpeedScale {
        let reach = Swift.max(top, 1) * 1.08
        let steps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500]
        let major = steps.first { (reach / $0).rounded(.up) <= 13 } ?? 1_000
        return SpeedScale(max: (reach / major).rounded(.up) * major, major: major, minor: major / 2)
    }

    public static func tachometer(max: Double = 8000, redline: Double = 6500) -> GaugeParams {
        GaugeParams(
            channel: "rpm", title: "RPM", minValue: 0, maxValue: max, unitLabel: "rpm", majorTick: 1000, minorTick: 500,
            zones: [GaugeZone(from: redline, to: nil, color: .red)])
    }
}

/// A speedometer's dial: where it ends, and the steps between its labels and its marks.
public struct SpeedScale: Hashable, Sendable {
    public var max: Double
    public var major: Double
    public var minor: Double

    public init(max: Double, major: Double, minor: Double) {
        self.max = max
        self.major = major
        self.minor = minor
    }
}
