import Foundation
import MediaKit
import ProjectModel

// MARK: - Clip sequences, arrangement and framing (M15)

extension EditorModel {
    /// Appends files to a video input's clip sequence.
    func addClips(to inputID: InputID) {
        let urls = OpenPanels.chooseVideos()
        guard !urls.isEmpty else { return }
        let references = urls.map { MediaReference.make(for: $0, relativeTo: fileURL) }
        updateInput(inputID, name: "Add Clips") { input in
            guard case .video(var settings) = input.kind else { return }
            settings.clips.append(contentsOf: references)
            input.kind = .video(settings)
        }
        statusMessage = "Added \(urls.count) clip\(urls.count == 1 ? "" : "s") to the sequence."
    }

    /// Appends the camera's following chapter files, if any exist next to the first file.
    func addFollowingChapters(to inputID: InputID) {
        guard let input = project.input(inputID), case .video(let settings) = input.kind else { return }
        let last = settings.clips.last.map { location.resolve($0) } ?? location.resolve(input.source)
        let chapters = CameraChapters.following(last)
        guard !chapters.isEmpty else {
            statusMessage = "No further chapters found next to \(last.lastPathComponent)."
            return
        }
        let references = chapters.map { MediaReference.make(for: $0, relativeTo: fileURL) }
        updateInput(inputID, name: "Add Chapters") { input in
            guard case .video(var settings) = input.kind else { return }
            settings.clips.append(contentsOf: references)
            input.kind = .video(settings)
        }
        statusMessage = "Added \(chapters.count) chapter\(chapters.count == 1 ? "" : "s")."
    }

    func removeClip(_ index: Int, from inputID: InputID) {
        updateInput(inputID, name: "Remove Clip") { input in
            guard case .video(var settings) = input.kind, settings.clips.indices.contains(index) else { return }
            settings.clips.remove(at: index)
            input.kind = .video(settings)
        }
    }

    /// Moves a clip up (−1) or down (+1) in the sequence. Index 0 is the first clip after the
    /// input's own file; moving it up swaps it with that file.
    func moveClip(_ index: Int, by delta: Int, in inputID: InputID) {
        updateInput(inputID, name: "Reorder Clips") { input in
            guard case .video(var settings) = input.kind else { return }
            let target = index + delta
            if index == 0, target < 0 {
                // Swap the primary file with the first clip.
                let first = settings.clips.removeFirst()
                settings.clips.insert(input.source, at: 0)
                input.source = first
            } else if settings.clips.indices.contains(index), settings.clips.indices.contains(target) {
                settings.clips.swapAt(index, target)
            } else {
                return
            }
            input.kind = .video(settings)
        }
    }

    /// Project seconds at which a video input ends (its offset plus its played length).
    func end(of video: Input) -> Double? {
        guard let info = loaded?.mediaInfo[video.id], case .video(let settings) = video.kind else { return nil }
        let start = max(settings.trim.start ?? 0, video.sync.startPositionInInput)
        let stop = min(settings.trim.end ?? info.duration, info.duration)
        return video.sync.offsetInProject + max(0, stop - start) / max(video.sync.playSpeed, 0.001)
    }

    /// The video input listed before `inputID`, if any.
    func previousVideo(before inputID: InputID) -> Input? {
        let videos = project.videoInputs
        guard let index = videos.firstIndex(where: { $0.id == inputID }), index > 0 else { return nil }
        return videos[index - 1]
    }

    /// Places a video input so it starts exactly when the previous video input ends.
    func chainAfterPreviousVideo(_ inputID: InputID) {
        guard let previous = previousVideo(before: inputID), let end = end(of: previous) else {
            statusMessage = "There is no earlier video to follow."
            return
        }
        setOffset(of: inputID, to: end, name: "Chain After Previous Video")
    }

    func setOffset(of inputID: InputID, to seconds: Double, name: String = "Move Video") {
        let value = (max(0, seconds) * 1000).rounded() / 1000
        updateInput(inputID, name: name) { $0.sync.offsetInProject = value }
    }

    /// Moves a video input up or down in the input list (which is also the chaining order).
    func moveInput(_ inputID: InputID, by delta: Int) {
        edit("Reorder Inputs") { project in
            guard let index = project.inputs.firstIndex(where: { $0.id == inputID }) else { return }
            let target = index + delta
            guard project.inputs.indices.contains(target) else { return }
            project.inputs.swapAt(index, target)
        }
    }

    func setFraming(_ change: (inout CameraFraming) -> Void, name: String = "Change Camera Framing") {
        edit(name) { change(&$0.settings.framing) }
    }

    /// Whether the guided checklist has anything left to suggest.
    var gettingStartedSteps: [GettingStartedStep] {
        let hasVideo = !project.videoInputs.isEmpty
        let hasData = !project.dataInputs.isEmpty
        let synced = project.dataInputs.contains { $0.sync != .identity } || !hasData
        let hasOverlays = project.displayObjects.contains { $0.kind.isOverlay }
        let gopro = project.videoInputs.first.flatMap { loaded?.mediaInfo[$0.id] }
        return [
            GettingStartedStep(
                title: "Add a video", done: hasVideo,
                detail: "A GoPro, dash cam or phone clip. Chapters of one recording are joined automatically.",
                action: .addVideo),
            GettingStartedStep(
                title: "Add the data", done: hasData,
                detail: gopro?.hasGPMF == true
                    ? "This GoPro clip has GPS inside it; use it, or add a RaceChrono/GPX/CSV log."
                    : "A RaceChrono export, GPX, FIT, CSV or the camera's own log.",
                action: gopro?.hasGPMF == true && !hasData ? .useEmbedded : .addData),
            GettingStartedStep(
                title: "Line the data up with the video", done: hasData && synced,
                detail: "Timestamps do it automatically for most files; otherwise Auto-Sync by Motion or the wizard.",
                action: .sync),
            GettingStartedStep(
                title: "Add gauges", done: hasOverlays,
                detail: "Start from a template, then drag objects around the preview and tune them in the inspector.",
                action: .applyTemplate),
            GettingStartedStep(
                title: "Export", done: false, detail: "Render the video, then upload it to YouTube.", action: .export),
        ]
    }
}

struct GettingStartedStep: Identifiable {
    enum Action {
        case addVideo, addData, useEmbedded, sync, applyTemplate, export
    }

    let title: String
    let done: Bool
    let detail: String
    let action: Action
    var id: String { title }
}
