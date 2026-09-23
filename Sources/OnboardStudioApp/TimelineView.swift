import ProjectModel
import SwiftUI
import TelemetryKit

/// The timeline under the transport: a time ruler, a lane per video (drag to move, drag an edge
/// to trim, click to select) and the segment lane. Zooms horizontally (⌘= / ⌘− / ⇧Z, or the
/// slider next to the transport) and scrolls; a magnet toggle snaps drags to clip edges and the
/// playhead, as in DaVinci Resolve.
struct TimelineView: View {
    @Bindable var editor: EditorModel
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    var body: some View {
        GeometryReader { geometry in
            let viewWidth = max(geometry.size.width, 1)
            let contentWidth = viewWidth * editor.timelineZoom
            VStack(spacing: 0) {
                TimelineOverview(
                    editor: editor, visibleFraction: 1 / editor.timelineZoom,
                    scrollTo: { fraction in scrollPosition.scrollTo(x: fraction * contentWidth) })
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        TimelineRuler(editor: editor, width: contentWidth)
                        Divider()
                        MarkerLaneView(editor: editor, width: contentWidth)
                        Divider()
                        if !editor.project.videoInputs.isEmpty {
                            VideoLaneView(editor: editor, width: contentWidth)
                            Divider()
                        }
                        if !editor.project.dataInputs.isEmpty {
                            DataLaneView(editor: editor, width: contentWidth)
                            Divider()
                        }
                        if !editor.project.timeline.segments.isEmpty {
                            SegmentLaneView(editor: editor, width: contentWidth)
                        }
                    }
                    .frame(width: contentWidth)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x / max(geometry.contentSize.width, 1)
                } action: { _, fraction in
                    editor.timelineScrollFraction = min(max(fraction, 0), 1)
                }
            }
        }
        // Every lane that can be absent is subtracted here as well as skipped above. Hiding the
        // segment lane while still reserving its height would leave the empty grey strip #105 is
        // about, only without the label on it.
        .frame(
            height: MarkerLaneView.height + 1
                + (editor.project.dataInputs.isEmpty ? 0 : DataLaneView.height + 1)
                + (editor.project.timeline.segments.isEmpty ? 0 : SegmentLaneView.height)
                + (editor.project.videoInputs.isEmpty ? 12 + 18 + 3 : 12 + 18 + 26 + 4))
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
///
/// Shown only once a project has a segment, like the video and data lanes above it. A project with
/// none used to get a full-width grey bar labelled "Start" — the stretch before the first segment,
/// stretched over a timeline that had no first segment to be before (#105). Nothing is lost by
/// hiding it: **Add Segment at Playhead** is on the layout toolbar menu and in the menu bar, not
/// only in this lane's context menu.
struct SegmentLaneView: View {
    @Bindable var editor: EditorModel
    let width: CGFloat
    @State private var dragging: (id: SegmentID, start: Double)?

    /// Not private: `TimelineView` subtracts it when this lane is not shown.
    static let height: CGFloat = 34

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let segments = editor.project.timeline.segments
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            // The stretch before the first segment, where the project's own layout is what draws.
            // Only when there is one: a segment starting at zero leaves nothing in front of it,
            // and a two-pixel sliver with a clipped label is not a label.
            let firstStart = segments.first?.start ?? 0
            if firstStart > 0 {
                span(label: "Start", x: 0, width: width * firstStart / duration, selected: false, color: .secondary)
            }
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
                Rectangle().fill(Color.clear).frame(width: 10, height: Self.height).contentShape(Rectangle())
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
            Rectangle().fill(Color.red).frame(width: 1, height: Self.height)
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
        .frame(width: width, height: Self.height)
        .disabled(editor.project.videoInputs.isEmpty)
    }

    private func span(label: String, x: CGFloat, width: CGFloat, selected: Bool, color: Color) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(selected ? 0.55 : 0.25))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(selected ? 1 : 0.5), lineWidth: 1))
            Text(label).font(.caption).lineLimit(1).padding(.horizontal, 6)
        }
        .frame(width: max(width - 2, 2), height: Self.height - 8)
        .offset(x: x + 1, y: 4)
    }
}

