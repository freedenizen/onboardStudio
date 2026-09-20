import Foundation
import Testing

@testable import ProjectModel

@Suite("Camera framing and clip sequences")
struct VideoEditingModelTests {
    @Test func cropsCompose() {
        let outer = CropInsets(top: 0.1, left: 0.2, bottom: 0.1, right: 0.2)
        let inner = CropInsets(top: 0.5, left: 0, bottom: 0, right: 0.5)
        let total = outer.composed(with: inner)
        // Remaining after outer: 60% wide, 80% tall; inner takes half of each from the top/right.
        #expect(abs(total.top - 0.5) < 1e-9 && abs(total.bottom - 0.1) < 1e-9)
        #expect(abs(total.left - 0.2) < 1e-9 && abs(total.right - 0.5) < 1e-9)
        #expect(CropInsets.none.composed(with: .none).isEmpty)
    }

    @Test func zoomWindowStaysInsideThePicture() {
        let centred = CameraFraming(zoom: 2)
        #expect(centred.zoomCrop == CropInsets(top: 0.25, left: 0.25, bottom: 0.25, right: 0.25))
        let corner = CameraFraming(zoom: 4, centerX: 0, centerY: 1)
        let crop = corner.zoomCrop
        #expect(abs(crop.left) < 1e-9 && abs(crop.right - 0.75) < 1e-9)
        #expect(abs(crop.top - 0.75) < 1e-9 && abs(crop.bottom) < 1e-9)
        #expect(CameraFraming(zoom: 0.2).zoomCrop.isEmpty, "zoom below 1 is clamped")
        #expect(CameraFraming.none.effectiveCrop(over: CropInsets(top: 0.1)).top == 0.1)
    }

    @Test func settingsDecodeWithoutFramingAndInputsWithoutClips() throws {
        let json = """
            {"outputWidth": 1280, "outputHeight": 720, "frameRate": 30}
            """
        let settings = try JSONDecoder().decode(ProjectSettings.self, from: Data(json.utf8))
        #expect(settings.framing == .none)
        #expect(settings.withoutFraming == settings)
        let video = try JSONDecoder().decode(VideoInputSettings.self, from: Data("{}".utf8))
        #expect(video.clips.isEmpty)
        var with = video
        with.clips = [VideoClip(source: MediaReference(path: "GX020037.MP4"))]
        let round = try JSONDecoder().decode(VideoInputSettings.self, from: JSONEncoder().encode(with))
        #expect(round.clips == with.clips)
    }

    @Test func goProAndCounterChaptersAreFound() {
        let dir = URL(fileURLWithPath: "/cam")
        let existing: Set<String> = ["GX020037.MP4", "GX030037.MP4", "GP010042.MP4", "DJI_0002_002.MP4", "clip_2.mov"]
        func exists(_ url: URL) -> Bool { existing.contains(url.lastPathComponent) }
        #expect(
            CameraChapters.following(dir.appending(path: "GX010037.MP4"), fileExists: exists).map(\.lastPathComponent)
                == ["GX020037.MP4", "GX030037.MP4"])
        #expect(
            CameraChapters.following(dir.appending(path: "GOPR0042.MP4"), fileExists: exists).map(\.lastPathComponent)
                == ["GP010042.MP4"])
        #expect(
            CameraChapters.following(dir.appending(path: "DJI_0002_001.MP4"), fileExists: exists)
                .map(\.lastPathComponent) == ["DJI_0002_002.MP4"])
        #expect(
            CameraChapters.following(dir.appending(path: "clip_1.mov"), fileExists: exists).map(\.lastPathComponent)
                == ["clip_2.mov"])
        #expect(CameraChapters.following(dir.appending(path: "holiday.mp4"), fileExists: exists).isEmpty)
        #expect(CameraChapters.next(after: dir.appending(path: "GX990037.MP4"))?.lastPathComponent == "GX1000037.MP4")
    }
}

@Suite("Clips, chapter groups and snapping")
struct ClipModelTests {
    @Test func clipsDecodeFromBothForms() throws {
        let json = """
            {"clips": [{"path": "GX020037.MP4"},
                       {"source": {"path": "GX030037.MP4"}, "trim": {"start": 5}, "gapBefore": 2}]}
            """
        let settings = try JSONDecoder().decode(VideoInputSettings.self, from: Data(json.utf8))
        #expect(settings.clips.count == 2)
        #expect(settings.clips[0] == VideoClip(source: MediaReference(path: "GX020037.MP4")))
        #expect(settings.clips[1].trim.start == 5 && settings.clips[1].gapBefore == 2)
        let round = try JSONDecoder().decode(VideoInputSettings.self, from: JSONEncoder().encode(settings))
        #expect(round.clips == settings.clips)
    }

    @Test func selectionsGroupIntoRecordings() {
        let dir = URL(fileURLWithPath: "/cam")
        let urls = ["GX020037.MP4", "GX010037.MP4", "holiday.mp4", "GX010099.MP4", "GX030037.MP4", "clip_2.mov"].map {
            dir.appending(path: $0)
        }
        let groups = CameraChapters.group(urls).map { $0.map(\.lastPathComponent) }
        #expect(
            groups == [
                ["GX010037.MP4", "GX020037.MP4", "GX030037.MP4"], ["holiday.mp4"], ["GX010099.MP4"], ["clip_2.mov"],
            ])
    }

    @Test func snappingPrefersTheNearestTargetWithinTolerance() {
        let snapping = TimelineSnapping(targets: [0, 10, 25.5], tolerance: 1)
        #expect(snapping.snap(9.4) == 10)
        #expect(snapping.snap(24.9) == 25.5)
        #expect(snapping.snap(12) == 12)
        // A 4 s clip whose end lands near 25.5 moves so its end snaps.
        #expect(snapping.snapSpan(start: 21.2, length: 4) == 21.5)
        #expect(snapping.snapSpan(start: 9.6, length: 4) == 10)
    }
}

