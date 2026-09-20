import SwiftUI

/// Small controls shared by the inspector panels.

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let fractionDigits: ClosedRange<Int>
    let step: Double
    let range: ClosedRange<Double>?

    /// `step` is how far one press of ↑/↓ moves the value; ⇧ multiplies it. It defaults to 1,
    /// which suits the percentages, degrees and pixel counts most of these fields hold — pass a
    /// smaller step for a field that lives between 0 and 1.
    init(
        _ title: String, value: Binding<Double>, fractionDigits: ClosedRange<Int> = 0...3,
        step: Double = 1, range: ClosedRange<Double>? = nil
    ) {
        self.title = title
        _value = value
        self.fractionDigits = fractionDigits
        self.step = step
        self.range = range
    }

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(fractionDigits)))
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                adjust(
                    by: press.key == .upArrow ? step : -step,
                    coarse: press.modifiers.contains(.shift))
                return .handled
            }
    }

    private func adjust(by amount: Double, coarse: Bool) {
        let moved = value + amount * (coarse ? NudgeStep.shiftMultiplier : 1)
        value = range.map { min(max(moved, $0.lowerBound), $0.upperBound) } ?? moved
    }
}
