import AVFoundation
import Foundation
import ProjectModel
import Testing

@testable import MediaKit

@Suite("Gyroflow (#263)", .serialized)
struct GyroflowTests {
    @Test func theArgumentsKeepTheRecordingsSizeAndASafeName() throws {
        let input = URL(fileURLWithPath: "/Volumes/Card/Track Day (am)/GX010037.MP4")
        let folder = URL(fileURLWithPath: "/tmp/out")
        // Gyroflow percent-encodes anything but letters, digits, - and _ in the name it is given.
        #expect(Gyroflow.outputURL(for: input, in: folder).lastPathComponent == "GX010037-gyroflow.mp4")
        let spaced = URL(fileURLWithPath: "/tmp/Lap 7 (best).mov")
        #expect(Gyroflow.outputURL(for: spaced, in: folder).lastPathComponent == "Lap_7__best_-gyroflow.mp4")
        let arguments = Gyroflow.arguments(input: input, folder: folder, width: 2704, height: 2028)
        #expect(arguments.first == input.path)
        #expect(arguments.contains("--stdout-progress") && arguments.contains("--overwrite"))
        let parameters = try #require(arguments.last)
        #expect(parameters.contains("'output_width': 2704") && parameters.contains("'output_height': 2028"))
        #expect(parameters.contains("'output_folder': '/tmp/out/'"))
        #expect(parameters.contains("'output_filename': 'GX010037-gyroflow.mp4'"))
    }

    @Test func progressIsReadFromGyroflowsOutput() {
        #expect(Gyroflow.progress(in: "[282180e1] Rendering progress: 351/361 frames (97.2%) ETA 0.3s") == 351.0 / 361)
        #expect(Gyroflow.progress(in: "[282180e1] Rendering completed: GX010029_stabilized.mp4") == nil)
        #expect(Gyroflow.progress(in: "16:26:42 [INFO] Done in 9.684s") == nil)
    }

    @Test func theSteadiedCopiesStandInOnlyWhenEveryOneIsThere() throws {
        let copy = try MediaFixtures.video
        var settings = VideoInputSettings()
        settings.stabilisation = StabilisationSettings(
            method: .gyroflow, gyroflowFiles: [MediaReference(path: copy.path)])
        let input = Input(label: "v", source: MediaReference(path: "/tmp/recording.mp4"), kind: .video(settings))
        let loaded = ProjectCompiler.LoadedProject(
            project: Project(inputs: [input]), location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")),
            sessions: [:], mediaInfo: [:])
        #expect(ProjectCompiler.gyroflowPictures(for: input, settings: settings, in: loaded) == [copy])
        // A missing copy, or one short for a chapter, shows the recording instead.
        var missing = settings
        missing.stabilisation.gyroflowFiles = [MediaReference(path: "/tmp/no-such-copy.mp4")]
        #expect(ProjectCompiler.gyroflowPictures(for: input, settings: missing, in: loaded) == nil)
        var chaptered = settings
        chaptered.clips = [VideoClip(source: MediaReference(path: "/tmp/chapter2.mp4"))]
        #expect(ProjectCompiler.gyroflowPictures(for: input, settings: chaptered, in: loaded) == nil)
        // Turning it off, or making new copies, rebuilds the media.
        var off = settings
        off.stabilisation.method = .off
        let before = Project(inputs: [input])
        var after = before
        after.inputs[0].kind = .video(off)
        #expect(ProjectCompiler.gyroflowPicturesChanged(from: before, to: after))
        #expect(!ProjectCompiler.gyroflowPicturesChanged(from: before, to: before))
    }

    @Test func aProjectSavedBeforeGyroflowOpensWithoutIt() throws {
        let old = try JSONDecoder().decode(
            StabilisationSettings.self, from: Data(#"{"method": "motionData", "smoothing": 1, "zoom": 1.2}"#.utf8))
        #expect(old.gyroflowFiles.isEmpty && old.method == .motionData)
    }

    /// A real Gyroflow render, when it is installed and `ONBOARD_GYROFLOW_CLIP` names a short GoPro clip:
    /// the copy keeps the recording's frame count and duration, which is what keeps sync (local only).
    @Test func gyroflowKeepsTheTimingOfTheRecording() async throws {
        guard let path = ProcessInfo.processInfo.environment["ONBOARD_GYROFLOW_CLIP"], Gyroflow.executable() != nil
        else { return }
        let clip = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory.appending(path: "gyroflow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var last = 0.0
        for try await fraction in Gyroflow.stabilise([clip], into: folder, width: 2704, height: 2028) {
            last = fraction
        }
        #expect(last == 1)
        let copy = Gyroflow.outputURL(for: clip, in: folder)
        let original = AVURLAsset(url: clip)
        let steadied = AVURLAsset(url: copy)
        let a = try await original.load(.duration).seconds
        let b = try await steadied.load(.duration).seconds
        #expect(abs(a - b) < 0.05, "\(a) vs \(b)")
    }
}
