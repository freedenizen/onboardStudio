import Foundation

/// How an indicator decides it is "on".
public enum IndicatorCondition: String, Codable, Sendable, CaseIterable {
    case atLeast
    case atMost
    case equal
    case notEqual

    public var displayName: String {
        switch self {
        case .atLeast: "≥ threshold"
        case .atMost: "≤ threshold"
        case .equal: "= threshold"
        case .notEqual: "≠ threshold"
        }
    }

    public func holds(_ value: Double, threshold: Double) -> Bool {
        switch self {
        case .atLeast: value >= threshold
        case .atMost: value <= threshold
        case .equal: abs(value - threshold) < 1e-9
        case .notEqual: abs(value - threshold) >= 1e-9
        }
    }
}

/// The glyph an indicator draws.
public enum IndicatorGlyph: String, Codable, Sendable, CaseIterable {
    /// ISO ABS symbol: a circle with "ABS" and flanking brackets.
    case abs
    /// ISO stability-control symbol: a car with skid marks (DSC / ESC / TC).
    case traction
    /// A warning triangle with an exclamation mark.
    case warning
    /// A round light.
    case light
    /// The label text alone.
    case text

    public var displayName: String {
        switch self {
        case .abs: "ABS"
        case .traction: "Traction / stability"
        case .warning: "Warning triangle"
        case .light: "Round light"
        case .text: "Text only"
        }
    }
}

/// A warning light driven by one channel: dim (or hidden) until a condition holds, then lit in
/// its colour with an optional glow, held on for a minimum time and optionally flashing. Covers
/// RaceRender's brake/ABS/DSC lights without a script.
public struct IndicatorParams: Hashable, Codable, Sendable {
    public var channel: String
    public var condition: IndicatorCondition
    public var threshold: Double
    public var glyph: IndicatorGlyph
    /// Text for the `.text` glyph and the label under `.light` / `.warning`.
    public var label: String
    public var onColor: RGBAColor
    public var offColor: RGBAColor
    /// Draw the dim symbol when off (false hides it entirely).
    public var showWhenOff: Bool
    public var glow: Bool
    /// Keep the light on at least this long after the condition last held.
    public var holdSeconds: Double
    /// 0 = steady; otherwise flashes at this rate while on.
    public var flashHertz: Double
    public var outline: Bool

    public init(
        channel: String = "", condition: IndicatorCondition = .atLeast, threshold: Double = 0.5,
        glyph: IndicatorGlyph = .abs, label: String = "ABS",
        onColor: RGBAColor = RGBAColor(red: 1, green: 0.69, blue: 0),
        offColor: RGBAColor = RGBAColor(red: 0.24, green: 0.24, blue: 0.24), showWhenOff: Bool = true,
        glow: Bool = true,
        holdSeconds: Double = 0.3, flashHertz: Double = 0, outline: Bool = true
    ) {
        self.channel = channel
        self.condition = condition
        self.threshold = threshold
        self.glyph = glyph
        self.label = label
        self.onColor = onColor
        self.offColor = offColor
        self.showWhenOff = showWhenOff
        self.glow = glow
        self.holdSeconds = holdSeconds
        self.flashHertz = flashHertz
        self.outline = outline
    }

    private enum CodingKeys: String, CodingKey {
        case channel, condition, threshold, glyph, label, onColor, offColor, showWhenOff, glow, holdSeconds
        case flashHertz, outline
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IndicatorParams()
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? d.channel
        condition = try c.decodeIfPresent(IndicatorCondition.self, forKey: .condition) ?? d.condition
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? d.threshold
        glyph = try c.decodeIfPresent(IndicatorGlyph.self, forKey: .glyph) ?? d.glyph
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        onColor = try c.decodeIfPresent(RGBAColor.self, forKey: .onColor) ?? d.onColor
        offColor = try c.decodeIfPresent(RGBAColor.self, forKey: .offColor) ?? d.offColor
        showWhenOff = try c.decodeIfPresent(Bool.self, forKey: .showWhenOff) ?? d.showWhenOff
        glow = try c.decodeIfPresent(Bool.self, forKey: .glow) ?? d.glow
        holdSeconds = try c.decodeIfPresent(Double.self, forKey: .holdSeconds) ?? d.holdSeconds
        flashHertz = try c.decodeIfPresent(Double.self, forKey: .flashHertz) ?? d.flashHertz
        outline = try c.decodeIfPresent(Bool.self, forKey: .outline) ?? d.outline
    }

