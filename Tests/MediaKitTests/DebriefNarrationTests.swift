import AVFoundation
import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Debrief narration (#335)", .serialized)
struct DebriefNarrationTests {
    @Test func aSentenceBecomesAShortAudioFileOfItsLength() async throws {
        try #require(DebriefNarrator.isAvailable, "no system voice on this machine")
        let url = FileManager.default.temporaryDirectory.appending(path: "narration-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let piece = try await DebriefNarrator.speak("Turn four: brake a little later.", to: url)
        #expect(piece.url == url)
        #expect(piece.seconds > 0.5 && piece.seconds < 10, "\(piece.seconds) s")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - piece.seconds) < 0.25)
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func theCardsGrowToFitTheirWords() {
        let plan = DebriefPlan(
            title: .init(title: "T", lines: [], seconds: 2), corners: [],
            closing: .init(title: "C", lines: [], seconds: 9))
        let url = URL(fileURLWithPath: "/tmp/x.caf")
        let narration = DebriefNarration(
            title: .init(url: url, seconds: 6), corners: [], closing: .init(url: url, seconds: 3))
        let fitted = narration.fitting(plan)
        #expect(fitted.title.seconds == 6 + DebriefNarration.tail)
        #expect(fitted.closing.seconds == 9, "a card already longer than its words keeps its length")
    }

    @Test func aNarratedDebriefHasAVoiceTrackAndFitsItsCards() async throws {
        try #require(DebriefNarrator.isAvailable, "no system voice on this machine")
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
        var plan = try #require(DebriefPlan.make(in: loaded, duration: compiled.duration))
        #expect(plan.cornerNotes.count == plan.corners.count)
        // Short cards, so the voice has to stretch them.
        plan.title.seconds = 1
        plan.closing.seconds = 1
        let url = FileManager.default.temporaryDirectory.appending(path: "narrated-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        for try await _ in DebriefExporter.export(
            compiled, project: loaded.project, plan: plan, settings: DebriefTests.settings, narrated: true, to: url)
        {}
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 2 + 2 * DebriefNarration.tail, "both cards grew to fit their words: \(duration) s")
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1, "the voice is mixed into one track")
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    }
}
