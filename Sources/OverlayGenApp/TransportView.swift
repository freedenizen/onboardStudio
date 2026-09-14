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
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(editor.project.videoInputs.isEmpty)
    }
}
