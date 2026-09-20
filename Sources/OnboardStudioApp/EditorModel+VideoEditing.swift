import Foundation
import MediaKit
import ProjectModel

// MARK: - Clip sequences, arrangement and framing (M15)

extension EditorModel {
    /// A new camera on its own lane, whatever the project already holds.
    func addCamera() {
        let urls = OpenPanels.chooseVideos(
            title: "Add Camera",
            message: "Choose the recording of another camera; it gets its own lane and a picture-in-picture window.")
        guard !urls.isEmpty else { return }
        addVideos(at: urls, asCamera: true)
    }

    /// Appends files to a video input's clip sequence.
    func addClips(to inputID: InputID) {
        let urls = OpenPanels.chooseVideos()
        guard !urls.isEmpty else { return }
        let references = urls.map { VideoClip(source: MediaReference.make(for: $0, relativeTo: fileURL)) }
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
        let last = settings.clips.last.map { location.resolve($0.source) } ?? location.resolve(input.source)
        let chapters = CameraChapters.following(last)
        guard !chapters.isEmpty else {
            statusMessage = "No further chapters found next to \(last.lastPathComponent)."
            return
        }
        let references = chapters.map { VideoClip(source: MediaReference.make(for: $0, relativeTo: fileURL)) }
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
                settings.clips.insert(VideoClip(source: input.source), at: 0)
                input.source = first.source
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

    /// The files a recording was split into, in order. Empty unless this input joins several,
    /// so callers can treat "no chapters" as "nothing worth showing".
    func chapters(of inputID: InputID) -> [ChapterSpan] { loaded?.chapters[inputID] ?? [] }

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

// MARK: - Timeline view state, snapping and trimming

extension EditorModel {
    /// The span the timeline draws: the project, or further if a video has been dragged past it.
    var timelineDuration: Double {
        max(duration, project.videoInputs.compactMap { end(of: $0) }.max() ?? 0, 0.001)
    }

    /// Targets the magnet snaps to: zero, the playhead and every other video's start and end.
    func snapTargets(excluding inputID: InputID? = nil) -> [Double] {
        var targets: [Double] = [0, currentTime]
        for video in project.videoInputs where video.id != inputID {
            targets.append(video.sync.offsetInProject)
            if let end = end(of: video) { targets.append(end) }
        }
        return targets
    }

    private var snapTolerance: Double { timelineDuration * 0.015 / timelineZoom }

    func snapped(_ time: Double, excluding inputID: InputID? = nil) -> Double {
        guard snappingEnabled else { return time }
        return TimelineSnapping(targets: snapTargets(excluding: inputID), tolerance: snapTolerance).snap(time)
    }

    func snappedSpan(start: Double, length: Double, excluding inputID: InputID? = nil) -> Double {
        guard snappingEnabled else { return start }
        return TimelineSnapping(targets: snapTargets(excluding: inputID), tolerance: snapTolerance)
            .snapSpan(start: start, length: length)
    }

    /// Moves the head of a video to project time `time`, keeping the picture where it was.
    func trimHead(of inputID: InputID, toProjectTime time: Double) {
        guard let video = project.input(inputID), case .video = video.kind else { return }
        let sync = VideoTrimming.headTrimmed(video.sync, toProjectTime: time)
        updateInput(inputID, name: "Trim Video Start") { $0.sync = sync }
    }

    /// Ends a video at project time `time` by setting its trim end (in file seconds).
    func trimTail(of inputID: InputID, toProjectTime time: Double) {
        guard let video = project.input(inputID), case .video(let settings) = video.kind else { return }
        let end = VideoTrimming.tailTrimmed(
            video.sync, trim: settings.trim, toProjectTime: time, fullDuration: loaded?.mediaInfo[inputID]?.duration)
        updateInput(inputID, name: "Trim Video End") { input in
            guard case .video(var s) = input.kind else { return }
            s.trim.end = end
            input.kind = .video(s)
        }
    }

    func zoomTimeline(by factor: Double) {
        timelineZoom = min(max(timelineZoom * factor, 1), 64)
    }

    func fitTimeline() { timelineZoom = 1 }
}

extension EditorModel {
    /// Edits one clip of a sequence (trim or gap).
    func updateClip(_ index: Int, in inputID: InputID, name: String, _ change: (inout VideoClip) -> Void) {
        updateInput(inputID, name: name) { input in
            guard case .video(var settings) = input.kind, settings.clips.indices.contains(index) else { return }
            change(&settings.clips[index])
            input.kind = .video(settings)
        }
    }
}

// MARK: - Viewer panning

extension EditorModel {
    /// Live update while dragging the picture (no undo entry per mouse move).
    func previewFraming(centerX: Double, centerY: Double) {
        var framing = project.settings.framing
        framing.centerX = min(max(centerX, 0), 1)
        framing.centerY = min(max(centerY, 0), 1)
        setFramingLive(framing)
    }

    /// One undoable step for the whole drag, registered against where it started.
    func commitFraming(centerX: Double, centerY: Double, from original: CGPoint) {
        var before = project.settings.framing
        before.centerX = original.x
        before.centerY = original.y
        var after = before
        after.centerX = min(max(centerX, 0), 1)
        after.centerY = min(max(centerY, 0), 1)
        setFramingLive(before)
        setFraming({ $0 = after }, name: "Pan Camera")
    }
}

extension EditorModel {
    /// Applies a framing without an undo entry (used while a drag is in progress).
    func setFramingLive(_ framing: CameraFraming) {
        document.apply(nil, name: "") { $0.settings.framing = framing }
        syncFromDocument()
    }
}

// MARK: - Trim to the playhead (#54)

extension EditorModel {
    /// Whether there is a video selected that trim-to-playhead could act on.
    var canTrimToPlayhead: Bool { selectedTrimmableVideo != nil }

    private var selectedTrimmableVideo: Input? {
        guard selectedObjectID == nil, selectedMarkerID == nil, let input = selectedInput,
            input.kind.isVideo || input.kind.isData
        else { return nil }
        return input
    }

    /// Where a trimmable input starts and ends on the project ruler. Video length comes from the
    /// file, a data session's from its own time range, so the two are asked separately.
    private func trimmableSpan(of input: Input) -> (start: Double, end: Double)? {
        if input.kind.isVideo {
            guard let end = end(of: input) else { return nil }
            return (input.sync.offsetInProject, end)
        }
        let span = dataSpan(of: input)
        return span.end > span.start ? span : nil
    }

    /// Trims a data input by moving its own trim, in the file's seconds.
    private func trimData(_ input: Input, toProjectTime time: Double, head: Bool) {
        let fileTime = input.sync.inputTime(forProjectTime: time)
        updateInput(input.id, name: head ? "Trim Data Start" : "Trim Data End") { updated in
            guard case .data(var settings) = updated.kind else { return }
            if head {
                settings.trim.start = fileTime
                // The picture and the data must still line up afterwards, so the input slides
                // along the timeline by as much as was dropped off its front.
                updated.sync.offsetInProject = time
                updated.sync.startPositionInInput = fileTime
            } else {
                settings.trim.end = fileTime
            }
            updated.kind = .data(settings)
        }
    }

    /// Drops everything before the playhead, as Resolve's Trim Start does.
    ///
    /// There is no separate "trim to marker": jump to the marker with ⇧↑/⇧↓, which puts the
    /// playhead on it, then trim — the same two steps Resolve uses, and one command rather than
    /// two that can disagree.
    func trimStartToPlayhead() {
        guard let input = selectedTrimmableVideo else {
            statusMessage = "Select a video or data file on the timeline to trim it."
            return
        }
        let time = currentTime
        guard let span = trimmableSpan(of: input), time > span.start, time < span.end else {
            statusMessage = "Put the playhead inside \(input.label) to trim it."
            return
        }
        if input.kind.isVideo {
            trimHead(of: input.id, toProjectTime: time)
        } else {
            trimData(input, toProjectTime: time, head: true)
        }
        statusMessage = "Trimmed the start of \(input.label) to the playhead."
    }

    /// Drops everything after the playhead, as Resolve's Trim End does.
    func trimEndToPlayhead() {
        guard let input = selectedTrimmableVideo else {
            statusMessage = "Select a video or data file on the timeline to trim it."
            return
        }
        let time = currentTime
        guard let span = trimmableSpan(of: input), time > span.start, time < span.end else {
            statusMessage = "Put the playhead inside \(input.label) to trim it."
            return
        }
        if input.kind.isVideo {
            trimTail(of: input.id, toProjectTime: time)
        } else {
            trimData(input, toProjectTime: time, head: false)
        }
        statusMessage = "Trimmed the end of \(input.label) to the playhead."
    }
}
