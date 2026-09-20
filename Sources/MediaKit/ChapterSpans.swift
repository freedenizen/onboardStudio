import Foundation
import ProjectModel

/// Where one file of a multi-file recording falls on its input's own media timeline.
///
/// A camera that splits a recording at its file-size limit produces several files that are one
/// continuous shot; the app joins them into a single input. These spans are what lets the rest of
/// the app say so — which file is playing, and where the seams are — without undoing the join.
public struct ChapterSpan: Hashable, Sendable, Identifiable {
    public var id: Int { index }
    /// Position in the recording, 0 for the file the input itself points at.
    public let index: Int
    /// The file's name, for the sidebar and the timeline's tooltips.
    public let name: String
    /// Seconds of stopped camera before this chapter. Real elapsed time, so it is drawn.
    public let gapBefore: Double
    /// Start on the input's media timeline, after `gapBefore`.
    public let start: Double
    /// Length on that timeline, with the clip's own speed already applied.
    public let duration: Double

    public var end: Double { start + duration }

    public init(index: Int, name: String, gapBefore: Double, start: Double, duration: Double) {
        self.index = index
        self.name = name
        self.gapBefore = gapBefore
        self.start = start
        self.duration = duration
    }
}

extension ChapterSpan {
    /// Lays the files of a recording out end to end on the input's media timeline.
    ///
    /// `firstDuration` is the whole first file; the input's own trim is applied to the joined
    /// sequence rather than to any one file, so it is deliberately not considered here. Each
    /// following clip contributes its gap and then its trimmed, speed-adjusted length, matching
    /// how `ProjectCompiler` sums them into the input's duration.
    ///
    /// Returns an empty array for a single-file input: there are no seams worth drawing.
    public static func layout(
        firstName: String, firstDuration: Double, clips: [VideoClip], playedDurations: [Double]
    ) -> [ChapterSpan] {
        guard !clips.isEmpty else { return [] }
        var spans = [
            ChapterSpan(
                index: 0, name: firstName, gapBefore: 0, start: 0, duration: max(0, firstDuration))
        ]
        var cursor = max(0, firstDuration)
        for (offset, clip) in clips.enumerated() {
            let gap = max(0, clip.gapBefore)
            let played = offset < playedDurations.count ? playedDurations[offset] : 0
            let length = clip.sequenceDuration(played: played)
            cursor += gap
            spans.append(
                ChapterSpan(
                    index: offset + 1, name: clip.source.displayName, gapBefore: gap, start: cursor,
                    duration: length))
            cursor += length
        }
        return spans
    }
}

extension MediaReference {
    /// The file's own name, which is what the camera numbered and what the user recognises.
    public var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
