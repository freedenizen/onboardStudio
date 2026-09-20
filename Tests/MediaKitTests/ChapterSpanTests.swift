import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel

@Suite("Recording chapters")
struct ChapterSpanTests {
    private func clip(_ name: String, gapBefore: Double = 0, speed: Double = 1, trim: TrimRange = .none) -> VideoClip {
        VideoClip(source: MediaReference(path: name), trim: trim, gapBefore: gapBefore, speed: speed)
    }

    /// A single-file input has no seams, so there is nothing for the sidebar or the timeline to
    /// draw — callers rely on the empty array to mean exactly that.
    @Test func aSingleFileRecordingHasNoChapters() {
        #expect(
            ChapterSpan.layout(
                firstName: "GX010037.MP4", firstDuration: 769, clips: [], playedDurations: []
            ).isEmpty)
    }

    /// The GoPro case from the report: two files the camera split at its size limit, butted
    /// together. The seam belongs at the end of the first file.
    @Test func twoChaptersMeetWhereTheFirstFileEnds() {
        let spans = ChapterSpan.layout(
            firstName: "GX010037.MP4", firstDuration: 769,
            clips: [clip("GX020037.MP4")], playedDurations: [660])

        #expect(spans.count == 2)
        #expect(spans[0].name == "GX010037.MP4")
        #expect(spans[0].start == 0 && spans[0].duration == 769)
        #expect(spans[1].name == "GX020037.MP4")
        #expect(spans[1].start == 769, "the second chapter starts where the first ends")
        #expect(spans[1].duration == 660)
        #expect(spans[1].end == 1429)
        #expect(spans[1].gapBefore == 0)
    }

    /// A gap is time the camera was stopped. It is real elapsed time, so it pushes the next
    /// chapter later rather than being closed up.
    @Test func aStoppedCameraPushesTheNextChapterLater() {
        let spans = ChapterSpan.layout(
            firstName: "a.mp4", firstDuration: 100,
            clips: [clip("b.mp4", gapBefore: 30), clip("c.mp4")], playedDurations: [50, 25])

        #expect(spans[1].gapBefore == 30)
        #expect(spans[1].start == 130, "the gap sits between the two files")
        #expect(spans[2].start == 180, "and everything after it moves by the same amount")
        #expect(spans.last?.end == 205)
    }

    /// The span is what the chapter occupies on the timeline, so a clip played at double speed
    /// takes half the room — matching how ProjectCompiler sums the input's duration.
    @Test func speedShortensAChaptersSpan() {
        let spans = ChapterSpan.layout(
            firstName: "a.mp4", firstDuration: 60,
            clips: [clip("b.mp4", speed: 2)], playedDurations: [80])

        #expect(spans[1].duration == 40)
        #expect(spans[1].end == 100)
    }

    /// The spans must add up to the duration the compiler reports for the input, or the seams
    /// would drift away from the bar they are drawn on.
    @Test func spansEndWhereTheInputEnds() {
        let clips = [clip("b.mp4", gapBefore: 5), clip("c.mp4", speed: 2)]
        let played = [50.0, 80.0]
        let spans = ChapterSpan.layout(
            firstName: "a.mp4", firstDuration: 60, clips: clips, playedDurations: played)

        // The same sum ProjectCompiler.loadClips accumulates, plus the first file.
        let compiled =
            60
            + zip(clips, played).reduce(0.0) { total, pair in
                total + max(0, pair.0.gapBefore) + pair.0.sequenceDuration(played: pair.1)
            }
        #expect(spans.last?.end == compiled)
    }

    /// A short read of the durations must not trap: probing can fail for a file the user has
    /// since moved, and the rest of the recording should still lay out.
    @Test func missingDurationsDoNotTrap() {
        let spans = ChapterSpan.layout(
            firstName: "a.mp4", firstDuration: 60,
            clips: [clip("b.mp4"), clip("c.mp4")], playedDurations: [])

        #expect(spans.count == 3)
        #expect(spans[1].duration == 0 && spans[2].duration == 0)
        #expect(spans.last?.end == 60)
    }

    @Test func chaptersAreNamedAfterTheirFile() {
        #expect(MediaReference(path: "clips/GX020037.MP4").displayName == "GX020037.MP4")
        #expect(MediaReference(path: "/Volumes/SD/GX010037.MP4").displayName == "GX010037.MP4")
    }
}
