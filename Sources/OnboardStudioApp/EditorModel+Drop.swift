import Foundation
import Importers
import MediaKit
import ProjectModel
import UniformTypeIdentifiers

// MARK: - Adding files: chapters, drops, multi-select

extension EditorModel {
    /// Adds video files chosen together. Chapters of one recording become one input; every other
    /// recording gets its own, placed after the previous video so they play in turn; files already
    /// in the project are skipped. `asCamera` opens a lane that plays alongside the others
    /// (picture-in-picture) rather than after them.
    func addVideos(at urls: [URL], asCamera: Bool = false) {
        let plan = InputPlanning.plan(adding: urls, to: project, asCamera: asCamera) { location.resolve($0) }
        var notes: [String] = []
        for action in plan {
            switch action {
            case .alreadyPresent(let url, let owner):
                let label = project.input(owner)?.label ?? "the project"
                notes.append("\(url.lastPathComponent) is already part of \(label).")
            case .appendClips(let inputID, let files):
                appendRecording(files, to: inputID)
                notes.append(
                    "\(files.map(\.lastPathComponent).joined(separator: ", ")) joined "
                        + "\(project.input(inputID)?.label ?? "the video"): they are later chapters of the same "
                        + "recording.")
            case .newInput(let files):
                addVideoGroup(files, asCamera: asCamera)
                if files.count > 1 {
                    let names = files.dropFirst().map(\.lastPathComponent).joined(separator: ", ")
                    notes.append(
                        "Joined \(files.count - 1) chapter\(files.count == 2 ? "" : "s") (\(names)) onto "
                            + "\(files[0].deletingPathExtension().lastPathComponent); remove any in the Clips section.")
                }
            }
        }
        if !notes.isEmpty { statusMessage = notes.joined(separator: " ") }
    }

    /// Adds `url` as a video, joining the chapter files that follow it on disk.
    func addVideo(at url: URL) {
        addVideos(at: [url] + CameraChapters.following(url))
    }

