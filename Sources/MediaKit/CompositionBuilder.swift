import AVFoundation
import Foundation
import ProjectModel
import RenderKit

/// One video file to place on the project timeline.
public struct VideoInputSpec: Sendable {
    public var url: URL
    public var sync: SyncSettings
    public var trim: TrimRange
    public var frame: UnitRect
    public var includeAudio: Bool
    public var audio: AudioSettings

    public init(
        url: URL, sync: SyncSettings = .identity, trim: TrimRange = .none, frame: UnitRect = .full,
        includeAudio: Bool = true, audio: AudioSettings = .neutral
    ) {
        self.url = url
        self.sync = sync
        self.trim = trim
        self.frame = frame
        self.includeAudio = includeAudio
        self.audio = audio
    }
}

/// The compiled AVFoundation objects for a project. Not Sendable: keep on the queue that built it.
public struct CompiledComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    /// Volume / balance / channel processing for the audio tracks, or `nil` when all are neutral.
    public let audioMix: AVMutableAudioMix?
    public let plan: RenderPlan
    /// Project duration in seconds.
    public let duration: Double
    /// Composition track ID per video input, in the order the inputs were given.
    public let trackIDs: [Int32]

    /// Returns a copy whose plan uses `videoLayers` (same overlays).
    public func replacingPlan(videoLayers: [VideoLayer]) -> CompiledComposition {
        replacingPlan(
            RenderPlan(
                outputWidth: plan.outputWidth, outputHeight: plan.outputHeight, frameRate: plan.frameRate,
                videoLayers: videoLayers, overlays: plan.overlays))
    }

    /// Returns a copy with a new plan (layers and overlays) and a freshly built video composition,
    /// leaving the media composition untouched. This is how live edits reach the preview.
    public func replacingPlan(_ newPlan: RenderPlan) -> CompiledComposition {
        let newVideoComposition = AVMutableVideoComposition()
        newVideoComposition.customVideoCompositorClass = OverlayCompositor.self
        newVideoComposition.renderSize = newPlan.outputSize
        newVideoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(newPlan.frameRate.rounded()))
        newVideoComposition.instructions = [
            CompositionBuilder.instruction(for: newPlan, duration: duration, timescale: 600)
        ]
        return CompiledComposition(
            composition: composition, videoComposition: newVideoComposition, audioMix: audioMix, plan: newPlan,
            duration: duration, trackIDs: trackIDs)
    }
}

public enum CompositionError: Error, CustomStringConvertible {
    case noVideoTrack(URL)
    case cannotAddTrack
    case emptyRange(URL)

    public var description: String {
        switch self {
        case .noVideoTrack(let url): "\(url.lastPathComponent) has no video track."
        case .cannotAddTrack: "Could not add a track to the composition."
        case .emptyRange(let url): "The selected range of \(url.lastPathComponent) is empty."
        }
    }
}

/// Builds an `AVMutableComposition` + `AVVideoComposition` (with `OverlayCompositor`) from video
/// inputs and overlays. The same result drives preview (`AVPlayerItem`) and export (`AVAssetReader`).
public enum CompositionBuilder {
    public static func build(
        videos: [VideoInputSpec],
        overlays: [any OverlayDrawing],
        outputWidth: Int,
        outputHeight: Int,
        frameRate: Double,
        duration explicitDuration: Double? = nil
    ) async throws -> CompiledComposition {
        let composition = AVMutableComposition()
        var layers: [VideoLayer] = []
        var audioTracks: [(track: AVMutableCompositionTrack, settings: AudioSettings)] = []
        var projectEnd = 0.0
        let timescale: CMTimeScale = 600

        for spec in videos {
            let asset = AVURLAsset(url: spec.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let assetDuration = try await asset.load(.duration).seconds
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw CompositionError.noVideoTrack(spec.url)
            }
            let inputStart = max(spec.trim.start ?? 0, spec.sync.startPositionInInput)
            let inputEnd = min(spec.trim.end ?? assetDuration, assetDuration)
            guard inputEnd > inputStart else { throw CompositionError.emptyRange(spec.url) }
            let inputRange = CMTimeRange(
                start: CMTime(seconds: inputStart, preferredTimescale: timescale),
                end: CMTime(seconds: inputEnd, preferredTimescale: timescale))
            let insertAt = CMTime(seconds: spec.sync.offsetInProject, preferredTimescale: timescale)
            let scaledDuration = CMTime(
                seconds: (inputEnd - inputStart) / spec.sync.playSpeed, preferredTimescale: timescale)

            guard
                let videoTrack = composition.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw CompositionError.cannotAddTrack }
            try videoTrack.insertTimeRange(inputRange, of: sourceVideo, at: insertAt)
            if spec.sync.playSpeed != 1 {
                videoTrack.scaleTimeRange(
                    CMTimeRange(start: insertAt, duration: inputRange.duration), toDuration: scaledDuration)
            }
            videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
            layers.append(VideoLayer(trackID: videoTrack.trackID, frame: spec.frame))

            if spec.includeAudio, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
                let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            {
                try audioTrack.insertTimeRange(inputRange, of: sourceAudio, at: insertAt)
                if spec.sync.playSpeed != 1 {
                    audioTrack.scaleTimeRange(
                        CMTimeRange(start: insertAt, duration: inputRange.duration), toDuration: scaledDuration)
                }
                audioTracks.append((audioTrack, spec.audio))
            }
            projectEnd = max(projectEnd, spec.sync.offsetInProject + scaledDuration.seconds)
        }

        let duration = explicitDuration ?? projectEnd
        let plan = RenderPlan(
            outputWidth: outputWidth, outputHeight: outputHeight, frameRate: frameRate, videoLayers: layers,
            overlays: overlays)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = OverlayCompositor.self
        videoComposition.renderSize = plan.outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        videoComposition.instructions = [Self.instruction(for: plan, duration: duration, timescale: timescale)]
        return CompiledComposition(
            composition: composition, videoComposition: videoComposition,
            audioMix: AudioMixBuilder.mix(for: audioTracks),
            plan: plan, duration: duration, trackIDs: layers.map(\.trackID))
    }

    static func instruction(for plan: RenderPlan, duration: Double, timescale: CMTimeScale) -> OverlayInstruction {
        OverlayInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: timescale)),
            plan: plan,
            sourceTrackIDs: plan.videoLayers.map(\.trackID))
    }
}
