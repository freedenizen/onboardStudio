import AVFoundation
import Foundation
import ProjectModel
import RenderKit

/// One video file to place on the project timeline.
/// One further file of a clip sequence: which part of it plays and the gap before it.
public struct ClipSpec: Sendable {
    public var url: URL
    public var trim: TrimRange
    public var gapBefore: Double
    /// This clip's own playback speed (1 = as recorded).
    public var speed: Double

    public init(url: URL, trim: TrimRange = .none, gapBefore: Double = 0, speed: Double = 1) {
        self.url = url
        self.trim = trim
        self.gapBefore = gapBefore
        self.speed = max(speed, 0.01)
    }
}

/// A source's orientation from a project time on (a clip sequence can change orientation at a
/// clip boundary).
public struct OrientationSpan: Sendable, Equatable {
    public let start: Double
    public let transform: CGAffineTransform

    public init(start: Double, transform: CGAffineTransform) {
        self.start = start
        self.transform = transform
    }
}

public struct VideoInputSpec: Sendable {
    public var url: URL
    /// Files played after `url` as one continuous video (camera chapters), each with its own trim
    /// and a gap before it. The input's own `trim` then applies to the whole sequence.
    public var clips: [ClipSpec]
    public var sync: SyncSettings
    public var trim: TrimRange
    public var frame: UnitRect
    public var includeAudio: Bool
    public var audio: AudioSettings

    public init(
        url: URL, clips: [ClipSpec] = [], sync: SyncSettings = .identity, trim: TrimRange = .none,
        frame: UnitRect = .full, includeAudio: Bool = true, audio: AudioSettings = .neutral
    ) {
        self.url = url
        self.clips = clips
        self.sync = sync
        self.trim = trim
        self.frame = frame
        self.includeAudio = includeAudio
        self.audio = audio
    }

    /// Every file of the sequence in playback order with its trim and gap.
    public var allClips: [ClipSpec] { [ClipSpec(url: url)] + clips }
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
    /// Orientation changes inside a clip sequence, per track, in project time (empty when a track
    /// keeps one orientation throughout).
    public let orientationSpans: [Int32: [OrientationSpan]]
    /// The compared lap's retimed picture, when the project compares laps (#154). Not one of
    /// `trackIDs`, which are one per video input in order.
    public let comparedTrackID: Int32?

    public init(
        composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix?,
        plans: [TimedPlan], duration: Double, trackIDs: [Int32], sourceTransforms: [Int32: CGAffineTransform]? = nil,
        orientationSpans: [Int32: [OrientationSpan]] = [:], comparedTrackID: Int32? = nil
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
        self.orientationSpans = orientationSpans
        self.comparedTrackID = comparedTrackID
    }

    /// Every track an instruction must require: each input's, and the compared lap's.
    var requiredTrackIDs: [Int32] { trackIDs + (comparedTrackID.map { [$0] } ?? []) }

    /// A copy that knows about the compared lap's track, already added to `composition` (#154).
    func addingComparedTrack(_ layer: VideoLayer) -> CompiledComposition {
        var transforms = sourceTransforms
        transforms[layer.trackID] = layer.sourceTransform
        return CompiledComposition(
            composition: composition, videoComposition: videoComposition, audioMix: audioMix, plans: plans,
            duration: duration, trackIDs: trackIDs, sourceTransforms: transforms, orientationSpans: orientationSpans,
            comparedTrackID: layer.trackID)
    }

    public init(
        composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix?,
        plan: RenderPlan, duration: Double, trackIDs: [Int32], orientationSpans: [Int32: [OrientationSpan]] = [:]
    ) {
        self.init(
            composition: composition, videoComposition: videoComposition, audioMix: audioMix,
            plans: [TimedPlan(start: 0, plan: plan)], duration: duration, trackIDs: trackIDs,
            orientationSpans: orientationSpans)
    }

    /// Returns a copy whose plan uses `videoLayers` (same overlays).
    public func replacingPlan(videoLayers: [VideoLayer]) -> CompiledComposition {
        replacingPlan(
            RenderPlan(
                outputWidth: plan.outputWidth, outputHeight: plan.outputHeight, frameRate: plan.frameRate,
                videoLayers: videoLayers, overlays: plan.overlays, background: plan.background,
                overlayOpacity: plan.overlayOpacity))
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
        newVideoComposition.instructions = CompositionBuilder.instructions(
            for: sorted, duration: duration, trackIDs: requiredTrackIDs)
        return CompiledComposition(
            composition: composition, videoComposition: newVideoComposition, audioMix: audioMix, plans: sorted,
            duration: duration, trackIDs: trackIDs, sourceTransforms: sourceTransforms,
            orientationSpans: orientationSpans, comparedTrackID: comparedTrackID)
    }

