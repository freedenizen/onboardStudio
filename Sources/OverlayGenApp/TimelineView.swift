import ProjectModel
import SwiftUI
import TelemetryKit

/// A strip under the transport showing timeline segments. Click to seek, click a segment's
/// header to select it, drag a segment's left edge to move it (later segments follow).
struct TimelineView: View {
    @Bindable var editor: EditorModel
    @State private var dragging: (id: SegmentID, start: Double)?

    private let height: CGFloat = 34

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let duration = max(editor.duration, 0.001)
            let segments = editor.project.timeline.segments
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                // Base span (before the first segment).
                let firstStart = segments.first?.start ?? duration
                span(label: "Start", x: 0, width: width * firstStart / duration, selected: false, color: .secondary)
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let start = dragging?.id == segment.id ? (dragging?.start ?? segment.start) : segment.start
                    let end = index + 1 < segments.count ? segments[index + 1].start : duration
                    let x = width * start / duration
                    span(
                        label: segment.label.isEmpty ? "Segment \(index + 1)" : segment.label, x: x,
                        width: max(2, width * (end - start) / duration),
                        selected: editor.selectedSegmentID == segment.id,
                        color: .accentColor
                    )
                    .onTapGesture(coordinateSpace: .named("timeline")) { location in
                        editor.selectedSegmentID = segment.id
                        editor.selectedObjectID = nil
                        editor.selectedInputID = nil
                        editor.seek(to: min(max(0, location.x / width * duration), duration))
                    }
                    // Drag handle on the segment's left edge.
                    Rectangle().fill(Color.clear).frame(width: 10, height: height).contentShape(Rectangle())
                        .offset(x: x - 5)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let t = min(max(0, (x + value.translation.width) / width * duration), duration)
                                    dragging = (segment.id, t)
                                }
                                .onEnded { value in
                                    let t = min(max(0, (x + value.translation.width) / width * duration), duration)
                                    dragging = nil
                                    editor.shiftSegment(segment.id, to: t)
                                }
                        )
                        .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                }
                // Playhead.
                Rectangle().fill(Color.white).frame(width: 1, height: height)
                    .offset(x: width * min(editor.currentTime, duration) / duration)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(name: "timeline")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    // A plain click seeks; segment taps are handled above.
                    if abs(value.translation.width) < 2 {
                        editor.seek(to: value.location.x / width * duration)
                    }
                }
            )
            .contextMenu {
                Button("Add Segment at Playhead") { editor.addSegmentAtPlayhead() }
                if let id = editor.selectedSegmentID {
                    Button("Delete Selected Segment") { editor.deleteSegment(id) }
                }
            }
        }
        .frame(height: height)
        .disabled(editor.project.videoInputs.isEmpty)
    }

    private func span(label: String, x: CGFloat, width: CGFloat, selected: Bool, color: Color) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(selected ? 0.55 : 0.25))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(selected ? 1 : 0.5), lineWidth: 1))
            Text(label).font(.caption).lineLimit(1).padding(.horizontal, 6)
        }
        .frame(width: max(width - 2, 2), height: height - 8)
        .offset(x: x + 1, y: 4)
    }
}
