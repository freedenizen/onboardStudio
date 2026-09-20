import SwiftUI

/// Small controls shared by the inspector panels.

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let fractionDigits: ClosedRange<Int>
    let step: Double
    let range: ClosedRange<Double>?

    /// `step` is how far one press of ↑/↓ moves the value. It defaults to 1, which suits the
    /// percentages, degrees and counts most of these fields hold — pass a smaller step for a
    /// field that lives between 0 and 1, where ±1 would be useless.
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
            // Bare ↑/↓ only. Inside a text field ⇧↑/⇧↓ extend the selection, which is the standard
            // macOS gesture and belongs to the field editor; `onKeyPress(keys:)` does not match a
            // modified key anyway, so they are left alone on purpose rather than by accident.
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                adjust(by: press.key == .upArrow ? step : -step)
                return .handled
            }
    }

    private func adjust(by amount: Double) {
        let moved = value + amount
        value = range.map { min(max(moved, $0.lowerBound), $0.upperBound) } ?? moved
    }
}
