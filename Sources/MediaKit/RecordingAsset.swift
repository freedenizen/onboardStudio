import AVFoundation
import Foundation

/// A camera recording as one asset to play (#516): its first file, and every chapter after it end
/// to end — a GoPro splits a long recording into 4 GB files, and a corner can fall across two.
public enum RecordingAsset {
    public static func joined(_ urls: [URL]) async throws -> AVAsset {
        // One file needs no joining.
        if urls.count == 1, let only = urls.first { return AVURLAsset(url: only) }
        let composition = AVMutableComposition()
        var video: AVMutableCompositionTrack?
        var audio: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if let picture = try await asset.loadTracks(withMediaType: .video).first {
                if video == nil {
                    video = composition.addMutableTrack(
                        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try video?.insertTimeRange(range, of: picture, at: cursor)
            }
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                if audio == nil {
                    audio = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try audio?.insertTimeRange(range, of: sound, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        return composition
    }
}
