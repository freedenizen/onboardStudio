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

/// Decides how added files fit an existing project: chapters join their recording, a file already
/// in the project is not added twice, and every distinct recording gets its own lane so it can be
/// moved, trimmed and relabelled on its own. "Add Camera" is the same, except the new lane is
/// meant to play *alongside* the others rather than after them.
public enum InputPlanning {
    public static func plan(
        adding urls: [URL], to project: Project, asCamera: Bool = false, resolve: (MediaReference) -> URL
    ) -> [VideoAddition] {
        let present = presentFiles(in: project, resolve: resolve)
        var actions: [VideoAddition] = []
        for group in CameraChapters.group(urls) {
            var fresh: [URL] = []
            for url in group {
                if let owner = present[url.standardizedFileURL.path] {
                    actions.append(.alreadyPresent(url, in: owner))
                } else {
                    fresh.append(url)
                }
            }
            guard !fresh.isEmpty else { continue }
            // Later chapters of a recording already in the project join it; anything else is a
            // recording in its own right and opens its own lane.
            if !asCamera, let lane = continuedRecording(startingWith: fresh[0], present: present) {
                actions.append(.appendClips(to: lane, fresh))
            } else {
                actions.append(.newInput(fresh))
            }
        }
        return actions
    }

    /// The input holding the chapter that comes immediately before `url`, when there is one — i.e.
    /// `url` continues a recording the project already plays.
    static func continuedRecording(startingWith url: URL, present: [String: InputID]) -> InputID? {
        guard let previous = CameraChapters.previousChapter(of: url) else { return nil }
        return present[previous.standardizedFileURL.path]
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

extension Project {
    /// Gives lights and steering wheels that have no channel yet the one their data input offers
    /// (templates and object presets name none, because every logger names them differently).
    /// Returns the labels of the objects it bound.
    @discardableResult
    public mutating func bindEmptyChannels(_ channels: [InputID: [ChannelSummary]]) -> [String] {
        var bound: [String] = []
        for index in displayObjects.indices {
            let object = displayObjects[index]
            guard let inputID = object.inputID, let available = channels[inputID], !available.isEmpty else { continue }
            switch object.kind {
            case .indicator(let params) where params.channel.isEmpty:
                let adapted = params.adapted(to: available)
                guard !adapted.channel.isEmpty else { continue }
                displayObjects[index].kind = .indicator(adapted)
                bound.append(object.label)
            case .steeringWheel(let params) where params.channel.isEmpty:
                let adapted = params.adapted(to: available)
                guard !adapted.channel.isEmpty else { continue }
                displayObjects[index].kind = .steeringWheel(adapted)
                bound.append(object.label)
            default:
                continue
            }
        }
        return bound
    }
}