    /// The source transform of each track at project `time`.
    public func sourceTransforms(at time: Double) -> [Int32: CGAffineTransform] {
        var result = sourceTransforms
        for (track, spans) in orientationSpans {
            if let span = spans.last(where: { $0.start <= time + 1e-6 }) { result[track] = span.transform }
        }
        return result
    }

    /// Project times at which any track changes orientation (never 0).
    public var orientationChangeTimes: [Double] {
        Array(Set(orientationSpans.values.flatMap { $0.map(\.start) }.filter { $0 > 0 })).sorted()
    }
}

extension CompiledComposition {
    /// The same composition rendering only the overlays over `background` (key colour or
    /// transparent), for compositing in another editor.
    public func overlayOnly(background: RGBAColor) -> CompiledComposition {
        replacingPlans(plans.map { TimedPlan(start: $0.start, plan: $0.plan.overlayOnly(background: background)) })
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
        var orientationSpans: [Int32: [OrientationSpan]] = [:]
        let timescale: CMTimeScale = 600

        for spec in videos {
            let inserted = try await insert(spec, into: composition, timescale: timescale)
            layers.append(inserted.layer)
            if let audio = inserted.audioTrack { audioTracks.append((audio, spec.audio)) }
            if inserted.spans.count > 1 { orientationSpans[inserted.layer.trackID] = inserted.spans }
            projectEnd = max(projectEnd, inserted.end)
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
            plan: plan, duration: duration, trackIDs: layers.map(\.trackID), orientationSpans: orientationSpans)
    }

    /// What inserting one input produced.
    struct InsertedInput {
        let layer: VideoLayer
        let audioTrack: AVMutableCompositionTrack?
        let spans: [OrientationSpan]
        let end: Double
    }

