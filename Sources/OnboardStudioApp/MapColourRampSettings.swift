import ProjectModel
import SwiftUI

/// Settings ▸ Maps (#561): the colours every Track Map paints a channel in, lowest to highest.
/// One ramp for every map, so a colour means the same thing in every project.
struct MapColourRampSettings: View {
    @AppStorage(Preferences.mapColorRamp.key) private var rampText = Preferences.mapColorRamp.unset

    private var ramp: ColorRamp { ColorRamp(preferenceText: rampText) }

    var body: some View {
        Section {
            LabeledContent("Channel colours") {
                HStack(spacing: 6) {
                    ForEach(ramp.stops.indices, id: \.self) { index in
                        ColorPicker(name(of: index), selection: stop(index), supportsOpacity: false)
                            .labelsHidden()
                            .help("The colour of a channel's \(name(of: index).lowercased()) values")
                            .accessibilityLabel("\(name(of: index)) Colour")
                            .accessibilityIdentifier("settings.mapRamp.\(index)")
                    }
                }
            }
            LabeledContent("Preview") {
                LinearGradient(colors: ramp.stops.map { Color($0) }, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 160, height: 10)
                    .clipShape(.rect(cornerRadius: 3))
                    .accessibilityHidden(true)
            }
            Button("Restore Default Colours") { rampText = Preferences.mapColorRamp.unset }
                .disabled(ramp == .standard)
                .accessibilityIdentifier("settings.mapRamp.restore")
        } header: {
            Text("Maps")
        } footer: {
            Text(
                "A Track Map coloured by a channel paints the lap being driven from the lowest of the "
                    + "session's values, on the left, to the highest, on the right. Every map uses these colours."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// "Lowest", "Low", "High", "Highest" for the standard four; by number for any other count.
    private func name(of index: Int) -> String {
        let count = ramp.stops.count
        if index == 0 { return "Lowest" }
        if index == count - 1 { return "Highest" }
        if count == 4 { return index == 1 ? "Low" : "High" }
        return "Middle \(index)"
    }

    private func stop(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(ramp.stops[index]) },
            set: { colour in
                var stops = ramp.stops
                stops[index] = RGBAColor(colour)
                let changed = ColorRamp(stops: stops)
                // The standard ramp is kept as no setting at all, so a later build's better default reaches it.
                rampText = changed == .standard ? Preferences.mapColorRamp.unset : changed.preferenceText
            })
    }
}