/// One bar per video input. Drag the body to move the video (snapping), drag either edge to trim
/// it (the head trim keeps the picture in place, as an editor's ripple-free trim does), click to
/// select it. A click anywhere in the lane also puts the playhead there, as in every editor (#106).
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
                .contentShape(Rectangle())
                .onTapGesture { location in editor.seek(to: location.x / pixelsPerSecond) }
            ForEach(editor.project.videoInputs) { video in
                let live = drag?.id == video.id ? drag : nil
                // `startInProject`, not the raw offset: a clip nudged before the project's start
                // renders from zero with its head dropped, and the bar has to show that rather
                // than hanging off the left edge claiming length it will not have.
                let offset = live?.offset ?? video.sync.startInProject
                let length = live?.length ?? max(0, (editor.end(of: video) ?? offset) - offset)
                let selected = editor.selectedInputID == video.id && editor.selectedObjectID == nil
                bar(
                    video, selected: selected, width: max(length * pixelsPerSecond - 2, 6),
                    pixelsPerSecond: pixelsPerSecond
                )
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

    private func bar(_ video: Input, selected: Bool, width: CGFloat, pixelsPerSecond: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.purple.opacity(selected ? 0.6 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4).stroke(Color.purple.opacity(selected ? 1 : 0.5), lineWidth: 1))
            chapterMarks(video, selected: selected, pixelsPerSecond: pixelsPerSecond)
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

    /// Seams between the files of a joined recording, and the stopped-camera gaps between them.
    ///
    /// One unbroken bar for what were several files is correct but surprising, so the joins are
    /// drawn. Positions come from the input's media timeline and are mapped through the same
    /// trim, start position and play speed the bar's own length uses.
    @ViewBuilder
    private func chapterMarks(_ video: Input, selected: Bool, pixelsPerSecond: CGFloat) -> some View {
        let chapters = editor.chapters(of: video.id)
        if chapters.count > 1, case .video(let settings) = video.kind {
            let start = max(settings.trim.start ?? 0, video.sync.startPositionInInput)
            let speed = max(video.sync.playSpeed, 0.001)
            let x = { (mediaTime: Double) in CGFloat((mediaTime - start) / speed) * pixelsPerSecond }
            ForEach(chapters.dropFirst()) { chapter in
                // A gap is time the camera was stopped: real elapsed time, drawn as a break in
                // the bar rather than silently closed up.
                if chapter.gapBefore > 0 {
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                        .frame(width: max(x(chapter.start) - x(chapter.start - chapter.gapBefore), 1))
                        .offset(x: x(chapter.start - chapter.gapBefore))
                }
                Rectangle().fill(Color.white.opacity(selected ? 0.9 : 0.55))
                    .frame(width: 1)
                    .offset(x: x(chapter.start))
            }
            .allowsHitTesting(false)
        }
    }

    private func dragGesture(for video: Input, pixelsPerSecond: CGFloat, barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // The same clamped start the bar is drawn from. Dragging from the raw offset while
                // drawing from the clamped one puts them exactly `-offsetInProject` apart: a body
                // drag would do nothing until the pointer had travelled that far, and a tail drag
                // would resize the bar the moment it began.
                let start = video.sync.startInProject
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
                guard let drag, drag.id == video.id, abs(value.translation.width) >= 2 else {
                    // A click rather than a drag: the playhead goes where it landed (#106).
                    editor.seek(to: video.sync.startInProject + value.startLocation.x / pixelsPerSecond)
                    return
                }
                switch drag.edge {
                case .body: editor.setOffset(of: video.id, to: drag.offset)
                case .head: editor.trimHead(of: video.id, toProjectTime: drag.offset)
                case .tail: editor.trimTail(of: video.id, toProjectTime: drag.offset + drag.length)
                }
            }
    }
}

/// Markers above the lanes: a flag for a point, a bar for a range. Click one to go to it.
///
/// Markers belonging to an input are drawn in the input's colour-neutral shape at the place its
/// sync puts them, so re-syncing an input visibly carries its marks along with it.
struct MarkerLaneView: View {
    @Bindable var editor: EditorModel
    let width: CGFloat

