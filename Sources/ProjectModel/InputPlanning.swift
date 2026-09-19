import Foundation

/// Where a video file added to a project should go.
public enum VideoAddition: Equatable, Sendable {
    /// The file is already the source or a clip of `inputID`.
    case alreadyPresent(URL, in: InputID)
    /// Play the files after the last clip of the project's only camera lane.
    case appendClips(to: InputID, [URL])
    /// A new video input (a new lane), the first file plus its chapters as clips.
    case newInput([URL])
}

/// Decides how added files fit an existing project, so "Add Video" does what a single-camera
/// editor expects: chapters join their recording, a second recording follows the first on the
/// same lane, and a file already in the project is not added twice. "Add Camera" always opens
/// a new lane for picture-in-picture layouts.
public enum InputPlanning {
    public static func plan(
        adding urls: [URL], to project: Project, asCamera: Bool = false, resolve: (MediaReference) -> URL
    ) -> [VideoAddition] {
        var present = presentFiles(in: project, resolve: resolve)
        let videoObjects = project.displayObjects.filter { if case .video = $0.kind { true } else { false } }
        let singleLane = project.videoInputs.count == 1 && videoObjects.count <= 1 ? project.videoInputs[0].id : nil
        // Several recordings chosen together for an empty single-camera project share one lane too.
        let oneLane = !asCamera && project.videoInputs.isEmpty && videoObjects.count <= 1
        var actions: [VideoAddition] = []
        var sequence: [URL] = []
        for group in CameraChapters.group(urls) {
            var fresh: [URL] = []
            for url in group {
                if let owner = present[url.standardizedFileURL.path] {
                    actions.append(.alreadyPresent(url, in: owner))
                } else if !sequence.contains(url) {
                    fresh.append(url)
                }
            }
            guard !fresh.isEmpty else { continue }
            if !asCamera, let lane = singleLane {
                actions.append(.appendClips(to: lane, fresh))
                for url in fresh { present[url.standardizedFileURL.path] = lane }
            } else if oneLane {
                sequence.append(contentsOf: fresh)
            } else {
                actions.append(.newInput(fresh))
            }
        }
        if !sequence.isEmpty { actions.append(.newInput(sequence)) }
        return actions
    }
}

extension InputPlanning {
    /// Every video file the project already plays, by standardised path, with the lane it is on.
    static func presentFiles(in project: Project, resolve: (MediaReference) -> URL) -> [String: InputID] {
        var present: [String: InputID] = [:]
        for input in project.videoInputs {
            present[resolve(input.source).standardizedFileURL.path] = input.id
            if case .video(let settings) = input.kind {
                for clip in settings.clips { present[resolve(clip.source).standardizedFileURL.path] = input.id }
            }
        }
        return present
    }
}

extension Project {
    /// Binds objects whose input is missing: data objects to the first data input, video objects
    /// to the video inputs in order (each input to at most one unbound object). Templates leave
    /// their objects unbound until the inputs arrive, and removed inputs leave orphans behind.
    public mutating func bindOrphanObjects() {
        let videoIDs = videoInputs.map(\.id)
        let dataID = dataInputs.first?.id
        var taken = Set<InputID>()
        for object in displayObjects {
            if case .video = object.kind, let id = object.inputID, videoIDs.contains(id) { taken.insert(id) }
        }
        for index in displayObjects.indices {
            let object = displayObjects[index]
            if case .video = object.kind {
                if let id = object.inputID, videoIDs.contains(id) { continue }
                guard let free = videoIDs.first(where: { !taken.contains($0) }) else { continue }
                displayObjects[index].inputID = free
                taken.insert(free)
            } else if object.kind.needsData {
                if let id = object.inputID, input(id)?.kind.isData == true { continue }
                displayObjects[index].inputID = dataID
            }
        }
    }
}
