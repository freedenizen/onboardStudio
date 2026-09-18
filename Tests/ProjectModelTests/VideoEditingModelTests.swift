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
        with.clips = [MediaReference(path: "GX020037.MP4")]
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
