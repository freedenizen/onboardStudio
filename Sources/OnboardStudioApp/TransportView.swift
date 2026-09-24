import SwiftUI
import TelemetryKit

struct TransportView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                editor.seek(to: 0)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .help("Go to start (Home)")
            .accessibilityIdentifier("transport.start").accessibilityLabel("Go to start")
            Button {
                editor.step(by: -1)
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            .help("Step back one frame (,)")
            .accessibilityIdentifier("transport.stepBack").accessibilityLabel("Step back one frame")
            Button {
                editor.togglePlayback()
            } label: {
                Image(systemName: editor.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(editor.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityIdentifier("transport.play").accessibilityLabel(editor.isPlaying ? "Pause" : "Play")
            Button {
                editor.step(by: 1)
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .help("Step forward one frame (.)")
            .accessibilityIdentifier("transport.stepForward").accessibilityLabel("Step forward one frame")
            TransportClock(editor: editor)
            Text(TimeParsing.lapTimeString(editor.duration)).monospacedDigit().foregroundStyle(.secondary).frame(
                width: 66, alignment: .leading
            )
            .accessibilityLabel("Length")
            .accessibilityValue(TimeParsing.lapTimeString(editor.duration))
            Divider().frame(height: 16)
            Button {
                editor.snappingEnabled.toggle()
            } label: {
                Image(systemName: "line.diagonal.arrow").symbolVariant(editor.snappingEnabled ? .fill : .none)
                    .foregroundStyle(editor.snappingEnabled ? Color.accentColor : Color.secondary)
            }
            .help("Snapping (N): drags stick to clip edges and the playhead")
            .keyboardShortcut("n", modifiers: [])
            .accessibilityIdentifier("transport.snap").accessibilityLabel("Snapping")
            Button {
                editor.zoomTimeline(by: 1 / 1.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out (⌘−)")
            .accessibilityIdentifier("transport.zoomOut").accessibilityLabel("Zoom out")
            Slider(
                value: Binding(get: { log2(editor.timelineZoom) }, set: { editor.timelineZoom = pow(2, $0) }), in: 0...6
            )
            .frame(width: 70)
            .help("Timeline zoom")
            .accessibilityLabel("Timeline Zoom")
            .accessibilityIdentifier("transport.zoom")
            Button {
                editor.zoomTimeline(by: 1.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in (⌘=)")
            .accessibilityIdentifier("transport.zoomIn").accessibilityLabel("Zoom in")
            Button {
                editor.fitTimeline()
            } label: {
                Image(systemName: "arrow.left.and.right.square")
            }
            .help("Zoom to fit (⇧Z)").disabled(editor.timelineZoom == 1)
            .accessibilityIdentifier("transport.fit").accessibilityLabel("Zoom to fit")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(editor.project.videoInputs.isEmpty)
    }
}

/// The time and position slider: a view of their own so that they are all the transport redraws
/// on each tick of playback (#279).
struct TransportClock: View {
    let editor: EditorModel

    var body: some View {
        Text(TimeParsing.lapTimeString(editor.currentTime)).monospacedDigit().frame(width: 66, alignment: .trailing)
            .accessibilityIdentifier("transport.time").accessibilityLabel("Playhead")
            .accessibilityValue(TimeParsing.lapTimeString(editor.currentTime))
        Slider(
            value: Binding(get: { editor.currentTime }, set: { editor.seek(to: $0) }),
            in: 0...max(editor.duration, 0.001)
        )
        .frame(minWidth: 60)
        .accessibilityLabel("Position")
        .accessibilityIdentifier("transport.position")
    }
}
