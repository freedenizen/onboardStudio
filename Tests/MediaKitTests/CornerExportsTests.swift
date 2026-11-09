import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Every-corner export")
struct CornerExportsTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    /// A project whose data is the coaching fixture, with the slow lap chosen in Coaching.
    static func loaded(lap: Int? = 2) throws -> ProjectCompiler.LoadedProject {
        let data = Input(label: "d", source: MediaReference(path: fixture.path), kind: .data(DataInputSettings()))
        var project = Project(inputs: [data])
        if let lap { project.coaching = CoachingSettings(dataInputID: data.id, lap: lap, reference: .sessionBest) }
        let session = try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
        var loaded = ProjectCompiler.LoadedProject(
            project: project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")), sessions: [:],
            mediaInfo: [:])
        loaded.sessions[data.id] = session
        return loaded
    }

    @Test func everyCornerOfTheCoachingLapIsAClip() throws {
        let loaded = try Self.loaded()
        let clips = ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: false), in: loaded, duration: 170)
        #expect(clips.map(\.title) == ["Turn 1", "Turn 2"])
        let slow = try #require(loaded.sessions.values.first?.laps[1])
        for clip in clips {
            #expect(clip.range.lowerBound >= slow.start - 2.5)
            #expect(clip.range.upperBound <= (slow.end ?? 0) + 2.5)
            #expect(clip.range.upperBound - clip.range.lowerBound > 5)
            #expect(clip.timeLost > 0)
        }
        #expect(clips[0].fileName(base: "Day", fileExtension: "mp4") == "Day – Turn 1.mp4")
        // Clipped to the project: a short project cuts the clips.
        let short = ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: false), in: loaded, duration: 50)
        #expect(short.allSatisfy { $0.range.upperBound <= 50 })
        // Any other range writes no corner clips.
        #expect(ProjectCompiler.cornerExports(.whole, in: loaded, duration: 170).isEmpty)
    }

    @Test func onlyOpportunitiesKeepsTheCornersThatLostTimeBiggestFirst() throws {
        let loaded = try Self.loaded()
        let clips = ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: true), in: loaded, duration: 170)
        #expect(!clips.isEmpty)
        #expect(zip(clips, clips.dropFirst()).allSatisfy { $0.timeLost >= $1.timeLost })
        // The best lap against itself loses nothing: no opportunities, but every corner still has a clip.
        let best = try Self.loaded(lap: 4)
        #expect(ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: true), in: best, duration: 170).isEmpty)
        let every = ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: false), in: best, duration: 170)
        #expect(every.count == 2)
    }

    @Test func withoutACoachingLapTheFirstLapReadIsUsed() throws {
        let loaded = try Self.loaded(lap: nil)
        let clips = ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: false), in: loaded, duration: 170)
        let first = try #require(loaded.sessions.values.first?.laps[0])
        #expect(clips.count == 2)
        #expect(clips.allSatisfy { $0.range.upperBound <= (first.end ?? 0) + 2.5 })
    }

    @Test func aRetimedCornerSlowsItsBrakingZoneAndHoldsWhereTheReferenceBraked() throws {
        let loaded = try Self.loaded()
        let range = ExportRange.eachCorner(onlyOpportunities: false, retime: .standard)
        let clips = ProjectCompiler.cornerExports(range, in: loaded, duration: 170)
        #expect(clips.count == 2)
        let read = try #require(ProjectCompiler.coachingLap(in: loaded))
        for (clip, comparison) in zip(clips, read.analysis.corners) {
            struct Slowed {
                let start: Double
                let end: Double
                let rate: Double
            }
            let speed = clip.retimes.compactMap { retime -> Slowed? in
                if case .speed(let end, let rate) = retime.kind {
                    return Slowed(start: retime.start, end: end, rate: rate)
                }
                return nil
            }
            let hold = clip.retimes.compactMap { retime -> (Double, Double)? in
                if case .hold(let seconds) = retime.kind { return (retime.start, seconds) }
                return nil
            }
            // Slowed from the brake point, two seconds into the clip, to the slowest point.
            let slowed = try #require(speed.first)
            #expect(abs(slowed.start - (clip.range.lowerBound + ProjectCompiler.cornerClipLeadSeconds)) < 0.05)
            #expect(slowed.end > slowed.start && slowed.rate == 0.5)
            let slowest =
                read.lap.start
                + read.analysis.lap.elapsed(
                    atDistance: comparison.lap.corner.apexDistance + comparison.lap.minimumSpeedMeters)
            #expect(abs(slowed.end - slowest) < 0.05)
            // Held a second where the reference braked: the best lap brakes later than the slow
            // one, so the lap reaches that spot after its own brake point.
            let held = try #require(hold.first)
            #expect(held.1 == 1)
            let referenceBrake = read.lap.start + read.analysis.lap.elapsed(atDistance: comparison.reference.phaseStart)
            #expect(abs(held.0 - referenceBrake) < 0.05)
            #expect(held.0 > slowed.start && clip.range.contains(held.0))
        }
        // Without a retime, or with both switched off, the clips play at speed.
        #expect(
            ProjectCompiler.cornerExports(.eachCorner(onlyOpportunities: false), in: loaded, duration: 170)
                .allSatisfy { $0.retimes.isEmpty })
        let neither = CornerClipRetime(brakingRate: nil, referenceHoldSeconds: nil)
        #expect(
            ProjectCompiler.cornerExports(
                .eachCorner(onlyOpportunities: false, retime: neither), in: loaded, duration: 170
            )
            .allSatisfy { $0.retimes.isEmpty })
    }
}
