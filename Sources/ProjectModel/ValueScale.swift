import Foundation

/// How a slider's stored value reads in the box beside it (#266): a crop stored as 0.12 is shown
/// and typed as 12 %, a stabilisation zoom of 1.08 as 8 %.
///
/// `shown = stored × factor + offset`. The box shows `fractionDigits` decimals at most, and a
/// typed value is held to the slider's range so the two can never disagree.
public struct ValueScale: Hashable, Sendable {
    public var factor: Double
    public var offset: Double
    public var fractionDigits: Int

    public init(factor: Double = 1, offset: Double = 0, fractionDigits: Int = 0) {
        self.factor = factor
        self.offset = offset
        self.fractionDigits = fractionDigits
    }

    /// The value as stored, in whole numbers or the given decimals.
    public static func plain(fractionDigits: Int = 0) -> ValueScale { ValueScale(fractionDigits: fractionDigits) }
    /// A fraction shown as a whole percentage: 0.12 reads 12.
    public static let percent = ValueScale(factor: 100)
    /// A scale factor shown as the percentage it adds: 1.08 reads 8.
    public static let percentAboveOne = ValueScale(factor: 100, offset: -100)

    public func shown(_ stored: Double) -> Double { stored * factor + offset }

    /// The stored value for a typed one, held to `range` (which is in stored units).
    public func stored(_ shown: Double, in range: ClosedRange<Double>) -> Double {
        guard shown.isFinite, factor != 0 else { return range.lowerBound }
        let value = (shown - offset) / factor
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// `range` as the box shows it.
    public func shown(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let (low, high) = (shown(range.lowerBound), shown(range.upperBound))
        return min(low, high)...max(low, high)
    }

    /// How far one press of ↑/↓ in the box moves the value, in the box's units: the slider's step
    /// when it has one, otherwise one unit of the last decimal shown.
    public func keyStep(sliderStep: Double?) -> Double {
        if let sliderStep, sliderStep > 0 { return abs(sliderStep * factor) }
        return pow(10, Double(-fractionDigits))
    }
}