@Suite("Timeline trimming arithmetic")
struct VideoTrimmingTests {
    @Test func headTrimKeepsThePictureInPlace() {
        // A video at project 10 s showing file second 5 at double speed; dragging its head to 14 s
        // must show file second 5 + 4 × 2 = 13 there.
        let sync = SyncSettings(startPositionInInput: 5, offsetInProject: 10, playSpeed: 2)
        let trimmed = VideoTrimming.headTrimmed(sync, toProjectTime: 14)
        #expect(trimmed.offsetInProject == 14 && trimmed.startPositionInInput == 13 && trimmed.playSpeed == 2)
        // Dragging left of zero clamps and never rewinds the file before its start.
        let early = VideoTrimming.headTrimmed(
            SyncSettings(startPositionInInput: 1, offsetInProject: 3), toProjectTime: -5)
        #expect(early.offsetInProject == 0 && early.startPositionInInput == 0)
    }

    @Test func tailTrimMapsProjectTimeToFileSeconds() {
        let sync = SyncSettings(startPositionInInput: 5, offsetInProject: 10, playSpeed: 2)
        #expect(VideoTrimming.tailTrimmed(sync, trim: .none, toProjectTime: 20, fullDuration: 100) == 25)
        // Beyond the file's end means "no trim".
        #expect(VideoTrimming.tailTrimmed(sync, trim: .none, toProjectTime: 60, fullDuration: 100) == nil)
        // A tail can never be dragged before the head.
        #expect(VideoTrimming.tailTrimmed(sync, trim: .none, toProjectTime: 9, fullDuration: 100) == 5.2)
    }
}

@Suite("Splitting a video")
struct VideoSplitTests {
    /// Identity timing: the cut falls at the same second in the file as on the timeline.
    private let sync = SyncSettings(startPositionInInput: 0, offsetInProject: 0, playSpeed: 1)

    @Test func theTwoHalvesMeetAtTheCut() throws {
        let split = try #require(
            VideoTrimming.split(sync, trim: .none, atProjectTime: 30, fullDuration: 100))

        #expect(split.firstEnd == 30, "the first half stops at the cut")
        #expect(split.secondSync.startPositionInInput == 30, "and the second picks the file up there")
        #expect(split.secondSync.offsetInProject == 30, "at the same place on the timeline")
        #expect(split.secondTrim.start == 30)
        #expect(split.secondTrim.end == nil, "no end trim to carry over")
    }

    /// The point of splitting rather than trimming twice: the picture must run on unbroken, so
    /// the file time the first half ends at is exactly the one the second begins at.
    @Test func thereIsNoGapOrOverlapAcrossTheJoin() throws {
        let shifted = SyncSettings(startPositionInInput: 12, offsetInProject: 5, playSpeed: 1)
        let split = try #require(
            VideoTrimming.split(shifted, trim: .none, atProjectTime: 20, fullDuration: 100))

        #expect(split.firstEnd == split.secondSync.startPositionInInput)
        #expect(split.secondSync.offsetInProject == 20)
        // The second half shows file second 27 at project second 20, which is where the first
        // half had reached.
        #expect(split.secondSync.inputTime(forProjectTime: 20) == 27)
        #expect(shifted.inputTime(forProjectTime: 20) == 27)
    }

    @Test func speedIsCarriedOverAndAppliedToTheCut() throws {
        let fast = SyncSettings(startPositionInInput: 0, offsetInProject: 0, playSpeed: 2)
        let split = try #require(
            VideoTrimming.split(fast, trim: .none, atProjectTime: 10, fullDuration: 100))

        #expect(split.firstEnd == 20, "ten seconds of a 2× video is twenty seconds of file")
        #expect(split.secondSync.playSpeed == 2)
        #expect(split.secondSync.startPositionInInput == 20)
    }

    @Test func anExistingEndTrimIsKeptOnTheSecondHalf() throws {
        let split = try #require(
            VideoTrimming.split(sync, trim: TrimRange(start: 5, end: 60), atProjectTime: 30, fullDuration: 100))
        #expect(split.secondTrim.end == 60, "the second half still stops where the video did")
        #expect(split.firstEnd == 30)
    }

    /// Cutting on an edge would make an empty input, so it is refused rather than allowed to
    /// produce a zero-length half that cannot be selected or removed.
    @Test func cuttingOutsideOrOnAnEdgeIsRefused() {
        #expect(VideoTrimming.split(sync, trim: .none, atProjectTime: 0, fullDuration: 100) == nil)
        #expect(VideoTrimming.split(sync, trim: .none, atProjectTime: 100, fullDuration: 100) == nil)
        #expect(VideoTrimming.split(sync, trim: .none, atProjectTime: -5, fullDuration: 100) == nil)
        #expect(VideoTrimming.split(sync, trim: .none, atProjectTime: 200, fullDuration: 100) == nil)
        // Inside an existing trim, the trim's own edges are what count.
        let trimmed = TrimRange(start: 20, end: 40)
        #expect(VideoTrimming.split(sync, trim: trimmed, atProjectTime: 20, fullDuration: 100) == nil)
        #expect(VideoTrimming.split(sync, trim: trimmed, atProjectTime: 30, fullDuration: 100) != nil)
        #expect(VideoTrimming.split(sync, trim: trimmed, atProjectTime: 40, fullDuration: 100) == nil)
    }
}
