import ProjectModel
import SwiftUI

/// Video input ▸ Stabilisation (#262): steadies a shaky picture — helmet footage above all — from the
/// orientation the camera recorded with it.
struct StabilisationSection: View {
    @Bindable var editor: EditorModel
    let input: Input
    let settings: VideoInputSettings

    /// Whether the file carries the camera's motion record at all (GoPro HERO8 and later).
    var hasMotionData: Bool { editor.loaded?.mediaInfo[input.id]?.hasGPMF == true }
    var recordedWithHyperSmooth: Bool { editor.loaded?.orientations[input.id]?.stabilisedInCamera == true }

    var body: some View {
        Section("Stabilisation") {
            Picker("Steady", selection: method) {
                ForEach(StabilisationSettings.Method.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .disabled(!hasMotionData && !settings.stabilisation.isActive)
            .accessibilityIdentifier("stabilisation.method")
            if settings.stabilisation.isActive {
                Slider(
                    value: field(\.smoothing, name: "Change Smoothing"), in: StabilisationSettings.smoothingRange,
                    step: 0.1
                ) {
                    Text(
                        "Smoothing \(settings.stabilisation.smoothing, format: .number.precision(.fractionLength(1))) s"
                    )
                } minimumValueLabel: {
                    Text("Follow")
                } maximumValueLabel: {
                    Text("Float")
                }
                .help("How long the steadied view takes to follow the camera: short keeps more of the movement")
                Slider(
                    value: field(\.zoom, name: "Change Stabilisation Zoom"), in: StabilisationSettings.zoomRange,
                    step: 0.01
                ) {
                    Text("Zoom \(Int(((settings.stabilisation.zoom - 1) * 100).rounded()))%")
                }
                .help(
                    "How much the picture is enlarged to hide the edges moved into view; also how far a frame can move")
            }
            Text(explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var explanation: String {
        if !hasMotionData {
            return "This video has no camera motion record. GoPro HERO8 and later record one with every video."
        }
        if recordedWithHyperSmooth {
            return "This video was recorded with HyperSmooth, which Onboard Studio cannot yet steady further from "
                + "motion data. Gyroflow can; see the user guide."
        }
        if !settings.stabilisation.isActive {
            return "Steadies a shaky picture, such as from a helmet, using the orientation the camera recorded."
        }
        return "Each frame is moved so the camera seems to follow a smooth path; turns still come through."
    }

    var method: Binding<StabilisationSettings.Method> {
        Binding(
            get: { settings.stabilisation.method },
            set: { value in update(value == .off ? "Turn Off Stabilisation" : "Stabilise Video") { $0.method = value } }
        )
    }

    func field(_ keyPath: WritableKeyPath<StabilisationSettings, Double>, name: String) -> Binding<Double> {
        Binding(
            get: { settings.stabilisation[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func update(_ name: String, _ change: (inout StabilisationSettings) -> Void) {
        var new = settings
        change(&new.stabilisation)
        editor.updateInput(input.id, name: name) { $0.kind = .video(new) }
    }
}
