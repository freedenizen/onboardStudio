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

    public init(
        url: URL, sync: SyncSettings = .identity, trim: TrimRange = .none, frame: UnitRect = .full,
        includeAudio: Bool = true
    ) {
        self.url = url
        self.sync = sync
        self.trim = trim
        self.frame = frame
        self.includeAudio = includeAudio
    }
}

/// The compiled AVFoundation objects for a project. Not Sendable: keep on the queue that built it.
public struct CompiledComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let plan: RenderPlan
    /// Project duration in seconds.
    public let duration: Double

    /// Returns a copy whose plan uses `videoLayers` (same overlays), with the instruction rebuilt.
    public func replacingPlan(videoLayers: [VideoLayer]) -> CompiledComposition {
        let newPlan = RenderPlan(
            outputWidth: plan.outputWidth, outputHeight: plan.outputHeight, frameRate: plan.frameRate,
            videoLayers: videoLayers, overlays: plan.overlays)
        videoComposition.instructions = [
            CompositionBuilder.instruction(for: newPlan, duration: duration, timescale: 600)
        ]
        return CompiledComposition(
            composition: composition, videoComposition: videoComposition, plan: newPlan, duration: duration)
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
            composition: composition, videoComposition: videoComposition, plan: plan, duration: duration)
    }

    static func instruction(for plan: RenderPlan, duration: Double, timescale: CMTimeScale) -> OverlayInstruction {
        OverlayInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: timescale)),
            plan: plan,
            sourceTrackIDs: plan.videoLayers.map(\.trackID))
    }
}
