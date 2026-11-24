import SwiftUI

extension ExportSheet {
    /// The frame's width, height and rate. Each field's title is the hint inside it, which is not
    /// read out as its name: three fields in a row were "edit text" to VoiceOver (#673).
    var sizeFields: some View {
        HStack {
            TextField("Width", value: custom(\.width), format: .number)
                .accessibilityLabel("Width in Pixels")
            Text("×")
            TextField("Height", value: custom(\.height), format: .number)
                .accessibilityLabel("Height in Pixels")
            Text("px")
            TextField("fps", value: custom(\.frameRate), format: .number.precision(.fractionLength(0...2)))
                .accessibilityLabel("Frames per Second")
        }
    }
}
