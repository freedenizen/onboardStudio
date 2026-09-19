import Foundation
import ProjectModel

/// The pause between two recordings of one camera, from the clocks in the files.
public enum RecordingGaps {
    /// When a file starts on the wall clock and how long it runs. A GoPro chapter carries its
    /// recording's start, not its own, so the earlier chapters next to it on disk are added up.
    public static func span(of url: URL) async -> (start: Double, duration: Double)? {
        var chain = [url]
        while let previous = CameraChapters.previousChapter(of: chain[0]),
            FileManager.default.fileExists(atPath: previous.path)
        {
            chain.insert(previous, at: 0)
        }
        guard let first = try? await MediaProbe.probe(chain[0]),
            let start = TimestampSync.recordingStart(of: chain[0], info: first)
        else { return nil }
        var offset = 0.0
        var duration = first.duration
        for (index, chapter) in chain.enumerated().dropFirst() {
            offset += duration
            guard let info = try? await MediaProbe.probe(chapter) else { return nil }
            duration = info.duration
            if index == chain.count - 1 { break }
        }
        return (start.epoch + offset, duration)
    }

    /// Seconds between the end of `previous` and the start of `next` (about zero for chapters
    /// of one recording, negative when they overlap), or `nil` when a file has no usable clock.
    public static func pause(between previous: URL, and next: URL) async -> Double? {
        guard let a = await span(of: previous), let b = await span(of: next) else { return nil }
        return b.start - (a.start + a.duration)
    }
}
