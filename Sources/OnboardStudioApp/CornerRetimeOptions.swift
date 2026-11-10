import ProjectModel
import SwiftUI

/// What the Every Corner export's retime controls say (#360), kept as two switches and two values
/// so turning a switch off and on again keeps the value chosen.
struct CornerRetimeChoice: Hashable {
    var slowBraking: Bool
    var rate: Double
    var holdReference: Bool
    var holdSeconds: Double

    init(_ retime: CornerClipRetime?) {
        slowBraking = retime?.brakingRate != nil
        rate = retime?.brakingRate ?? CornerClipRetime.standard.brakingRate ?? 0.5
        holdReference = retime?.referenceHoldSeconds != nil
        holdSeconds = retime?.referenceHoldSeconds ?? CornerClipRetime.standard.referenceHoldSeconds ?? 1
    }

    /// What the clips will do, for the end of the sheet's sentence about them.
    var summary: String {
        var parts: [String] = []
        if slowBraking { parts.append("the braking zone at \(Int((rate * 100).rounded()))%") }
        if holdReference {
            let seconds = holdSeconds == 1 ? "a 1-second" : "a \(holdSeconds.formatted())-second"
            parts.append("\(seconds) hold where the reference braked")
        }
        return parts.isEmpty ? "" : ", with " + parts.joined(separator: " and ")
    }

    /// `nil` when both are off: the clips play at speed, as before #360.
    var value: CornerClipRetime? {
        guard slowBraking || holdReference else { return nil }
        return CornerClipRetime(
            brakingRate: slowBraking ? rate : nil, referenceHoldSeconds: holdReference ? holdSeconds : nil)
    }
}

/// What reading the corner files depends on, so the list is read again when it changes.
struct CornerFilesKey: Hashable {
    let onlyOpportunities: Bool
    let retime: CornerClipRetime?
}

/// Slow the braking zone; hold where the reference braked (#360).
struct CornerRetimeOptions: View {
    @Binding var choice: CornerRetimeChoice

    var body: some View {
        Toggle("Slow the braking zone", isOn: $choice.slowBraking)
            .accessibilityIdentifier("export.slowBraking")
            .help(
                "Plays each corner from its brake point to its slowest point slowly, picture and gauges alike, "
                    + "with the sound muted"
            )
        if choice.slowBraking {
            Picker("Speed", selection: $choice.rate) {
                ForEach(CornerClipRetime.rates, id: \.self) { Text("\(Int(($0 * 100).rounded()))%").tag($0) }
            }
            .accessibilityIdentifier("export.brakingRate")
        }
        Toggle("Hold where the reference braked", isOn: $choice.holdReference)
            .accessibilityIdentifier("export.holdReference")
            .help(
                "Freezes the whole frame when your lap reaches the spot where the reference lap braked, "
                    + "as a sight picture"
            )
        if choice.holdReference {
            Picker("Hold", selection: $choice.holdSeconds) {
                ForEach(CornerClipRetime.holds, id: \.self) { seconds in
                    Text(seconds == 1 ? "1 second" : "\(seconds.formatted()) seconds").tag(seconds)
                }
            }
            .accessibilityIdentifier("export.referenceHold")
        }
    }
}
