import ProjectModel
import SwiftUI
import TelemetryKit

/// The timeline under the transport: a time ruler, a lane per video (drag to move, drag an edge
/// to trim, click to select) and the segment lane. Zooms horizontally (⌘= / ⌘− / ⇧Z, or the
/// slider next to the transport) and scrolls; a magnet toggle snaps drags to clip edges and the
/// playhead, as in DaVinci Resolve.
struct TimelineView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        GeometryReader { geometry in
            let viewWidth = max(geometry.size.width, 1)
            let contentWidth = viewWidth * editor.timelineZoom
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    TimelineRuler(editor: editor, width: contentWidth)
                    Divider()
                    if !editor.project.videoInputs.isEmpty {
                        VideoLaneView(editor: editor, width: contentWidth)
                        Divider()
                    }
                    SegmentLaneView(editor: editor, width: contentWidth)
                }
                .frame(width: contentWidth)
            }
        }
        .frame(height: editor.project.videoInputs.isEmpty ? 18 + 34 + 2 : 18 + 26 + 34 + 3)
    }
}

/// Time labels at a sensible spacing for the current zoom, with the playhead; click to seek.
struct TimelineRuler: View {
    @Bindable var editor: EditorModel
    let width: CGFloat

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let pixelsPerSecond = width / duration
        let step = Self.labelStep(pixelsPerSecond: pixelsPerSecond)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .underPageBackgroundColor))
            ForEach(Array(stride(from: 0.0, through: duration, by: step)), id: \.self) { t in
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.label(t)).font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 3)
                    Spacer(minLength: 0)
                }
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 1, height: 6)
                }
                .frame(width: max(step * pixelsPerSecond, 1), height: 18, alignment: .topLeading)
                .offset(x: t * pixelsPerSecond)
            }
            Rectangle().fill(Color.red).frame(width: 1, height: 18)
                .offset(x: min(editor.currentTime, duration) * pixelsPerSecond)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                editor.seek(to: min(max(0, value.location.x / pixelsPerSecond), editor.duration))
            }
        )
    }

    /// The smallest "nice" interval that keeps labels at least 70 pt apart.
    static func labelStep(pixelsPerSecond: CGFloat) -> Double {
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        return candidates.first { $0 * pixelsPerSecond >= 70 } ?? 3600
    }

    static func label(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let fraction = seconds - Double(total)
        if abs(fraction) > 0.01 { return String(format: "%d:%04.1f", total / 60, seconds - Double(total / 60 * 60)) }
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Timeline segments: click to seek, click a segment to select it, drag its left edge to move it.
struct SegmentLaneView: View {
    @Bindable var editor: EditorModel
    let width: CGFloat
    @State private var dragging: (id: SegmentID, start: Double)?

    private let height: CGFloat = 34

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let segments = editor.project.timeline.segments
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            let firstStart = segments.first?.start ?? duration
            span(label: "Start", x: 0, width: width * firstStart / duration, selected: false, color: .secondary)
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let start = dragging?.id == segment.id ? (dragging?.start ?? segment.start) : segment.start
                let end = index + 1 < segments.count ? segments[index + 1].start : duration
                let x = width * start / duration
                span(
                    label: segment.label.isEmpty ? "Segment \(index + 1)" : segment.label, x: x,
                    width: max(2, width * (end - start) / duration),
                    selected: editor.selectedSegmentID == segment.id, color: .accentColor
                )
                .onTapGesture(coordinateSpace: .named("segments")) { location in
                    editor.selectedSegmentID = segment.id
                    editor.selectedObjectID = nil
                    editor.selectedInputID = nil
                    editor.seek(to: min(max(0, location.x / width * duration), duration))
                }
                Rectangle().fill(Color.clear).frame(width: 10, height: height).contentShape(Rectangle())
                    .offset(x: x - 5)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let t = editor.snapped(
                                    min(max(0, (x + value.translation.width) / width * duration), duration))
                                dragging = (segment.id, t)
                            }
                            .onEnded { value in
                                let t = editor.snapped(
                                    min(max(0, (x + value.translation.width) / width * duration), duration))
                                dragging = nil
                                editor.shiftSegment(segment.id, to: t)
                            }
                    )
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            }
            Rectangle().fill(Color.red).frame(width: 1, height: height)
                .offset(x: width * min(editor.currentTime, duration) / duration)
                .allowsHitTesting(false)
        }
        .coordinateSpace(name: "segments")
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                if abs(value.translation.width) < 2 { editor.seek(to: value.location.x / width * duration) }
            }
        )
        .contextMenu {
            Button("Add Segment at Playhead") { editor.addSegmentAtPlayhead() }
            if let id = editor.selectedSegmentID {
                Button("Delete Selected Segment") { editor.deleteSegment(id) }
            }
        }
        .frame(width: width, height: height)
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

