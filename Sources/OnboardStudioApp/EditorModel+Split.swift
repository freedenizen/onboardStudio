import Foundation
import ProjectModel

// MARK: - Splitting a video at the playhead (#54)

extension EditorModel {
    /// The video a split would act on: the selected one, or the only one when nothing is chosen.
    var splittableVideo: Input? {
        if selectedObjectID == nil, selectedMarkerID == nil, let input = selectedInput,
            case .video = input.kind
        {
            return input
        }
        return project.videoInputs.count == 1 ? project.videoInputs.first : nil
    }

    var canSplitAtPlayhead: Bool { splittableVideo != nil }

    /// Cuts the selected video at the playhead into two independent halves.
    ///
    /// A `Segment`'s override cannot change which input an object shows — camera switching works
    /// by showing one object and hiding another — so a split that actually plays needs four
    /// things, not one: the first half trimmed to the cut, a second input picking the file up
    /// there, a video object bound to it, and a segment at the cut that swaps the two. Doing less
    /// would leave the second half on the timeline but never on screen.
    func splitVideoAtPlayhead() {
        guard let video = splittableVideo, case .video(let settings) = video.kind else {
            statusMessage = "Select a video on the timeline to split it."
            return
        }
        // Floor to the millisecond so the playhead is never a hair before the new segment.
        let time = (currentTime * 1000).rounded(.down) / 1000
        guard
            let split = VideoTrimming.split(
                video.sync, trim: settings.trim, atProjectTime: time,
                fullDuration: loaded?.mediaInfo[video.id]?.duration)
        else {
            statusMessage = "Put the playhead inside \(video.label) to split it."
            return
        }

        var second = video
        second.id = InputID()
        second.label = nextSplitLabel(from: video.label)
        second.sync = split.secondSync
        var secondSettings = settings
        secondSettings.trim = split.secondTrim
        second.kind = .video(secondSettings)

        let objects = project.videoObjects.filter { $0.inputID == video.id }
        var newObjects: [DisplayObject: DisplayObject] = [:]
        for object in objects {
            var copy = object
            copy.id = DisplayObjectID()
            copy.inputID = second.id
            copy.label = nextSplitLabel(from: object.label)
            // Hidden until the cut. The segment turns it on there; without this it would draw
            // over the first half from the very beginning.
            copy.isVisible = false
            newObjects[object] = copy
        }

        edit("Split Video") { project in
            guard let index = project.inputs.firstIndex(where: { $0.id == video.id }) else { return }
            if case .video(var first) = project.inputs[index].kind {
                first.trim.end = split.firstEnd
                project.inputs[index].kind = .video(first)
            }
            project.inputs.insert(second, at: index + 1)
            for (original, copy) in newObjects {
                guard let at = project.displayObjects.firstIndex(where: { $0.id == original.id }) else { continue }
                project.displayObjects.insert(copy, at: at + 1)
            }
            // The segment swaps the halves over at the cut. Without it the second input would sit
            // on the timeline and never appear.
            let segment = project.timeline.addSegment(at: time, label: "Split")
            for (original, copy) in newObjects {
                project.timeline.setOverride(
                    ObjectOverride(isVisible: false), for: original.id, in: segment)
                project.timeline.setOverride(
                    ObjectOverride(isVisible: true), for: copy.id, in: segment)
            }
        }
        selectedInputID = second.id
        selectedObjectID = nil
        selectedMarkerID = nil
        statusMessage = "Split \(video.label) at the playhead."
    }

    /// "Camera" → "Camera 2" → "Camera 3": splitting twice should not make two things with the
    /// same name in the sidebar.
    private func nextSplitLabel(from label: String) -> String {
        let base: String
        if let space = label.lastIndex(of: " "), Int(label[label.index(after: space)...]) != nil {
            base = String(label[..<space])
        } else {
            base = label
        }
        let taken = Set(project.inputs.map(\.label) + project.displayObjects.map(\.label))
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
