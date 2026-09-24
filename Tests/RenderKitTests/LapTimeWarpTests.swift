import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

@Suite("Two laps kept level by distance (#154)")
struct LapTimeWarpTests {
    /// 100 m laps: lap 1 at 10 m/s (0–10 s), then lap 2 at 20 m/s (10–15 s).
    static let session: TelemetrySession = {
        let times = Array(stride(from: 0.0, through: 15.0, by: 0.25))
        let distance = times.map { $0 < 10 ? 10 * $0 : 100 + 20 * ($0 - 10) }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .distance, name: "d", unit: .meters, times: times, values: distance)],
            laps: [
                Lap(number: 1, start: 0, end: 10, isComplete: true),
                Lap(number: 2, start: 10, end: 15, isComplete: true),
            ])
    }()

    func warp(comparedSync: SyncSettings = .identity, compared: TelemetrySession = session) throws -> LapTimeWarp {
        try #require(
            LapTimeWarp(
                lap: Self.session.laps[0], in: Self.session, sync: .identity, compared: compared.laps[1],
                in: compared, comparedSync: comparedSync))
    }

    @Test func theComparedLapIsAsFarRoundAtEveryMoment() throws {
        let warp = try warp()
        #expect(warp.lapStart == 0 && warp.lapEnd == 10)
        #expect(warp.comparedStart == 10 && warp.comparedEnd == 15)
        // Halfway round lap 1 (5 s, 50 m) lap 2 was 50 m in, 2.5 s after it started.
        #expect(abs(warp.comparedTime(at: 5) - 12.5) < 1e-6)
        #expect(abs(warp.comparedTime(at: 2) - 11) < 1e-6)
        // Lap 1 is 2.5 s behind lap 2 there, and 5 s behind at the line.
        #expect(abs((warp.delta(at: 5) ?? 0) - 2.5) < 1e-6)
        #expect(abs((warp.delta(at: 10) ?? 0) - 5) < 1e-6)
        #expect(warp.delta(at: 11) == nil)
        // Before and after the lap the compared side runs on at normal speed.
        #expect(abs(warp.comparedTime(at: -1) - 9) < 1e-6)
        #expect(abs(warp.comparedTime(at: 12) - 17) < 1e-6)
    }

    @Test func anotherSessionIsMatchedByTheFractionOfItsLapAndItsOwnSync() throws {
        // The same laps logged 10 % longer (another GPS) and placed 100 s later on the timeline.
        let longer = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(
                    role: .distance, name: "d", unit: .meters, times: try #require(Self.session[.distance]?.times),
                    values: try #require(Self.session[.distance]?.values).map { $0 * 1.1 })
            ], laps: Self.session.laps)
        let warp = try warp(comparedSync: SyncSettings(offsetInProject: 100), compared: longer)
        // Halfway round is halfway round, whatever each file thinks a lap measures.
        #expect(abs(warp.comparedTime(at: 5) - 112.5) < 1e-6)
        #expect(abs(warp.comparedStart - 110) < 1e-6)
    }

    @Test func aLapWithoutAnEndOrDistanceCannotBeCompared() {
        let open = Lap(number: 3, start: 15, end: nil, isComplete: false)
        #expect(
            LapTimeWarp(
                lap: Self.session.laps[0], in: Self.session, sync: .identity, compared: open, in: Self.session,
                comparedSync: .identity) == nil)
        let noDistance = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"), channels: [], laps: Self.session.laps)
        #expect(
            LapTimeWarp(
                lap: noDistance.laps[0], in: noDistance, sync: .identity, compared: noDistance.laps[1], in: noDistance,
                comparedSync: .identity) == nil)
    }

    @Test func anObjectFollowingTheComparedLapReadsItsDataThroughTheWarp() throws {
        let warp = try warp()
        func context(follows: Bool) -> ObjectContext {
            ObjectContext(
                objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: TelemetrySampler(session: Self.session),
                sync: .identity, cache: RenderCache(), lapComparison: warp, followsComparedLap: follows)
        }
        #expect(context(follows: false).inputTime(5) == 5)
        #expect(abs(context(follows: true).inputTime(5) - 12.5) < 1e-6)
        // Each side sees the delta from its own lap.
        #expect(abs((context(follows: false).deltaToComparedLap(at: 5) ?? 0) - 2.5) < 1e-6)
        #expect(abs((context(follows: true).deltaToComparedLap(at: 5) ?? 0) + 2.5) < 1e-6)
        // A timer comparing with the compared lap.
        let timer = TimerRenderer(
            context: context(follows: false), params: TimerParams(mode: .deltaToBest, deltaReference: .comparedLap))
        #expect(timer.readout(sample: nil, projectTime: 5).text == "+2.50")
        let projected = TimerRenderer(
            context: context(follows: false), params: TimerParams(mode: .projectedLap, deltaReference: .comparedLap))
        #expect(projected.readout(sample: nil, projectTime: 5).text == "0:07.50")
        // Without a comparison nothing follows it.
        let plain = ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: nil, sync: .identity, cache: RenderCache(),
            followsComparedLap: true)
        #expect(plain.inputTime(5) == 5 && !plain.followsComparedLap)
    }

    @Test func aVideoObjectFollowingTheComparedLapDrawsItsOwnTrack() {
        let video = Input(label: "Cam", source: MediaReference(path: "/tmp/c.mp4"), kind: .video(VideoInputSettings()))
        let data = Input(label: "Log", source: MediaReference(path: "/tmp/l.csv"), kind: .data(DataInputSettings()))
        let lap = DisplayObject(label: "Lap", inputID: video.id, frame: .full, kind: .video(VideoObjectParams()))
        let compared = DisplayObject(
            label: "Compared", inputID: video.id, frame: .full, kind: .video(VideoObjectParams()),
            followsComparedLap: true)
        var project = Project(inputs: [video, data], displayObjects: [lap, compared])
        let side = LapComparisonSettings.Side(dataInputID: data.id, videoInputID: video.id, lap: 1)
        // Not comparing: the flag is ignored and both draw the camera's own track.
        #expect(RenderPlanner.videoLayers(for: project, trackIDs: [video.id: 1]).map(\.trackID) == [1, 1])
        project.lapComparison = LapComparisonSettings(lap: side, comparedLap: side)
        #expect(
            RenderPlanner.videoLayers(for: project, trackIDs: [video.id: 1], comparedTrackID: 9).map(\.trackID) == [
                1, 9,
            ])
        // Before the compared track exists it draws nothing rather than the wrong moment.
        #expect(RenderPlanner.videoLayers(for: project, trackIDs: [video.id: 1]).map(\.trackID) == [1])
    }
}
