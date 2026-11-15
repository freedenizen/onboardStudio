import CoreML
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// Reading onboard video for a car close ahead (#573): the detector's raw output decoded into
/// boxes, the rule that says which are a car ahead, and the readings put on a session's clock.
@Suite("Video traffic", .serialized)
struct VideoTrafficTests {
    static let rule = VideoTraffic.Rule()
    /// A 2.7K picture, with the rule's crop of it: what the model sees, letterboxed to 640.
    static let picture = CGSize(width: 2_704, height: 2_028)
    static let crop = CGRect(x: 406, y: 243, width: 1_893, height: 1_014)

    /// A raw head with every anchor empty but those given: anchor → (centre x, y and width,
    /// height in letterbox pixels, objectness, class, class score).
    struct Anchor {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var objectness: Double
        var category: Int
        var score: Double

        init(
            _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ objectness: Double, _ category: Int, _ score: Double
        ) {
            (self.x, self.y, self.w, self.h) = (x, y, w, h)
            (self.objectness, self.category, self.score) = (objectness, category, score)
        }
    }

    static func head(_ anchors: [Int: Anchor]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 8_400, 85], dataType: .float32)
        for index in 0..<array.count { array[index] = 0 }
        // Objectness and scores are probabilities; a zero leaves the anchor out.
        for (anchor, a) in anchors {
            let stride: Double = anchor < 6_400 ? 8 : (anchor < 8_000 ? 16 : 32)
            let cells = 640 / Int(stride)
            let local = anchor < 6_400 ? anchor : (anchor < 8_000 ? anchor - 6_400 : anchor - 8_000)
            let row = Double(local / cells)
            let column = Double(local % cells)
            let base = anchor * 85
            array[base] = NSNumber(value: a.x / stride - column)
            array[base + 1] = NSNumber(value: a.y / stride - row)
            array[base + 2] = NSNumber(value: log(a.w / stride))
            array[base + 3] = NSNumber(value: log(a.h / stride))
            array[base + 4] = NSNumber(value: a.objectness)
            array[base + 5 + a.category] = NSNumber(value: a.score)
        }
        return array
    }

    /// The anchor of the stride-8 grid cell holding letterbox point (x, y).
    static func anchor(atX x: Double, y: Double) -> Int { Int(y / 8) * 80 + Int(x / 8) }

    @Test func theHeadIsDecodedIntoBoxesOnThePicture() throws {
        // A car in the middle of the letterbox, 60 × 40 px of it: 177 × 118 px of the picture.
        let head = try Self.head([Self.anchor(atX: 320, y: 320): Anchor(320, 320, 60, 40, 0.9, 2, 0.8)])
        let boxes = VideoTraffic.detections(head: head, crop: Self.crop, picture: Self.picture)
        let box = try #require(boxes.count == 1 ? boxes.first : nil)
        #expect(box.category == 2)
        #expect(abs(box.score - 0.72) < 1e-4)
        let scale = 1_893.0 / 640
        #expect(abs(box.width * 2_704 - 60 * scale) < 0.5)
        // The middle of the letterbox is the middle of the crop.
        #expect(abs((box.minX + box.maxX) / 2 * 2_704 - (406 + 1_893 / 2)) < 0.5)
        #expect(abs((box.minY + box.maxY) / 2 * 2_028 - (243 + 1_014 / 2)) < 0.5)
        // Not a vehicle (COCO's person), or too unsure, is no box.
        let person = try Self.head([Self.anchor(atX: 320, y: 320): Anchor(320, 320, 60, 40, 0.9, 0, 0.9)])
        #expect(VideoTraffic.detections(head: person, crop: Self.crop, picture: Self.picture).isEmpty)
        let unsure = try Self.head([Self.anchor(atX: 320, y: 320): Anchor(320, 320, 60, 40, 0.3, 2, 0.3)])
        #expect(VideoTraffic.detections(head: unsure, crop: Self.crop, picture: Self.picture).isEmpty)
    }

    @Test func overlappingBoxesOfOneCarAreOne() throws {
        let head = try Self.head([
            Self.anchor(atX: 320, y: 320): Anchor(320, 320, 60, 40, 0.9, 2, 0.9),
            Self.anchor(atX: 328, y: 320): Anchor(324, 320, 60, 40, 0.8, 2, 0.8),
            Self.anchor(atX: 120, y: 320): Anchor(120, 320, 60, 40, 0.8, 2, 0.8),
        ])
        let boxes = VideoTraffic.detections(head: head, crop: Self.crop, picture: Self.picture)
        #expect(boxes.count == 2)
        #expect(boxes.contains { abs($0.score - 0.81) < 1e-4 })
    }

    static func box(
        x: Double, y: Double, width: Double, height: Double = 0.05, score: Double = 0.8
    ) -> VideoTraffic.Box {
        VideoTraffic.Box(
            minX: x - width / 2, minY: y - height / 2, maxX: x + width / 2, maxY: y + height / 2, score: score,
            category: 2)
    }

    @Test func onlyACarCloseAheadOnTheRoadCounts() {
        let ahead = Self.box(x: 0.5, y: 0.45, width: 0.05)
        #expect(VideoTraffic.carsAhead([ahead], rule: Self.rule) == [ahead])
        // This car's own cabin: the windscreen frame and dash as one huge "car".
        #expect(VideoTraffic.carsAhead([Self.box(x: 0.5, y: 0.5, width: 0.8, height: 0.4)], rule: Self.rule).isEmpty)
        // A car far down the straight, a car in the rear-view mirror, one off to the side.
        #expect(VideoTraffic.carsAhead([Self.box(x: 0.5, y: 0.45, width: 0.005)], rule: Self.rule).isEmpty)
        #expect(VideoTraffic.carsAhead([Self.box(x: 0.6, y: 0.15, width: 0.05)], rule: Self.rule).isEmpty)
        #expect(VideoTraffic.carsAhead([Self.box(x: 0.9, y: 0.45, width: 0.05)], rule: Self.rule).isEmpty)
        // Too unsure.
        #expect(VideoTraffic.carsAhead([Self.box(x: 0.5, y: 0.45, width: 0.05, score: 0.3)], rule: Self.rule).isEmpty)
    }

    @Test func theBundledDetectorReadsAVideoOneKeyframeASecond() async throws {
        let video = try MediaFixtures.video
        let sightings = try await VideoTraffic.read(video, rule: Self.rule) { _ in }
        // A three-second test picture with no car in it.
        #expect(abs(sightings.duration - 3) < 0.1)
        #expect(!sightings.times.isEmpty && sightings.times.count <= 3)
        #expect(sightings.widths.allSatisfy { $0 == 0 })
        #expect(zip(sightings.times, sightings.times.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// Writes `sightings` as the reading of a fresh copy of the fixture video, and returns the copy.
    static func read(_ sightings: CarSightings) throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appending(path: "traffic-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: try MediaFixtures.video, to: copy)
        try VideoTraffic.save(sightings, for: copy)
        return copy
    }

    static func forget(_ files: [URL]) {
        for file in files {
            if let cache = VideoTraffic.cacheURL(for: file) { try? FileManager.default.removeItem(at: cache) }
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test func aRecordingIsPutOnTheSessionsClockChapterAfterChapter() throws {
        let first = try Self.read(CarSightings(times: [0, 1, 2], widths: [0, 0.05, 0.04], duration: 3))
        let second = try Self.read(CarSightings(times: [0, 1], widths: [0.03, 0], duration: 2))
        defer { Self.forget([first, second]) }
        let recordedAt = Date(timeIntervalSince1970: 1_800_000_100)
        // The session's clock starts 100 s before the camera's.
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "x", createdAt: Date(timeIntervalSince1970: 1_800_000_000)), channels: [])
        let samples = try #require(
            VideoTraffic.samples(ofRecording: [first, second], recordedAt: recordedAt, in: session))
        #expect(samples.map(\.time) == [100, 101, 102, 103, 104])
        #expect(samples.map(\.carAhead) == [false, true, true, true, false])
        // A file not read yet leaves nothing to say.
        let unread = FileManager.default.temporaryDirectory.appending(path: "unread-\(UUID().uuidString).mp4")
        #expect(VideoTraffic.samples(ofRecording: [first, unread], recordedAt: recordedAt, in: session) == nil)
    }

    @Test func aProjectsCameraIsPutOnItsDatasClockThroughTheSync() throws {
        let file = try Self.read(CarSightings(times: [0, 1, 2], widths: [0, 0.05, 0], duration: 3))
        defer { Self.forget([file]) }
        // The video starts 5 s into the project; the data 2 s before it, 40 s into its own log.
        let camera = Input(
            label: "camera", source: MediaReference(path: file.path), kind: .video(VideoInputSettings()),
            sync: SyncSettings(startPositionInInput: 0, offsetInProject: 5))
        let data = Input(
            label: "data", source: MediaReference(path: "/tmp/log.csv"), kind: .data(DataInputSettings()),
            sync: SyncSettings(startPositionInInput: 40, offsetInProject: 3))
        let loaded = ProjectCompiler.LoadedProject(
            project: Project(inputs: [camera, data]),
            location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")), sessions: [:], mediaInfo: [:])
        #expect(loaded.project.camera(for: data.id) == camera.id)
        #expect(VideoTraffic.files(of: camera, in: loaded) == [file])
        let samples = try #require(VideoTraffic.samples(of: camera, for: data, in: loaded))
        #expect(samples.map(\.time) == [42, 43, 44])
        #expect(samples.map(\.carAhead) == [false, true, false])
    }

    @Test func aReadingIsKeptByFileAndDetector() throws {
        let file = try Self.read(CarSightings(times: [0], widths: [0.05], duration: 1))
        defer { Self.forget([file]) }
        #expect(VideoTraffic.saved(for: file) == CarSightings(times: [0], widths: [0.05], duration: 1))
        let folder = VideoTraffic.cacheFolder(environment: ["ONBOARD_TEST_MOTION_DIR": "/tmp/motion-test"])
        #expect(folder.path == "/tmp/motion-test/Traffic")
        #expect(VideoTraffic.cacheFolder(environment: [:]).path.hasSuffix("Application Support/OnboardStudio/Traffic"))
    }
}
