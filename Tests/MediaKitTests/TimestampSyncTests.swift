import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel
@testable import TelemetryKit

@Suite("Timestamp sync")
struct TimestampSyncTests {
    func session(epoch: Bool) -> TelemetrySession {
        let base = epoch ? 1_787_528_164.0 : 0.0
        var info = SessionInfo(sourceFormat: "test")
        if !epoch { info.createdAt = Date(timeIntervalSince1970: 1_787_528_164) }
        return TelemetrySession(
            info: info,
            channels: [
                Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [base, base + 100], values: [1, 2])
            ])
    }

    @Test func absoluteTimeHelpers() {
        let epochSession = session(epoch: true)
        #expect(epochSession.timesAreEpoch && epochSession.hasAbsoluteTime)
        #expect(epochSession.epoch(forSessionTime: 1_787_528_200) == 1_787_528_200)
        #expect(epochSession.sessionTime(forEpoch: 5) == 5)
        let relative = session(epoch: false)
        #expect(!relative.timesAreEpoch && relative.hasAbsoluteTime)
        #expect(relative.epoch(forSessionTime: 10) == 1_787_528_174)
        #expect(relative.sessionTime(forEpoch: 1_787_528_174) == 10)
        let none = TelemetrySession(info: SessionInfo(sourceFormat: "x"), channels: [])
        #expect(!none.hasAbsoluteTime && none.sessionTime(forEpoch: 1) == nil)
    }

    @Test func suggestsTheStartPositionFromTheClocks() {
        // The video started 14 s after the data session (the real GoPro/RaceChrono relationship).
        let videoStart = 1_787_528_178.0
        let plain = TimestampSync.suggest(
            data: session(epoch: true), video: SyncSettings(), videoStartEpoch: videoStart, videoClock: "GPS")
        #expect(plain?.sync.startPositionInInput == videoStart)
        #expect(plain?.sync.offsetInProject == 0 && plain?.sync.playSpeed == 1)
        // A trimmed, offset, sped-up video: the data follows the same mapping.
        let videoSync = SyncSettings(startPositionInInput: 30, offsetInProject: 2, playSpeed: 2)
        let trimmed = TimestampSync.suggest(
            data: session(epoch: false), video: videoSync, videoStartEpoch: videoStart, videoClock: "file")
        #expect(trimmed?.sync.startPositionInInput == 44.0)
        #expect(trimmed?.sync.offsetInProject == 2 && trimmed?.sync.playSpeed == 2)
        // Project time 2 shows video time 30 → wall clock videoStart + 30 → data time 44.
        #expect(trimmed?.sync.inputTime(forProjectTime: 2) == 44)
        let none = TelemetrySession(info: SessionInfo(sourceFormat: "x"), channels: [])
        #expect(
            TimestampSync.suggest(data: none, video: SyncSettings(), videoStartEpoch: videoStart, videoClock: "x")
                == nil)
    }

    @Test func recordingStartFallsBackToTheCreationDate() async throws {
        let url = try MediaFixtures.video
        var info = try await MediaProbe.probe(url)
        #expect(!info.hasGPMF)
        // The test fixture has no creation date, so there is no clock at all…
        if info.creationDate == nil {
            #expect(TimestampSync.recordingStart(of: url, info: info) == nil)
        }
        // …but one supplied by the container is used, labelled as such.
        info.creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let start = TimestampSync.recordingStart(of: url, info: info)
        #expect(start?.epoch == 1_700_000_000 && start?.source == "file creation time")
    }
}

@Suite("Companion telemetry")
struct CompanionTelemetryTests {
    @Test func findsADJILogNextToTheVideoAndUsesItsClock() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "companion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appending(path: "DJI_0001.MP4")
        try FileManager.default.copyItem(at: try MediaFixtures.video, to: video)
        #expect(CompanionTelemetry.find(for: video) == nil)
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        try FileManager.default.copyItem(
            at: fixtures.appending(path: "dji-osmo.srt"), to: dir.appending(path: "DJI_0001.SRT"))
        let companion = try #require(CompanionTelemetry.find(for: video))
        #expect(companion.importerID == "dji-srt")
        let info = try await MediaProbe.probe(video)
        #expect(info.companion == companion)
        let start = try #require(TimestampSync.recordingStart(of: video, info: info))
        #expect(start.source == "DJI SRT clock")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: Date(timeIntervalSince1970: start.epoch))
        #expect(parts.hour == 14 && parts.minute == 5 && parts.second == 10)
    }

    @Test func readsASonySidecarDate() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sony-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appending(path: "C0001.MP4")
        try Data().write(to: video)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.00">
        <CreationDate value="2024-06-02T14:05:10+02:00"/>
        </NonRealTimeMeta>
        """.write(to: dir.appending(path: "C0001M01.XML"), atomically: true, encoding: .utf8)
        let date = try #require(CompanionTelemetry.sonyCreationDate(for: video))
        #expect(date.timeIntervalSince1970 == 1_717_329_910)
    }
}
