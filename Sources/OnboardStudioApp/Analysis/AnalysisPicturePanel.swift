import AVKit
import SwiftUI
import TelemetryKit

/// The picture of one chosen lap at the cursor (#556), the project's own or the day's clip; Play
/// runs it from there with the cursor following round every trace.
struct AnalysisPicturePanel: View {
    @Bindable var model: LapAnalysisModel
    let analysis: LapAnalysis
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VideoPlayer(player: model.picture.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Picture of \(label)")
                .accessibilityIdentifier("analysis.picture")
            HStack(spacing: 8) {
                Button(model.picture.isPlaying ? "Pause" : "Play") {
                    if model.picture.isPlaying { model.picture.stop() } else { model.playPicture() }
                }
                .help("Play this lap's picture from the cursor, the cursor following it")
                .accessibilityIdentifier("analysis.picture.play")
                if model.footage.count > 1 {
                    // A closure, not `model.showPicture(of:)` itself: handed over as a method, the
                    // setter needed a thunk that crashed the compiler in CodeQL's build (#639).
                    Picker(
                        "Picture of",
                        selection: Binding(get: { model.picture.trace }, set: { model.showPicture(of: $0) })
                    ) {
                        ForEach(analysis.traces.filter { model.footage[$0.id] != nil }) { trace in
                            Text(trace.label).tag(trace.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Whose picture to show")
                    .accessibilityIdentifier("analysis.picture.lap")
                } else {
                    Circle().fill(colors[model.picture.trace % colors.count]).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(label).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onAppear(perform: model.showPicture)
        .onDisappear { model.picture.stop() }
    }

    private var label: String {
        analysis.traces.first { $0.id == model.picture.trace }?.label ?? ""
    }
}
