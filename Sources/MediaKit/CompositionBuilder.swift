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
    /// The plan in effect at time 0 (the only one without timeline segments).
    public let plan: RenderPlan
    /// One plan per timeline cut point, in time order; `plans[0].start == 0`.
    public let plans: [TimedPlan]
    /// Project duration in seconds.
    public let duration: Double
    /// Composition track ID per video input, in the order the inputs were given.
    public let trackIDs: [Int32]
    /// Each video track's display rotation (Core Image convention), kept here so a track that is
    /// hidden in every current plan still renders upright when a later plan shows it.
    public let sourceTransforms: [Int32: CGAffineTransform]

    public init(
        composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix?,
        plans: [TimedPlan], duration: Double, trackIDs: [Int32], sourceTransforms: [Int32: CGAffineTransform]? = nil
    ) {
        precondition(!plans.isEmpty, "a composition needs at least one plan")
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.plans = plans
        self.plan = plans[0].plan
        self.duration = duration
        self.trackIDs = trackIDs
        self.sourceTransforms =
            sourceTransforms
            ?? Dictionary(
                plans.flatMap { $0.plan.videoLayers.map { ($0.trackID, $0.sourceTransform) } },
                uniquingKeysWith: { first, _ in first })
    }

    public init(
        composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix?,
        plan: RenderPlan, duration: Double, trackIDs: [Int32]
    ) {
        self.init(
            composition: composition, videoComposition: videoComposition, audioMix: audioMix,
            plans: [TimedPlan(start: 0, plan: plan)], duration: duration, trackIDs: trackIDs)
    }

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
        replacingPlans([TimedPlan(start: 0, plan: newPlan)])
    }

    /// Like `replacingPlan` with one plan per timeline segment: each becomes a video composition
    /// instruction covering its time span, so camera switches and moves happen at exact frames.
    public func replacingPlans(_ newPlans: [TimedPlan]) -> CompiledComposition {
        let sorted = newPlans.sorted { $0.start < $1.start }
        precondition(sorted.first?.start == 0, "the first plan must start at 0")
        let first = sorted[0].plan
        let newVideoComposition = AVMutableVideoComposition()
        newVideoComposition.customVideoCompositorClass = OverlayCompositor.self
        newVideoComposition.renderSize = first.outputSize
        newVideoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(first.frameRate.rounded()))
        newVideoComposition.instructions = CompositionBuilder.instructions(for: sorted, duration: duration)
        return CompiledComposition(
            composition: composition, videoComposition: newVideoComposition, audioMix: audioMix, plans: sorted,
            duration: duration, trackIDs: trackIDs, sourceTransforms: sourceTransforms)
    }
}

/// A render plan that applies from `start` until the next plan begins.
public struct TimedPlan: Sendable {
    public let start: Double
    public let plan: RenderPlan

    public init(start: Double, plan: RenderPlan) {
        self.start = start
        self.plan = plan
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
            // The composition track deliberately keeps an identity transform: the compositor applies
            // the source rotation itself, so AVFoundation must not apply it a second time when it
            // delivers source frames or displays the composed output.
            let preferredTransform = try await sourceVideo.load(.preferredTransform)
            layers.append(
                VideoLayer(
                    trackID: videoTrack.trackID, frame: spec.frame,
                    sourceTransform: Self.ciTransform(preferredTransform)))

            let timing = TrackTiming(
                range: inputRange, insertAt: insertAt, scaledDuration: scaledDuration, playSpeed: spec.sync.playSpeed)
            if spec.includeAudio, let audioTrack = try await addAudioTrack(from: asset, to: composition, timing: timing)
            {
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

    /// Where an input's samples land on the project timeline.
    struct TrackTiming {
        let range: CMTimeRange
        let insertAt: CMTime
        let scaledDuration: CMTime
        let playSpeed: Double
    }

    /// Inserts the asset's first audio track (if any) into the composition, mirroring the video timing.
    static func addAudioTrack(
        from asset: AVURLAsset, to composition: AVMutableComposition, timing: TrackTiming
    ) async throws -> AVMutableCompositionTrack? {
        guard let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        try audioTrack.insertTimeRange(timing.range, of: sourceAudio, at: timing.insertAt)
        if timing.playSpeed != 1 {
            audioTrack.scaleTimeRange(
                CMTimeRange(start: timing.insertAt, duration: timing.range.duration), toDuration: timing.scaledDuration)
        }
        return audioTrack
    }

    /// AVFoundation's preferred transform is expressed in a top-left coordinate system; Core Image
    /// uses bottom-left. Rotations by multiples of 90° convert by inverting the sign of the
    /// rotation (equivalently, conjugating with a vertical flip); pure translations are dropped
    /// because the compositor re-normalises the origin.
    static func ciTransform(_ t: CGAffineTransform) -> CGAffineTransform {
        guard t != .identity else { return .identity }
        return CGAffineTransform(a: t.a, b: -t.b, c: -t.c, d: t.d, tx: 0, ty: 0)
    }

    static func instruction(for plan: RenderPlan, duration: Double, timescale: CMTimeScale) -> OverlayInstruction {
        OverlayInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: timescale)),
            plan: plan,
            sourceTrackIDs: plan.videoLayers.map(\.trackID))
    }

    /// One instruction per plan, tiling `0..<duration` exactly (AVFoundation rejects gaps and overlaps).
    static func instructions(for plans: [TimedPlan], duration: Double) -> [OverlayInstruction] {
        let timescale: CMTimeScale = 600
        var result: [OverlayInstruction] = []
        for (index, timed) in plans.enumerated() where timed.start < duration {
            let end = index + 1 < plans.count ? min(plans[index + 1].start, duration) : duration
            guard end > timed.start else { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: timed.start, preferredTimescale: timescale),
                end: CMTime(seconds: end, preferredTimescale: timescale))
            // Every source track is required by every instruction so switching cameras never
            // stalls on a track that was not being decoded.
            let allTracks = Set(plans.flatMap { $0.plan.videoLayers.map(\.trackID) })
            result.append(
                OverlayInstruction(timeRange: range, plan: timed.plan, sourceTrackIDs: Array(allTracks).sorted()))
        }
        return result
    }
}
