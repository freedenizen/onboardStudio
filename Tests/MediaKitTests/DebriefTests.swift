import AVFoundation
import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Coaching debrief (#327)", .serialized)
struct DebriefTests {
    static let settings: ExportSettings = {
        var s = ExportSettings(width: 320, height: 180)
        s.frameRate = 30
        s.audioBitrate = nil
        return s
    }()

    @Test func thePlanReadsTheCoachingLapAndKeepsTheBiggestLosses() throws {
        var loaded = try CornerExportsTests.loaded(lap: 2)
        loaded.project.details.track = "Stadium"
        loaded.project.details.date = "1 May"
        let plan = try #require(DebriefPlan.make(in: loaded, duration: 170))
        // The slow lap loses time in both corners: both are clips, biggest loss first.
        #expect(plan.corners.count == 2)
        #expect(plan.corners[0].timeLost >= plan.corners[1].timeLost)
        #expect(plan.segmentTitles.first == "Title card")
        #expect(plan.segmentTitles.last == "Next session")
        #expect(plan.segmentTitles[1].hasPrefix("Turn "))
        #expect(plan.segmentTitles[1].hasSuffix(" s lost"))
        // The title card: the track, the day, the best lap and the reading.
        #expect(plan.title.title == "Stadium")
        #expect(plan.title.lines.contains("1 May"))
        #expect(plan.title.lines.contains { $0.hasPrefix("Best lap ") })
        let reading = try #require(plan.title.lines.last)
        #expect(reading.hasPrefix("Lap 2 read against your best lap: ") && reading.hasSuffix(" behind"))
        #expect(plan.title.seconds == DebriefPlan.titleSeconds)
        // The closing card: one experiment per corner kept, in the same order.
        #expect(plan.closing.title == "Next session, try…")
        #expect(plan.closing.lines.count == 2)
        #expect(plan.closing.lines[0].hasPrefix("Turn \(plan.corners[0].label): "))
        #expect(plan.closing.seconds == 2 * DebriefPlan.closingSecondsPerLine)
        #expect(plan.duration > plan.title.seconds + plan.closing.seconds)
        // Fewer corners when asked.
        let one = try #require(DebriefPlan.make(in: loaded, duration: 170, cornerCount: 1))
        #expect(one.corners.count == 1)
        #expect(one.closing.lines.count == 1)
    }

    @Test func aLapThatLostNothingHasNoClipsAndSaysSo() throws {
        let loaded = try CornerExportsTests.loaded(lap: 4)
        let plan = try #require(DebriefPlan.make(in: loaded, duration: 170))
        #expect(plan.corners.isEmpty)
        #expect(plan.closing.lines == ["This lap matched your best lap in every corner. Drive it again the same way."])
        #expect(plan.closing.seconds == DebriefPlan.closingSecondsMinimum)
        // Without any data there is no debrief.
        let empty = ProjectCompiler.LoadedProject(
            project: Project(), location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")), sessions: [:],
            mediaInfo: [:])
        #expect(DebriefPlan.make(in: empty, duration: 10) == nil)
    }

    @Test func cardsWrapTheirLinesToTheWidth() {
        let long = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces)
        let lines = CardWriter.wrapped(long, budget: 24)
        #expect(lines.count > 1)
        #expect(lines.allSatisfy { $0.count <= 24 })
        #expect(lines.joined(separator: " ") == long)
        #expect(CardWriter.wrapped("supercalifragilistic", budget: 5) == ["supercalifragilistic"])
        let card = DebriefPlan.Card(title: "T", lines: [long, "short"], seconds: 1)
        let objects = CardWriter.objects(for: card, settings: Self.settings)
        #expect(objects.count > 3, "the long line became several text objects")
        #expect(objects.allSatisfy { $0.frame.y + $0.frame.height <= 0.96 })
    }

    @Test func aCardIsAMovieOfItsLengthAndTheStitchAddsThemUp() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DebriefTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appending(path: "one.mp4")
        let two = folder.appending(path: "two.mp4")
        let card = DebriefPlan.Card(title: "Stadium", lines: ["Best lap 0:44.10 (lap 4)"], seconds: 1)
        try await CardWriter.write(card, project: Project(), settings: Self.settings, to: one)
        try await CardWriter.write(card, project: Project(), settings: Self.settings, to: two)
        let asset = AVURLAsset(url: one)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 320, height: 180))
        let joined = folder.appending(path: "joined.mp4")
        try await MovieStitcher.concatenate([one, two], fileType: .mp4, to: joined)
        let total = try await AVURLAsset(url: joined).load(.duration).seconds
        #expect(abs(total - 2) < 0.1)
    }

    /// The whole thing on the fixture video: its three seconds hold no corner clip, so the
    /// debrief is the two cards, and plays for as long as they do.
    @Test func theDebriefExportsAsOneVideo() async throws {
        let video = Input(
            label: "v", source: MediaReference(path: try MediaFixtures.video.path), kind: .video(VideoInputSettings()))
        let data = Input(
            label: "d", source: MediaReference(path: CornerExportsTests.fixture.path), kind: .data(DataInputSettings()))
        var project = Project(inputs: [video, data])
        project.settings.outputWidth = 320
        project.settings.outputHeight = 180
        project.coaching = CoachingSettings(dataInputID: data.id, lap: 2, reference: .sessionBest)
        var loaded = try await ProjectCompiler.load(
            project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")))
        loaded.problems[data.id] = nil
        loaded.sessions[data.id] = try RaceRenderCSVImporter()
            .importSession(at: CornerExportsTests.fixture, options: SessionBuilder.Options())
        let compiled = try await ProjectCompiler.compile(loaded)
        let plan = try #require(DebriefPlan.make(in: loaded, duration: compiled.duration))
        #expect(plan.corners.isEmpty, "a 3 s video holds no corner of a 44 s lap")
        let url = FileManager.default.temporaryDirectory.appending(path: "debrief-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var last = ExportProgress(fraction: 0, framesWritten: 0, currentTime: 0)
        for try await progress in DebriefExporter.export(
            compiled, project: loaded.project, plan: plan, settings: Self.settings, to: url)
        {
            #expect(progress.fraction >= last.fraction)
            last = progress
        }
        #expect(last.fraction == 1)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - plan.duration) < 0.15)
    }
}
