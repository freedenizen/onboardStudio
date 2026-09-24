import AVFoundation
import Foundation
import ProjectModel
import RenderKit

extension CompositionBuilder {
    /// A video track of `spec` retimed by `warp` (#154): at every project time it shows the moment
    /// `warp` maps it to, so the compared lap's picture stays level with the lap playing.
    ///
    /// The lap is cut at the warp's knots and each piece is inserted and scaled to the time the lap
    /// playing took over the same stretch. To the compositor it is an ordinary track, which is what
    /// keeps preview and export identical. Measured on a 5.3K GoPro HEVC file, reading 60 s cut into
    /// 239 scaled pieces decoded as fast as reading it whole, so the cuts cost nothing.
    ///
    /// Video only: the compared lap's sound would be the same engine note at the wrong pitch.
    static func insertWarped(
        _ spec: VideoInputSpec, warp: LapTimeWarp, duration: Double, into composition: AVMutableComposition
    ) async throws -> VideoLayer {
        let (clips, sequenceDuration) = try await loadClips(spec)
        guard let first = clips.first else { throw CompositionError.noVideoTrack(spec.url) }
        guard
            let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.cannotAddTrack }
        let inputStart =
            max(spec.trim.start ?? 0, spec.sync.startPositionInInput) + spec.sync.inputSecondsBeforeProjectStart
        let inputEnd = min(spec.trim.end ?? sequenceDuration, sequenceDuration)
        let timescale: CMTimeScale = 600
        // Knots inside the project; outside the lap the warp is a straight line, one piece each side.
        let knots = [0] + warp.lapTimes.filter { $0 > 0 && $0 < duration } + [duration]
        var cursor = CMTime.zero
        for (from, to) in zip(knots, knots.dropFirst()) where to > from {
            // This stretch of the project, in the compared input's own time.
            let start = min(max(spec.sync.inputTime(forProjectTime: warp.comparedTime(at: from)), inputStart), inputEnd)
            let end = min(max(spec.sync.inputTime(forProjectTime: warp.comparedTime(at: to)), inputStart), inputEnd)
            guard end - start > 0.001 else { continue }
            for clip in clips {
                let pieceStart = max(start, clip.start)
                let pieceEnd = min(end, clip.start + clip.duration)
                guard pieceEnd > pieceStart else { continue }
                let fileStart = clip.fileStart + (pieceStart - clip.start) * clip.speed
                let fileEnd = clip.fileStart + (pieceEnd - clip.start) * clip.speed
                let source = CMTimeRange(
                    start: CMTime(seconds: fileStart, preferredTimescale: timescale),
                    end: CMTime(seconds: fileEnd, preferredTimescale: timescale))
                // Where the piece lands, as a share of this stretch of the project.
                let span = end - start
                let landAt = from + (to - from) * (pieceStart - start) / span
                let landEnd = from + (to - from) * (pieceEnd - start) / span
                // Never before the end of what is already there: inserting inside it would push it on.
                let at = max(CMTime(seconds: landAt, preferredTimescale: timescale), cursor)
                let until = CMTime(seconds: landEnd, preferredTimescale: timescale)
                guard until > at, source.duration > .zero else { continue }
                try track.insertTimeRange(source, of: clip.video, at: at)
                track.scaleTimeRange(CMTimeRange(start: at, duration: source.duration), toDuration: until - at)
                cursor = until
            }
        }
        return VideoLayer(trackID: track.trackID, frame: .full, sourceTransform: ciTransform(first.transform))
    }
}