    private func addVideoGroup(_ group: [URL], asCamera: Bool) {
        guard let first = group.first else { return }
        var settings = VideoInputSettings()
        settings.clips = group.dropFirst().map { VideoClip(source: MediaReference.make(for: $0, relativeTo: fileURL)) }
        let input = Input(
            label: first.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: first, relativeTo: fileURL), kind: .video(settings))
        // A second recording plays *after* the first, so it fills the frame like the first one and
        // starts where the previous video ends. A second camera plays *alongside*, so it comes in
        // as picture-in-picture at the same time.
        let previous = project.videoInputs.last
        let follows = !asCamera ? previous : nil
        edit(asCamera ? "Add Camera" : settings.clips.isEmpty ? "Add Video" : "Add Video with Chapters") { project in
            let cameras = project.videoInputs.count
            project.inputs.append(input)
            project.bindOrphanObjects()
            let bound = project.displayObjects.contains { $0.inputID == input.id }
            if !bound {
                // No template object was waiting: the first camera fills the frame, later ones start
                // as picture-in-picture so they show up at once.
                let pip = asCamera && cameras > 0
                let frame = LayoutPreset.pictureInPicture.frames(count: cameras + 1)[min(cameras, 2)] ?? .full
                var object = DisplayObject.makeDefault(kind: .video(VideoObjectParams()), inputID: input.id, index: 0)
                object.label = cameras == 0 ? "Camera" : input.label
                object.frame = pip ? frame : .full
                project.displayObjects.insert(object, at: cameras == 0 ? 0 : project.videoObjects.count)
            }
        }
        selectedInputID = input.id
        selectedObjectID = nil
        if let follows, let end = end(of: follows) {
            setOffset(of: input.id, to: end, name: "Add Video")
            leaveRecordingPause(before: input.id, after: follows, nextFile: group[0])
        }
        fillGaps(in: input.id, files: group, firstClipIndex: 0)
    }

    /// Appends a recording to a lane; the pause between the recordings becomes a gap.
    private func appendRecording(_ files: [URL], to inputID: InputID) {
        guard let input = project.input(inputID), case .video(let settings) = input.kind else { return }
        let previous = settings.clips.last.map { location.resolve($0.source) } ?? location.resolve(input.source)
        let firstNewIndex = settings.clips.count
        let references = files.map { VideoClip(source: MediaReference.make(for: $0, relativeTo: fileURL)) }
        updateInput(inputID, name: "Add Recording") { input in
            guard case .video(var settings) = input.kind else { return }
            settings.clips.append(contentsOf: references)
            input.kind = .video(settings)
        }
        selectedInputID = inputID
        fillGaps(in: inputID, files: [previous] + files, firstClipIndex: firstNewIndex)
    }

    /// Recordings used to share a lane, where the camera's pause between them became a clip gap.
    /// They are separate inputs now, so the same pause becomes the offset between them — a data
    /// log stays lined up across the join either way.
    private func leaveRecordingPause(before inputID: InputID, after previous: Input, nextFile: URL) {
        guard case .video(let settings) = previous.kind else { return }
        let last = settings.clips.last.map { location.resolve($0.source) } ?? location.resolve(previous.source)
        guard let end = end(of: previous) else { return }
        Task {
            guard let pause = await RecordingGaps.pause(between: last, and: nextFile), pause > 0.25 else { return }
            setOffset(of: inputID, to: end + pause, name: "Set Gap from Camera Clock")
            statusMessage =
                "Left a \(Self.clock(pause)) gap before \(nextFile.lastPathComponent): the camera was stopped that "
                + "long (drag its bar on the timeline to change it)."
        }
    }

    /// Where consecutive files are not chapters of one recording, and both carry a clock, leaves
    /// the real pause between them as the clip's gap so a data log stays lined up across the join.
    /// `files[0]` precedes the clip at `firstClipIndex`.
    private func fillGaps(in inputID: InputID, files: [URL], firstClipIndex: Int) {
        let boundaries = zip(files, files.dropFirst()).enumerated().filter { _, pair in
            CameraChapters.next(after: pair.0)?.standardizedFileURL.path != pair.1.standardizedFileURL.path
        }
        guard !boundaries.isEmpty else { return }
        Task {
            for (offset, pair) in boundaries {
                guard let gap = await RecordingGaps.pause(between: pair.0, and: pair.1), gap > 0.25 else { continue }
                let index = firstClipIndex + offset
                updateInput(inputID, name: "Set Gap from Camera Clock") { input in
                    guard case .video(var settings) = input.kind, settings.clips.indices.contains(index) else { return }
                    settings.clips[index].gapBefore = gap
                    input.kind = .video(settings)
                }
                statusMessage =
                    "Left a \(Self.clock(gap)) gap before \(pair.1.lastPathComponent): the camera was stopped that "
                    + "long (Clips section ▸ Gap before)."
            }
        }
    }

    /// Seconds as m:ss, or h:mm:ss past an hour. Shared with the sidebar.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return whole >= 3600
            ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
            : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    func addData(at url: URL) {
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL), kind: .data(DataInputSettings()))
        edit("Add Data") { project in
            project.inputs.append(input)
            project.bindOrphanObjects()
        }
        selectedInputID = input.id
        selectedObjectID = nil
        pendingAutoSync = input.id
        pendingTrackLookup = input.id
    }

    func addImage(at url: URL) {
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL), kind: .image(ImageInputSettings()))
        edit("Add Image") { $0.inputs.append(input) }
        selectedInputID = input.id
    }

    /// Files dropped on the window: videos (joined into recordings), images, or data logs.
    func addDroppedFiles(_ urls: [URL]) {
        var videos: [URL] = []
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if type.conforms(to: .movie) || type.conforms(to: .video)
                || ["mp4", "mov", "m4v", "mts", "m2ts", "avi", "mkv", "360"].contains(url.pathExtension.lowercased())
            {
                videos.append(url)
            } else if type.conforms(to: .image) {
                addImage(at: url)
            } else {
                addData(at: url)
            }
        }
        if !videos.isEmpty { addVideos(at: videos) }
    }
}