/// One bar per video input. Drag the body to move the video (snapping), drag either edge to trim
/// it (the head trim keeps the picture in place, as an editor's ripple-free trim does), click to
/// select it.
struct VideoLaneView: View {
    @Bindable var editor: EditorModel
    let width: CGFloat

    enum Edge {
        case body, head, tail
    }

    struct Drag {
        let id: InputID
        let edge: Edge
        var offset: Double
        var length: Double
    }

    @State private var drag: Drag?
    private let height: CGFloat = 26
    private let handle: CGFloat = 8

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let pixelsPerSecond = width / duration
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            ForEach(editor.project.videoInputs) { video in
                let live = drag?.id == video.id ? drag : nil
                let offset = live?.offset ?? video.sync.offsetInProject
                let length = live?.length ?? max(0, (editor.end(of: video) ?? offset) - video.sync.offsetInProject)
                let selected = editor.selectedInputID == video.id && editor.selectedObjectID == nil
                bar(video, selected: selected, width: max(length * pixelsPerSecond - 2, 6))
                    .offset(x: offset * pixelsPerSecond + 1, y: 3)
                    .gesture(
                        dragGesture(for: video, pixelsPerSecond: pixelsPerSecond, barWidth: length * pixelsPerSecond))
            }
            Rectangle().fill(Color.red).frame(width: 1, height: height)
                .offset(x: min(editor.currentTime, duration) * pixelsPerSecond)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
    }

    private func bar(_ video: Input, selected: Bool, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.purple.opacity(selected ? 0.6 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4).stroke(Color.purple.opacity(selected ? 1 : 0.5), lineWidth: 1))
            HStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(selected ? 0.5 : 0.25)).frame(width: 3)
                Text(video.label).font(.caption).lineLimit(1).padding(.horizontal, 5)
                Spacer(minLength: 0)
                Rectangle().fill(Color.white.opacity(selected ? 0.5 : 0.25)).frame(width: 3)
            }
            .padding(.vertical, 3)
        }
        .frame(width: width, height: height - 6)
        .contentShape(Rectangle())
    }

    private func dragGesture(for video: Input, pixelsPerSecond: CGFloat, barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = video.sync.offsetInProject
                let length = max(0, (editor.end(of: video) ?? start) - start)
                let edge: Edge =
                    drag?.edge
                    ?? (value.startLocation.x < handle
                        ? .head : value.startLocation.x > barWidth - handle ? .tail : .body)
                guard abs(value.translation.width) >= 2 || drag != nil else { return }
                let delta = value.translation.width / pixelsPerSecond
                switch edge {
                case .body:
                    let raw = max(0, start + delta)
                    drag = Drag(
                        id: video.id, edge: .body,
                        offset: editor.snappedSpan(start: raw, length: length, excluding: video.id), length: length)
                case .head:
                    let newStart = editor.snapped(min(max(0, start + delta), start + length - 0.1), excluding: video.id)
                    drag = Drag(id: video.id, edge: .head, offset: newStart, length: length - (newStart - start))
                case .tail:
                    let newEnd = editor.snapped(max(start + 0.1, start + length + delta), excluding: video.id)
                    drag = Drag(id: video.id, edge: .tail, offset: start, length: newEnd - start)
                }
            }
            .onEnded { value in
                defer { drag = nil }
                editor.selectedInputID = video.id
                editor.selectedObjectID = nil
                editor.selectedSegmentID = nil
                guard let drag, drag.id == video.id, abs(value.translation.width) >= 2 else { return }
                switch drag.edge {
                case .body: editor.setOffset(of: video.id, to: drag.offset)
                case .head: editor.trimHead(of: video.id, toProjectTime: drag.offset)
                case .tail: editor.trimTail(of: video.id, toProjectTime: drag.offset + drag.length)
                }
            }
    }
}
