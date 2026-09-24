import Foundation
import GPMFKit
import ProjectModel
import RenderKit
import TelemetryKit

// Loading and steadying video from the camera's motion data (#262).
extension ProjectCompiler {
    /// Probes a video or audio input — reusing what `previous` found while it is unchanged — and reads
    /// the camera's orientation for a video steadied from its motion data (#262).
    static func loadMedia(
        _ input: Input, url: URL, unchanged: Bool, previous: LoadedProject?, into loaded: inout LoadedProject
    ) async throws {
        if unchanged, let cached = previous?.mediaInfo[input.id] {
            loaded.mediaInfo[input.id] = cached
            loaded.mediaURLs[input.id] = previous?.mediaURLs[input.id]
            loaded.clipURLs[input.id] = previous?.clipURLs[input.id]
            loaded.chapters[input.id] = previous?.chapters[input.id]
        } else {
            let playable = try await FFmpegBridge.prepare(url)
            var info = try await MediaProbe.probe(playable)
            if playable != url { loaded.mediaURLs[input.id] = playable }
            if case .video(let settings) = input.kind, !settings.clips.isEmpty {
                let clips = try await loadClips(settings.clips, location: loaded.location)
                loaded.chapters[input.id] = ChapterSpan.layout(
                    firstName: input.source.displayName, firstDuration: info.duration,
                    clips: settings.clips, playedDurations: clips.played)
                info.duration += clips.duration
                loaded.clipURLs[input.id] = clips.urls
            }
            loaded.mediaInfo[input.id] = info
        }
        if case .video(let settings) = input.kind, settings.stabilisation.method == .motionData,
            loaded.mediaInfo[input.id]?.hasGPMF == true
        {
            loaded.orientations[input.id] = try Self.orientation(
                of: input, settings: settings, in: loaded, url: url, previous: previous)
        }
    }

    /// The orientation of a video input's whole sequence: each file's record moved to where that
    /// file plays. Kept from `previous` while the files and their trims are what they were, so moving
    /// a stabilisation slider does not read a long recording again.
    static func orientation(
        of input: Input, settings: VideoInputSettings, in loaded: LoadedProject, url: URL, previous: LoadedProject?
    ) throws -> CameraOrientationTrack? {
        if let cached = previous?.orientations[input.id], let before = previous?.project.input(input.id),
            before.source == input.source, case .video(let old) = before.kind, old.clips == settings.clips
        {
            return cached
        }
        let files = [url] + (loaded.clipURLs[input.id] ?? settings.clips.map { loaded.location.resolve($0.source) })
        let spans = loaded.chapters[input.id]
        var result: CameraOrientationTrack?
        for (index, file) in files.enumerated() {
            guard var track = try GoProTelemetry.orientation(of: file) else { continue }
            let clip = index > 0 && index - 1 < settings.clips.count ? settings.clips[index - 1] : nil
            let start = spans?.first { $0.index == index }?.start ?? 0
            let trimStart = clip?.trim.start ?? 0
            let speed = clip?.speed ?? 1
            track.times = track.times.map { start + ($0 - trimStart) / speed }
            if var combined = result {
                combined.times += track.times
                combined.camera += track.camera
                combined.image += track.image
                result = combined
            } else {
                result = track
            }
        }
        return result
    }

    /// Each steadied video input's path, from its orientation and its own settings.
    static func stabilisationPaths(for loaded: LoadedProject) -> [InputID: StabilisationPath] {
        var paths: [InputID: StabilisationPath] = [:]
        for input in loaded.project.inputs {
            guard case .video(let settings) = input.kind, settings.stabilisation.method == .motionData,
                let track = loaded.orientations[input.id],
                // Footage HyperSmooth already steadied is not steadied again from CORI: how its image
                // orientation (IORI) combines has not been measured, and a wrong guess shakes it more.
                !track.stabilisedInCamera
            else { continue }
            let stabilisation = settings.stabilisation
            paths[input.id] = StabilisationPath(
                track: track, smoothing: stabilisation.smoothing, maxShift: stabilisation.maxShift)
        }
        return paths
    }
}