    /// Inserts one input's clip sequence (video and audio) into the composition.
    static func insert(_ spec: VideoInputSpec, into composition: AVMutableComposition, timescale: CMTimeScale)
        async throws -> InsertedInput
    {
        let (clips, sequenceDuration) = try await loadClips(spec)
        guard let first = clips.first else { throw CompositionError.noVideoTrack(spec.url) }
        // A negative offset puts the head of the input before the project starts. Nothing can be
        // inserted at a negative time — AVFoundation rejects the whole composition with -11800 and
        // an underlying -12780 — so the part that falls off the front is dropped and the rest
        // begins at zero. The stored offset is left alone, so nudging back the other way restores
        // exactly what this took.
        let offset = spec.sync.startInProject
        let inputStart =
            max(spec.trim.start ?? 0, spec.sync.startPositionInInput) + spec.sync.inputSecondsBeforeProjectStart
        let inputEnd = min(spec.trim.end ?? sequenceDuration, sequenceDuration)
        guard inputEnd > inputStart else { throw CompositionError.emptyRange(spec.url) }
        let insertAt = CMTime(seconds: offset, preferredTimescale: timescale)
        let unscaled = CMTimeRange(
            start: insertAt, duration: CMTime(seconds: inputEnd - inputStart, preferredTimescale: timescale))
        let scaledDuration = CMTime(
            seconds: (inputEnd - inputStart) / spec.sync.playSpeed, preferredTimescale: timescale)

        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.cannotAddTrack }
        var audioTrack: AVMutableCompositionTrack?
        var spans: [OrientationSpan] = []
        for clip in clips {
            // The part of this clip inside the trimmed sequence window.
            let from = max(inputStart, clip.start)
            let to = min(inputEnd, clip.start + clip.duration)
            guard to > from else { continue }
            let range = CMTimeRange(
                start: CMTime(
                    seconds: clip.fileStart + (from - clip.start) * clip.speed, preferredTimescale: timescale),
                end: CMTime(seconds: clip.fileStart + (to - clip.start) * clip.speed, preferredTimescale: timescale))
            let at = CMTime(seconds: offset + (from - inputStart), preferredTimescale: timescale)
            try videoTrack.insertTimeRange(range, of: clip.video, at: at)
            if spec.includeAudio {
                audioTrack = try await insertAudio(
                    from: clip.asset, range: range, at: at, into: composition, track: audioTrack)
            }
            if clip.speed != 1 {
                // Squeeze (or stretch) just this clip so it occupies its sequence-axis length.
                let inserted = CMTimeRange(start: at, duration: range.duration)
                let target = CMTime(seconds: to - from, preferredTimescale: timescale)
                videoTrack.scaleTimeRange(inserted, toDuration: target)
                audioTrack?.scaleTimeRange(inserted, toDuration: target)
            }
            let transform = Self.ciTransform(clip.transform)
            if transform != spans.last?.transform ?? .identity || spans.isEmpty {
                let projectStart = offset + (from - inputStart) / spec.sync.playSpeed
                spans.append(OrientationSpan(start: projectStart, transform: transform))
            }
        }
        if spec.sync.playSpeed != 1 {
            videoTrack.scaleTimeRange(unscaled, toDuration: scaledDuration)
            audioTrack?.scaleTimeRange(unscaled, toDuration: scaledDuration)
        }
        // The composition track deliberately keeps an identity transform: the compositor applies
        // the source rotation itself, so AVFoundation must not apply it a second time when it
        // delivers source frames or displays the composed output.
        let layer = VideoLayer(
            trackID: videoTrack.trackID, frame: spec.frame, sourceTransform: Self.ciTransform(first.transform))
        return InsertedInput(
            layer: layer, audioTrack: audioTrack, spans: spans,
            end: offset + scaledDuration.seconds)
    }

    /// One file of a clip sequence and where its played part sits on the sequence's own time axis.
    struct LoadedClip {
        let asset: AVURLAsset
        let video: AVAssetTrack
        let transform: CGAffineTransform
        /// Sequence second at which the played part begins (after any gap).
        let start: Double
        /// Length on the sequence axis (the file's trimmed length divided by the clip's speed).
        let duration: Double
        /// File second at which the played part begins.
        let fileStart: Double
        /// File seconds per sequence second (the clip's own speed).
        let speed: Double
    }

    /// Loads every clip of the sequence; the sequence's time axis runs across the played parts in
    /// order, with each clip's gap (black) before it.
    static func loadClips(_ spec: VideoInputSpec) async throws -> ([LoadedClip], Double) {
        var clips: [LoadedClip] = []
        var cursor = 0.0
        for clip in spec.allClips {
            let asset = AVURLAsset(url: clip.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let assetDuration = try await asset.load(.duration).seconds
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw CompositionError.noVideoTrack(clip.url)
            }
            let transform = try await sourceVideo.load(.preferredTransform)
            let fileStart = min(max(clip.trim.start ?? 0, 0), assetDuration)
            let fileEnd = min(clip.trim.end ?? assetDuration, assetDuration)
            let played = max(0, fileEnd - fileStart) / clip.speed
            let start = cursor + max(0, clip.gapBefore)
            clips.append(
                LoadedClip(
                    asset: asset, video: sourceVideo, transform: transform, start: start, duration: played,
                    fileStart: fileStart, speed: clip.speed))
            cursor = start + played
        }
        return (clips, cursor)
    }

    /// Inserts one clip's audio (if it has any) into the input's audio track, creating the track
    /// on first use so a whole clip sequence shares one track and one mix setting.
    static func insertAudio(
        from asset: AVURLAsset, range: CMTimeRange, at: CMTime, into composition: AVMutableComposition,
        track existing: AVMutableCompositionTrack?
    ) async throws -> AVMutableCompositionTrack? {
        guard let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first else { return existing }
        guard
            let track = existing
                ?? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return existing }
        try track.insertTimeRange(range, of: sourceAudio, at: at)
        return track
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
    static func instructions(for plans: [TimedPlan], duration: Double, trackIDs: [Int32]) -> [OverlayInstruction] {
        let timescale: CMTimeScale = 600
        var result: [OverlayInstruction] = []
        for (index, timed) in plans.enumerated() where timed.start < duration {
            let end = index + 1 < plans.count ? min(plans[index + 1].start, duration) : duration
            guard end > timed.start else { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: timed.start, preferredTimescale: timescale),
                end: CMTime(seconds: end, preferredTimescale: timescale))
            // Every composition track is required by every instruction so switching cameras never
            // stalls on a track that was not being decoded (and overlay-only plans still get frames).
            result.append(OverlayInstruction(timeRange: range, plan: timed.plan, sourceTrackIDs: trackIDs))
        }
        return result
    }
}
