import Foundation
import ProjectModel
import TelemetryKit

/// Puts what a recording showed on a session's clock (#573), through a project's sync or a
/// clip's own recording time, so the suggestions can read it by corner.
extension VideoTraffic {
    /// Every file of a project's video input, the first then its chapters.
    public static func files(of camera: Input, in loaded: ProjectCompiler.LoadedProject) -> [URL] {
        guard case .video(let settings) = camera.kind else { return [] }
        return [loaded.location.resolve(camera.source)]
            + (loaded.clipURLs[camera.id] ?? settings.clips.map { loaded.location.resolve($0.source) })
    }

    /// What `camera` showed, in the session time of `data`, as the project lines the two up; `nil`
    /// until every file of the camera has been read.
    public static func samples(
        of camera: Input, for data: Input, in loaded: ProjectCompiler.LoadedProject, rule: Rule = Rule()
    ) -> [PictureSample]? {
        guard case .video(let settings) = camera.kind else { return nil }
        var samples: [PictureSample] = []
        for (index, file) in files(of: camera, in: loaded).enumerated() {
            guard let sightings = saved(for: file) else { return nil }
            let clip = index > 0 && index - 1 < settings.clips.count ? settings.clips[index - 1] : nil
            let start = loaded.chapters[camera.id]?.first { $0.index == index }?.start ?? 0
            let trimStart = clip?.trim.start ?? 0
            let speed = clip?.speed ?? 1
            samples += zip(sightings.times, sightings.widths).map { time, width in
                // The file's seconds → the camera's → the project's → the data's.
                let onCamera = start + (time - trimStart) / speed
                let project = camera.sync.projectTime(forInputTime: onCamera)
                return PictureSample(time: data.sync.inputTime(forProjectTime: project), carAhead: width > 0)
            }
        }
        return samples
    }

    /// What a recording showed, its files played back to back from `recordedAt` by the camera's
    /// clock, in `session`'s time; `nil` until every file has been read, or when the session is not
    /// on the clock.
    public static func samples(
        ofRecording files: [URL], recordedAt: Date, in session: TelemetrySession
    ) -> [PictureSample]? {
        var start = recordedAt.timeIntervalSince1970
        var samples: [PictureSample] = []
        for file in files {
            guard let sightings = saved(for: file) else { return nil }
            for (time, width) in zip(sightings.times, sightings.widths) {
                guard let at = session.sessionTime(forEpoch: start + time) else { return nil }
                samples.append(PictureSample(time: at, carAhead: width > 0))
            }
            start += sightings.duration
        }
        return samples
    }
}
