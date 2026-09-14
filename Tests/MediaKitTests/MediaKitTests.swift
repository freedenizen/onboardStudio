import AVFoundation
import Foundation
import Testing
@testable import MediaKit

@Test func fixtureVideoIsReadable() async throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        .appending(path: "test-3s.mp4")
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    #expect(abs(duration.seconds - 3.0) < 0.1)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    #expect(tracks.count == 1)
}
