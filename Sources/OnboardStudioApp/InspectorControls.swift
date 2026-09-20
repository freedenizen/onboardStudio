import SwiftUI

/// Small controls shared by the inspector panels.

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let fractionDigits: ClosedRange<Int>

    init(_ title: String, value: Binding<Double>, fractionDigits: ClosedRange<Int> = 0...3) {
        self.title = title
        _value = value
        self.fractionDigits = fractionDigits
    }

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(fractionDigits)))
    }
}
