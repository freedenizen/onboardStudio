import ProjectModel
import SwiftUI
import TelemetryKit

/// The retimes (#443) under the ruler: a band for each stretch that plays at another speed,
/// labelled with its speed, and a mark for each hold. The timeline stays in project time, so
/// nothing else moves; the playhead crawls through a slowed band and stops on a hold. Click one
/// to go to it; its context menu changes or removes it.
///
/// Shown only once the project has a retime, like the segment lane.
struct RetimeLaneView: View {
    @Bindable var editor: EditorModel
    let width: CGFloat

    static let height: CGFloat = 16

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let pixelsPerSecond = width / duration
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            ForEach(editor.project.retimes) { retime in
                band(for: retime, pixelsPerSecond: pixelsPerSecond)
                    .offset(x: retime.start * pixelsPerSecond, y: 2)
                    .onTapGesture { editor.seek(to: retime.start) }
                    .contextMenu { menu(for: retime) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Self.description(of: retime))
                    .accessibilityAction { editor.seek(to: retime.start) }
                    .accessibilityAction(named: "Remove") { editor.remove(retime) }
                    .accessibilityIdentifier("retime.\(Self.title(of: retime))")
            }
            PlayheadLine(editor: editor, height: Self.height) { min($0, duration) * pixelsPerSecond }
        }
        .frame(width: width, height: Self.height)
    }

    @ViewBuilder func band(for retime: Retime, pixelsPerSecond: CGFloat) -> some View {
        let label = Text(Self.title(of: retime)).font(.caption2).foregroundStyle(.primary).lineLimit(1)
        switch retime.kind {
        case .speed(let end, _):
            RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.45))
                .frame(width: max((end - retime.start) * pixelsPerSecond, 3), height: Self.height - 4)
                .overlay(alignment: .leading) { label.padding(.leading, 4) }
                .clipped()
                .help("\(Self.description(of: retime)). Right-click to change or remove it.")
        case .hold:
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1).fill(Color.orange).frame(width: 3, height: Self.height - 4)
                label
            }
            .help("\(Self.description(of: retime)). Right-click to change or remove it.")
        }
    }

    @ViewBuilder func menu(for retime: Retime) -> some View {
        switch retime.kind {
        case .speed(_, let current):
            Picker("Speed", selection: Binding(get: { current }, set: { editor.changeSpeed(of: retime, to: $0) })) {
                ForEach(Retime.editorRates, id: \.self) { Text(Retime.percent($0)).tag($0) }
            }
            Button("Remove Speed Change") { editor.remove(retime) }
        case .hold(let seconds):
            Picker("Hold Length", selection: Binding(get: { seconds }, set: { editor.changeHold(of: retime, to: $0) }))
            {
                ForEach(Retime.editorHolds, id: \.self) { Text(Self.seconds($0)).tag($0) }
            }
            Button("Remove Hold") { editor.remove(retime) }
        }
    }

    /// "50%", "Hold 1 s".
    static func title(of retime: Retime) -> String {
        switch retime.kind {
        case .speed(_, let rate): Retime.percent(rate)
        case .hold(let seconds): Retime.holdLabel(seconds)
        }
    }

    /// "Plays at 50% from 0:10.0 to 0:14.0", "Holds for 1 s at 0:21.3", for VoiceOver and the help tag.
    static func description(of retime: Retime) -> String {
        let at = TimeParsing.lapTimeString(retime.start)
        switch retime.kind {
        case .speed(let end, let rate):
            return "Plays at \(Retime.percent(rate)) from \(at) to \(TimeParsing.lapTimeString(end))"
        case .hold(let seconds):
            return "Holds for \(Self.seconds(seconds)) at \(at)"
        }
    }

    static func seconds(_ value: Double) -> String {
        value == 1 ? "1 second" : "\(value.formatted(.number.precision(.fractionLength(0...1)))) seconds"
    }
}
