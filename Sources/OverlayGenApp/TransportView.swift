import SwiftUI
import TelemetryKit

struct TransportView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                editor.seek(to: 0)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            Button {
                editor.step(by: -1)
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            Button {
                editor.togglePlayback()
            } label: {
                Image(systemName: editor.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            Button {
                editor.step(by: 1)
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            Text(TimeParsing.lapTimeString(editor.currentTime)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Slider(
                value: Binding(get: { editor.currentTime }, set: { editor.seek(to: $0) }),
                in: 0...max(editor.duration, 0.001)
            )
            Text(TimeParsing.lapTimeString(editor.duration)).monospacedDigit().foregroundStyle(.secondary).frame(
                width: 80, alignment: .leading)
            Divider().frame(height: 16)
            Button {
                editor.snappingEnabled.toggle()
            } label: {
                Image(systemName: "line.diagonal.arrow").symbolVariant(editor.snappingEnabled ? .fill : .none)
                    .foregroundStyle(editor.snappingEnabled ? Color.accentColor : Color.secondary)
            }
            .help("Snapping (N): drags stick to clip edges and the playhead")
            .keyboardShortcut("n", modifiers: [])
            Button {
                editor.zoomTimeline(by: 1 / 1.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out (⌘−)")
            Slider(
                value: Binding(get: { log2(editor.timelineZoom) }, set: { editor.timelineZoom = pow(2, $0) }), in: 0...6
            )
            .frame(width: 90)
            .help("Timeline zoom")
            Button {
                editor.zoomTimeline(by: 1.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in (⌘=)")
            Button {
                editor.fitTimeline()
            } label: {
                Image(systemName: "arrow.left.and.right.square")
            }
            .help("Zoom to fit (⇧Z)").disabled(editor.timelineZoom == 1)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(editor.project.videoInputs.isEmpty)
    }
}