    static let height: CGFloat = 14

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let pixelsPerSecond = width / duration
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            ForEach(editor.markersInProjectTime) { placed in
                let selected = editor.selectedMarkerID == placed.marker.id
                let colour = Color(placed.marker.colour)
                Group {
                    if placed.marker.isRange {
                        RoundedRectangle(cornerRadius: 2).fill(colour.opacity(selected ? 0.9 : 0.55))
                            .frame(width: max((placed.end - placed.start) * pixelsPerSecond, 3))
                    } else {
                        // A flag: narrow, and wide enough to hit.
                        RoundedRectangle(cornerRadius: 1).fill(colour.opacity(selected ? 1 : 0.75))
                            .frame(width: 3)
                    }
                }
                .frame(height: Self.height - 4)
                .overlay(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.8), lineWidth: 1)
                    }
                }
                .offset(x: placed.start * pixelsPerSecond, y: 2)
                .help(placed.marker.name.isEmpty ? "Marker" : placed.marker.name)
                .accessibilityIdentifier("marker.\(placed.marker.name)")
                .onTapGesture { editor.select(marker: placed.marker.id, seekTo: placed.start) }
            }
            Rectangle().fill(Color.red).frame(width: 1, height: Self.height)
                .offset(x: min(editor.currentTime, duration) * pixelsPerSecond)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: Self.height)
    }
}

/// A bar per data input with its laps marked out.
///
/// Data files had no bar at all, so there was nothing to say where the session sits against the
/// video, or where the laps fall. Lap boundaries come from the session and are mapped through the
/// input's sync, so re-syncing the data slides its laps with it.
struct DataLaneView: View {
    @Bindable var editor: EditorModel
    let width: CGFloat

    static let height: CGFloat = 22

    var body: some View {
        let duration = max(editor.timelineDuration, 0.001)
        let pixelsPerSecond = width / duration
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                .contentShape(Rectangle())
                .onTapGesture { location in editor.seek(to: location.x / pixelsPerSecond) }
            ForEach(editor.project.dataInputs) { data in
                let laps = editor.laps(of: data)
                let span = editor.dataSpan(of: data)
                let selected = editor.selectedInputID == data.id && editor.selectedObjectID == nil
                bar(data, laps: laps, selected: selected, pixelsPerSecond: pixelsPerSecond)
                    .frame(width: max((span.end - span.start) * pixelsPerSecond - 2, 6))
                    .offset(x: span.start * pixelsPerSecond + 1, y: 3)
                    .onTapGesture { location in
                        editor.selectedInputID = data.id
                        editor.selectedObjectID = nil
                        editor.selectedSegmentID = nil
                        editor.selectedMarkerID = nil
                        editor.seek(to: span.start + location.x / pixelsPerSecond)
                    }
            }
            Rectangle().fill(Color.red).frame(width: 1, height: Self.height)
                .offset(x: min(editor.currentTime, duration) * pixelsPerSecond)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: Self.height)
    }

    private func bar(_ data: Input, laps: [PlacedLap], selected: Bool, pixelsPerSecond: CGFloat) -> some View {
        let start = laps.first.map { _ in editor.dataSpan(of: data).start } ?? 0
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(selected ? 0.55 : 0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 4).stroke(Color.teal.opacity(selected ? 1 : 0.5), lineWidth: 1))
            // A divider where each lap begins, with its number when there is room for it.
            ForEach(laps) { placed in
                let x = (placed.start - start) * pixelsPerSecond
                Rectangle().fill(Color.white.opacity(selected ? 0.9 : 0.6)).frame(width: 1)
                    .offset(x: x)
                if let end = placed.end, (end - placed.start) * pixelsPerSecond > 22 {
                    Text("\(placed.lap.number)")
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .offset(x: x + 3, y: 0)
                }
            }
            Text(data.label).font(.caption).lineLimit(1).padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        }
        .frame(height: Self.height - 6)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .help(laps.isEmpty ? data.label : "\(data.label) — \(laps.count) laps")
    }
}
