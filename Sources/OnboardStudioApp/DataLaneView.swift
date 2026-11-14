import ProjectModel
import SwiftUI
import TelemetryKit

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
                let span = editor.dataSpan(of: data)
                // The part of the file the ruler has room for. A log that outlasts the video is cut
                // off where the timeline ends rather than drawn to its own end: a bar wider than
                // the lane was centred in it, its laps and the playhead minutes off the ruler (#463).
                let shown = (start: max(span.start, 0), end: min(span.end, duration))
                if shown.end > shown.start {
                    let selected = editor.selectedInputID == data.id && editor.selectedObjectID == nil
                    bar(
                        data, laps: editor.laps(of: data), from: shown.start, selected: selected,
                        pixelsPerSecond: pixelsPerSecond
                    )
                    .frame(width: max((shown.end - shown.start) * pixelsPerSecond - 2, 6))
                    .offset(x: shown.start * pixelsPerSecond + 1, y: 3)
                    .onTapGesture { location in
                        editor.selectedInputID = data.id
                        editor.selectedObjectID = nil
                        editor.selectedSegmentID = nil
                        editor.selectedMarkerID = nil
                        editor.seek(to: shown.start + location.x / pixelsPerSecond)
                    }
                }
            }
            PlayheadLine(editor: editor, height: Self.height) { min($0, duration) * pixelsPerSecond }
        }
        .frame(width: width, height: Self.height, alignment: .topLeading)
        .clipped()
    }

    /// "12 laps", "4 runs": what the bar is divided into, without the driving between runs.
    private func lapSummary(_ laps: [PlacedLap]) -> String {
        let listed = laps.map(\.lap).listed
        let noun = listed.areRuns ? "run" : "lap"
        return "\(listed.count) \(noun)\(listed.count == 1 ? "" : "s")"
    }

    /// The bar of `data` from project time `start` on, with a divider where each lap begins.
    private func bar(
        _ data: Input, laps: [PlacedLap], from start: Double, selected: Bool, pixelsPerSecond: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(selected ? 0.55 : 0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 4).stroke(Color.teal.opacity(selected ? 1 : 0.5), lineWidth: 1))
            // A divider where each lap begins, with its number when there is room for it.
            // The driving between runs (#552) is dimmed and unnumbered: it is not part of the course.
            ForEach(laps) { placed in
                let x = (placed.start - start) * pixelsPerSecond
                if !placed.lap.isListed, let end = placed.end {
                    Rectangle().fill(Color.black.opacity(0.25))
                        .frame(width: max(0, (end - placed.start) * pixelsPerSecond))
                        .offset(x: x)
                }
                Rectangle().fill(Color.white.opacity(selected ? 0.9 : 0.6)).frame(width: 1)
                    .offset(x: x)
                if placed.lap.isListed, let end = placed.end, (end - placed.start) * pixelsPerSecond > 22 {
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
        .help(laps.isEmpty ? data.label : "\(data.label) — \(lapSummary(laps))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.label)
        .accessibilityValue(laps.isEmpty ? "Data" : lapSummary(laps))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("timeline.data.\(data.label)")
    }
}
