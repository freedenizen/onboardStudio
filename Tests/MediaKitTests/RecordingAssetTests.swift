import AVFoundation
import Foundation
import Testing

@testable import MediaKit

@Suite("A recording as one asset (#516)", .media)
struct RecordingAssetTests {
    static let video = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/test-3s.mp4")

    @Test func chaptersPlayEndToEnd() async throws {
        let one = try await RecordingAsset.joined([Self.video]).load(.duration).seconds
        let two = try await RecordingAsset.joined([Self.video, Self.video]).load(.duration).seconds
        #expect(abs(one - 3) < 0.1)
        #expect(abs(two - 2 * one) < 0.05)
        let joined = try await RecordingAsset.joined([Self.video, Self.video])
        #expect(try await !joined.loadTracks(withMediaType: .video).isEmpty)
    }
}
