import AVFoundation
import Foundation
import ProjectModel

extension CompiledComposition {
    /// A copy that plays `map` (#442). Every track of the composition, the compared lap's too, is
    /// slowed, sped or held where the map says; the sound is muted there; the instructions are
    /// rebuilt in output time, carrying the map so each overlay is drawn at its project time.
    /// Mutates `composition` in place, as the compared lap's insertion does: call it once, on a
    /// freshly built composition.
    public func retimed(by map: TimeMap) -> CompiledComposition {
        guard !map.isIdentity else { return self }
        let timescale: CMTimeScale = 600
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: timescale) }
        let frame = CMTime(value: 1, timescale: CMTimeScale(plan.frameRate.rounded()))
        // Last first: scaling a range moves everything after it, so the project times of the
        // pieces still to do stay where they were.
        for piece in map.pieces.reversed() where piece.isRetimed {
            let length = time(piece.outputEnd - piece.outputStart)
            if piece.isHold {
                // A hold is one frame shown for longer: the frame at its moment, stretched by the
                // hold's length.
                composition.scaleTimeRange(
                    CMTimeRange(start: time(piece.projectStart), duration: frame), toDuration: frame + length)
            } else {
                composition.scaleTimeRange(
                    CMTimeRange(start: time(piece.projectStart), end: time(piece.projectEnd)), toDuration: length)
            }
        }
        let retimed = CompiledComposition(
            composition: composition, videoComposition: videoComposition,
            audioMix: Self.muting(audioMix, tracks: composition.tracks(withMediaType: .audio), over: map),
            plans: plans, duration: duration, trackIDs: trackIDs, sourceTransforms: sourceTransforms,
            orientationSpans: orientationSpans, comparedTrackID: comparedTrackID, timeMap: map)
        return retimed.replacingPlans(plans)
    }

    /// `mix` with every audio track silent over the map's retimed stretches, at the volume it had
    /// elsewhere: slowed or held sound is noise, not the moment.
    static func muting(
        _ mix: AVMutableAudioMix?, tracks: [AVMutableCompositionTrack], over map: TimeMap
    ) -> AVMutableAudioMix? {
        let ranges = map.retimedOutputRanges
        guard !ranges.isEmpty, !tracks.isEmpty else { return mix }
        let result = mix ?? AVMutableAudioMix()
        var parameters = result.inputParameters.compactMap { $0 as? AVMutableAudioMixInputParameters }
        for track in tracks where !parameters.contains(where: { $0.trackID == track.trackID }) {
            let added = AVMutableAudioMixInputParameters(track: track)
            added.setVolume(1, at: .zero)
            parameters.append(added)
        }
        for track in parameters {
            var volume: Float = 1
            _ = track.getVolumeRamp(for: .zero, startVolume: &volume, endVolume: nil, timeRange: nil)
            for range in ranges {
                track.setVolume(0, at: CMTime(seconds: range.lowerBound, preferredTimescale: 600))
                track.setVolume(volume, at: CMTime(seconds: range.upperBound, preferredTimescale: 600))
            }
        }
        result.inputParameters = parameters
        return result
    }
}
