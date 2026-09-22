import Foundation

/// What the editor knows about one channel of a data input; enough to adapt a template to it.
public struct ChannelSummary: Hashable, Sendable {
    public var identifier: String
    public var name: String
    /// The symbol the channel's values are in (`kPa`, `%`, `km/h`), or empty when it has none.
    /// Text, because this type is deliberately dependency-free and `TelemetryUnit` lives in
    /// `TelemetryKit`.
    public var unit: String
    public var minValue: Double?
    public var maxValue: Double?
    /// How this channel relates to a right turn measured from the session itself, −1…1, or `nil`
    /// when the session could not say. Negative means the channel is positive for a *left* turn
    /// and wants inverting. Computed where the samples live (`TurnDirection`), because this type
    /// is deliberately dependency-free.
    public var rightTurnCorrelation: Double?

    public init(
        identifier: String,
        name: String,
        unit: String = "",
        minValue: Double? = nil,
        maxValue: Double? = nil,
        rightTurnCorrelation: Double? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.unit = unit
        self.minValue = minValue
        self.maxValue = maxValue
        self.rightTurnCorrelation = rightTurnCorrelation
    }
}

extension ChannelSummary {
    /// A scale that contains everything this channel does, rounded out to a round number — what a
    /// gauge or a bar should be created with (#180).
    ///
    /// `nil` when the range is unknown or flat, and then whatever scale the object already had
    /// stands: a guess is only worth making when the data supports one.
    ///
    /// Three shapes, because physical channels come in three:
    /// - values that straddle zero (deltas, G, steering) get a **symmetric** scale, so zero sits
    ///   in the middle where the eye expects it;
    /// - values that never go negative start at **zero**, because a bar filling from anywhere else
    ///   misreads at a glance;
    /// - anything else keeps its own floor, rounded down.
    public var suggestedBounds: (min: Double, max: Double)? {
        guard let low = minValue, let high = maxValue, low.isFinite, high.isFinite, high > low else { return nil }
        if low < 0 && high > 0 {
            let extent = Self.roundedOut(Swift.max(Swift.abs(low), Swift.abs(high)), span: high - low)
            return (-extent, extent)
        }
        if low >= 0 { return (0, Self.roundedOut(high, span: high)) }
        return (-Self.roundedOut(Swift.abs(low), span: high - low), Self.roundedOut(high, span: high - low))
    }

    /// Whether what gets drawn for this channel is converted first, and so is not in the unit
    /// `minValue` and `maxValue` are in.
    ///
    /// Speed alone, today: `SessionBuilder` stores it in m/s and the renderer multiplies by the
    /// object's speed unit (#75), so a scale fitted to the stored range would be wrong by exactly
    /// that factor — a 0…58 dial for a car that reaches 130 mph. Such a channel is left to the
    /// scale its template carries until the display-unit work (#89) puts the conversion somewhere
    /// this can ask.
    public var isConvertedForDisplay: Bool { identifier == "speed" || identifier == "speedDelta" }

    /// Rounds `value` away from zero to a step derived from the span, so 1873 becomes 1900 and
    /// 1.37 becomes 1.4. The same idiom `suggestedThreshold` uses, kept in one place.
    private static func roundedOut(_ value: Double, span: Double) -> Double {
        guard span > 0, value != 0 else { return value }
        let step = pow(10, floor(log10(span)) - 1)
        guard step > 0, step.isFinite else { return value }
        return (value / step).rounded(.up) * step
    }
}
