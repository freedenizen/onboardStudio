import Foundation
import Importers
import ProjectModel
import UniformTypeIdentifiers

// MARK: - Adding files: chapters, drops, multi-select

extension EditorModel {
    /// Adds video files chosen together: chapters of one recording become one input, other files
    /// their own inputs. Joining is silent (the status line says what happened; undo splits it).
    func addVideos(at urls: [URL]) {
        for group in CameraChapters.group(urls) { addVideoGroup(group) }
    }

    /// Adds `url` as a video input, joining the chapter files that follow it on disk.
    func addVideo(at url: URL) {
        addVideoGroup([url] + CameraChapters.following(url))
    }

    private func addVideoGroup(_ group: [URL]) {
        guard let first = group.first else { return }
        var settings = VideoInputSettings()
        settings.clips = group.dropFirst().map { VideoClip(source: MediaReference.make(for: $0, relativeTo: fileURL)) }
        let input = Input(
            label: first.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: first, relativeTo: fileURL), kind: .video(settings))
        edit(settings.clips.isEmpty ? "Add Video" : "Add Video with Chapters") { project in
            project.inputs.append(input)
            if !project.displayObjects.contains(where: {
                if case .video = $0.kind { return true } else { return false }
            }) {
                project.displayObjects.insert(
                    DisplayObject.makeDefault(kind: .video(VideoObjectParams()), inputID: input.id, index: 0), at: 0)
            }
        }
        selectedInputID = input.id
        selectedObjectID = nil
        if !settings.clips.isEmpty {
            let names = group.dropFirst().map(\.lastPathComponent).joined(separator: ", ")
            statusMessage =
                "Joined \(settings.clips.count) chapter\(settings.clips.count == 1 ? "" : "s") (\(names)) onto "
                + "\(input.label); remove any of them in the Clips section."
        }
    }

    func addData(at url: URL) {
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL), kind: .data(DataInputSettings()))
        edit("Add Data") { $0.inputs.append(input) }
        selectedInputID = input.id
        selectedObjectID = nil
        pendingAutoSync = input.id
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
