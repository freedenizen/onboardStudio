import MediaKit
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
    /// Looked up when the section is drawn, so installing Gyroflow while the app is open is noticed.
    var gyroflowInstalled: Bool { Gyroflow.executable() != nil }
    var jobs: StabilisationJobs { .shared }
    /// With Gyroflow: whether a steadied copy of every file of the video is there to show.
    var copiesReady: Bool {
        let files = settings.stabilisation.gyroflowFiles
        return files.count == settings.clips.count + 1
            && files.allSatisfy { FileManager.default.fileExists(atPath: editor.location.resolve($0).path) }
    }

    var body: some View {
        Section("Stabilisation") {
            Picker("Steady", selection: method) {
                ForEach(StabilisationSettings.Method.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            // Always open: choosing what this video or this Mac lacks says what it needs.
            .accessibilityIdentifier("stabilisation.method")
            if settings.stabilisation.method == .gyroflow {
                gyroflowControls
            }
            if settings.stabilisation.method == .picture, !pictureMeasured {
                measureControls
            } else if settings.stabilisation.method == .motionData || settings.stabilisation.method == .picture {
                SliderField(
                    "Smoothing", value: field(\.smoothing, name: "Change Smoothing"),
                    in: StabilisationSettings.smoothingRange, step: 0.1, scale: .plain(fractionDigits: 1), unit: "s",
                    minimumLabel: "Follow", maximumLabel: "Float"
                )
                .help("How long the steadied view takes to follow the camera: short keeps more of the movement")
                SliderField(
                    "Zoom", value: field(\.zoom, name: "Change Stabilisation Zoom"),
                    in: StabilisationSettings.zoomRange, step: 0.01, scale: .percentAboveOne, unit: "%"
                )
                .help(
                    "How much the picture is enlarged to hide the edges moved into view; also how far a frame can move")
            }
            Text(explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var pictureMeasured: Bool { editor.loaded?.pictureMotions[input.id] != nil }

    /// Measure the picture's movement, or follow the measuring.
    @ViewBuilder var measureControls: some View {
        if let job = jobs.job(for: input.id), job.task != nil {
            ProgressView(value: job.progress) { Text("Measuring the picture's movement…") }
                .accessibilityIdentifier("stabilisation.measureProgress")
            Button("Cancel") { jobs.cancel(input.id) }
        } else {
            Button("Measure Motion") { jobs.measure(input, in: editor) }
                .help("Measure how the picture moves, frame by frame, to steady it; done once per video")
                .accessibilityIdentifier("stabilisation.measure")
        }
        if let failure = jobs.job(for: input.id)?.failure {
            Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Make the copies, follow the render, or say what is shown.
    @ViewBuilder var gyroflowControls: some View {
        if let job = jobs.job(for: input.id), job.task != nil {
            ProgressView(value: job.progress) { Text("Stabilising with Gyroflow…") }
                .accessibilityIdentifier("stabilisation.gyroflowProgress")
            Button("Cancel") { jobs.cancel(input.id) }
        } else if !gyroflowInstalled {
            Button("How to Install Gyroflow") { HelpLinks.open(.userGuide, section: "with-gyroflow") }
                .help("Open the user guide at the steps for installing Gyroflow")
                .accessibilityIdentifier("stabilisation.gyroflowHelp")
        } else {
            Button(copiesReady ? "Stabilise Again" : "Stabilise with Gyroflow") { jobs.stabilise(input, in: editor) }
                .help("Make a steadied copy of this video with Gyroflow; the recording itself is not changed")
                .accessibilityIdentifier("stabilisation.gyroflowStart")
        }
        if let failure = jobs.job(for: input.id)?.failure {
            Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
        }
    }

    var explanation: String {
        if settings.stabilisation.method == .gyroflow {
            if !gyroflowInstalled {
                return "Gyroflow is not installed. It is free: install it with “brew install --cask gyroflow” in "
                    + "Terminal, or from gyroflow.xyz, and open it once."
            }
            if copiesReady {
                return "Showing Gyroflow's steadied copy. Sync, GPS and telemetry still come from the recording."
            }
            return "Gyroflow makes a steadied copy of the picture beside the recording, which is left as it is. "
                + "Until it is made, the recording is shown."
        }
        if settings.stabilisation.method == .picture {
            return pictureMeasured
                ? "Steadied from the picture's own movement. Blur, darkness or a picture with little in it make "
                    + "this weaker than motion data; use that when the camera records it."
                : "Onboard Studio measures how the picture moves, frame by frame — once, for any camera — and "
                    + "steadies it from that. Until it is measured, the recording is shown."
        }
        if settings.stabilisation.method == .motionData, !hasMotionData {
            return "This video has no camera motion record, so it is shown as recorded. GoPro HERO8 and later "
                + "record one with every video; for others, try With Gyroflow."
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