    /// Ready-made lights. Loggers name their ABS / stability channels differently, so the presets
    /// leave the channel empty; `adapted(to:)` fills it from the data input when one is added.
    public static let abs = IndicatorParams()
    public static let traction = IndicatorParams(
        glyph: .traction, label: "DSC", onColor: RGBAColor(red: 1, green: 0.69, blue: 0))
    public static let brake = IndicatorParams(
        channel: "brake", threshold: 1, glyph: .light, label: "BRAKE",
        onColor: RGBAColor(red: 0.9, green: 0.15, blue: 0.15),
        showWhenOff: true, glow: true, holdSeconds: 0)
}

/// What the editor knows about one channel of a data input; enough to adapt a template to it.
public struct ChannelSummary: Hashable, Sendable {
    public var identifier: String
    public var name: String
    public var minValue: Double?
    public var maxValue: Double?

    public init(identifier: String, name: String, minValue: Double? = nil, maxValue: Double? = nil) {
        self.identifier = identifier
        self.name = name
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

extension IndicatorParams {
    /// Words loggers use in the name of the channel that carries each event.
    static let glyphKeywords: [IndicatorGlyph: [String]] = [
        .abs: ["abs"],
        .traction: ["dsc", "tcs", "esc", "esp", "asr", "vsc", "psm", "dtc", "traction", "stability", "tc"],
    ]

    /// The words this light looks for: the glyph's keywords plus its own label.
    var channelKeywords: [String] {
        var words = Self.glyphKeywords[glyph] ?? []
        let own = label.trimmingCharacters(in: .whitespaces).lowercased()
        if own.count >= 2, !words.contains(own) { words.append(own) }
        return words
    }

    /// The channel most likely to carry this light's event, or `nil` when nothing in the input
    /// looks like it. Exact identifier matches win (`brake`), then names or identifiers that
    /// contain a keyword as a whole word (`aux:ABS_Active`, `obd:DSC`, `Traction Control`).
    public func suggestedChannel(among channels: [ChannelSummary]) -> String? {
        let words = channelKeywords
        guard !words.isEmpty else { return nil }
        if let exact = channels.first(where: { words.contains($0.identifier.lowercased()) }) {
            return exact.identifier
        }
        func tokens(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        return channels.first { channel in
            let parts = Set(tokens(channel.identifier) + tokens(channel.name))
            return words.contains { parts.contains($0) }
        }?.identifier
    }

    /// A starting threshold for `channel` from the values it takes in this input: half way for
    /// on/off flags (ABS, traction, warning, text) and a tenth of the way up for analogue
    /// levels behind a plain light (brake pressure, throttle). `nil` when the range is unknown or flat.
    public func suggestedThreshold(for channel: ChannelSummary) -> Double? {
        guard let low = channel.minValue, let high = channel.maxValue, high > low, low.isFinite, high.isFinite
        else { return nil }
        let fraction = glyph == .light ? 0.1 : 0.5
        let raw = low + (high - low) * fraction
        let magnitude = pow(10, floor(log10(Swift.abs(raw))) - 1)
        return magnitude > 0 && raw != 0 ? (raw / magnitude).rounded() * magnitude : raw
    }

    /// The same light bound to `channels`: keeps a channel that exists there, otherwise picks the
    /// suggested one (and a threshold to match), or leaves the channel empty for the user to choose.
    public func adapted(to channels: [ChannelSummary]) -> IndicatorParams {
        var result = self
        if !channel.isEmpty, channels.contains(where: { $0.identifier == channel }) { return result }
        guard let pick = suggestedChannel(among: channels) else { return result }
        result.channel = pick
        if let summary = channels.first(where: { $0.identifier == pick }),
            let threshold = suggestedThreshold(for: summary)
        {
            result.threshold = threshold
        }
        return result
    }
}

/// RaceRender's "timing and deltas" strip as one object: best, previous and current lap times
/// with small lap numbers, a speed-vs-best scale with the current speed and its difference, and
/// a time-vs-best scale with the signed delta.
public struct LapPanelParams: Hashable, Codable, Sendable {
    public var showBest: Bool
    public var showPrevious: Bool
    public var showCurrent: Bool
    /// Headings over the three lap blocks.
    public var bestLabel: String
    public var previousLabel: String
    public var currentLabel: String
    /// Small lap numbers in front of the times.
    public var showLapNumbers: Bool
    /// Which completed lap the speed and time lanes compare against.
    public var reference: LapReference
    public var showSpeedDelta: Bool
    public var showTimeDelta: Bool
    /// Full scale of the speed-delta lane in the display unit (± this).
    public var speedDeltaRange: Double
    /// Full scale of the time-delta lane in seconds (± this).
    public var timeDeltaRange: Double
    public var speedUnit: SpeedDisplayUnit
    public var decimals: Int
    public var textColor: RGBAColor
    public var labelColor: RGBAColor
    public var aheadColor: RGBAColor
    public var behindColor: RGBAColor
    public var backgroundColor: RGBAColor
    public var outline: Bool

    public init(
        showBest: Bool = true, showPrevious: Bool = true, showCurrent: Bool = true,
        bestLabel: String = "Best", previousLabel: String = "Previous", currentLabel: String = "Current",
        showLapNumbers: Bool = true, reference: LapReference = .bestLap, showSpeedDelta: Bool = true,
        showTimeDelta: Bool = true, speedDeltaRange: Double = 10, timeDeltaRange: Double = 2,
        speedUnit: SpeedDisplayUnit = .mph,
        decimals: Int = 1, textColor: RGBAColor = .white,
        labelColor: RGBAColor = RGBAColor(red: 0.71, green: 0.71, blue: 0.71),
        aheadColor: RGBAColor = RGBAColor(red: 0.13, green: 0.75, blue: 0.25),
        behindColor: RGBAColor = RGBAColor(red: 0.88, green: 0.19, blue: 0.19),
        backgroundColor: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0), outline: Bool = true
    ) {
        self.showBest = showBest
        self.showPrevious = showPrevious
        self.showCurrent = showCurrent
        self.bestLabel = bestLabel
        self.previousLabel = previousLabel
        self.currentLabel = currentLabel
        self.showLapNumbers = showLapNumbers
        self.reference = reference
        self.showSpeedDelta = showSpeedDelta
        self.showTimeDelta = showTimeDelta
        self.speedDeltaRange = speedDeltaRange
        self.timeDeltaRange = timeDeltaRange
        self.speedUnit = speedUnit
        self.decimals = decimals
        self.textColor = textColor
        self.labelColor = labelColor
        self.aheadColor = aheadColor
        self.behindColor = behindColor
        self.backgroundColor = backgroundColor
        self.outline = outline
    }

    private enum CodingKeys: String, CodingKey {
        case showBest, showPrevious, showCurrent, showSpeedDelta, showTimeDelta, speedDeltaRange, timeDeltaRange
        case speedUnit, decimals, textColor, labelColor, aheadColor, behindColor, backgroundColor, outline
        case bestLabel, previousLabel, currentLabel, showLapNumbers, reference
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LapPanelParams()
        showBest = try c.decodeIfPresent(Bool.self, forKey: .showBest) ?? d.showBest
        showPrevious = try c.decodeIfPresent(Bool.self, forKey: .showPrevious) ?? d.showPrevious
        showCurrent = try c.decodeIfPresent(Bool.self, forKey: .showCurrent) ?? d.showCurrent
        bestLabel = try c.decodeIfPresent(String.self, forKey: .bestLabel) ?? d.bestLabel
        previousLabel = try c.decodeIfPresent(String.self, forKey: .previousLabel) ?? d.previousLabel
        currentLabel = try c.decodeIfPresent(String.self, forKey: .currentLabel) ?? d.currentLabel
        showLapNumbers = try c.decodeIfPresent(Bool.self, forKey: .showLapNumbers) ?? d.showLapNumbers
        reference = try c.decodeIfPresent(LapReference.self, forKey: .reference) ?? d.reference
        showSpeedDelta = try c.decodeIfPresent(Bool.self, forKey: .showSpeedDelta) ?? d.showSpeedDelta
        showTimeDelta = try c.decodeIfPresent(Bool.self, forKey: .showTimeDelta) ?? d.showTimeDelta
        speedDeltaRange = try c.decodeIfPresent(Double.self, forKey: .speedDeltaRange) ?? d.speedDeltaRange
        timeDeltaRange = try c.decodeIfPresent(Double.self, forKey: .timeDeltaRange) ?? d.timeDeltaRange
        speedUnit = try c.decodeIfPresent(SpeedDisplayUnit.self, forKey: .speedUnit) ?? d.speedUnit
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        labelColor = try c.decodeIfPresent(RGBAColor.self, forKey: .labelColor) ?? d.labelColor
        aheadColor = try c.decodeIfPresent(RGBAColor.self, forKey: .aheadColor) ?? d.aheadColor
        behindColor = try c.decodeIfPresent(RGBAColor.self, forKey: .behindColor) ?? d.behindColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        outline = try c.decodeIfPresent(Bool.self, forKey: .outline) ?? d.outline
    }
}

/// The completed lap a delta is measured against.
public enum LapReference: String, Codable, Sendable, CaseIterable {
    case bestLap
    case previousLap

    public var displayName: String {
        switch self {
        case .bestLap: "Best lap"
        case .previousLap: "Previous lap"
        }
    }
}
