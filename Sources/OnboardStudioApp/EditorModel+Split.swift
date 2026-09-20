import Foundation
import ProjectModel

// MARK: - Splitting a video at the playhead (#54)

extension EditorModel {
    /// The input a split would act on: the selected one, or the only video when nothing is chosen.
    var splittableVideo: Input? {
        if selectedObjectID == nil, selectedMarkerID == nil, let input = selectedInput,
            input.kind.isVideo || input.kind.isData
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
        guard let source = splittableVideo else {
            statusMessage = "Select a video or data file on the timeline to split it."
            return
        }
        // Floor to the millisecond so the playhead is never a hair before the new segment.
        let time = (currentTime * 1000).rounded(.down) / 1000
        guard let split = splitTiming(of: source, atProjectTime: time) else {
            statusMessage = "Put the playhead inside \(source.label) to split it."
            return
        }

        var second = source
        second.id = InputID()
        second.label = nextSplitLabel(from: source.label)
        second.sync = split.secondSync
        switch source.kind {
        case .video(var settings):
            settings.trim = split.secondTrim
            second.kind = .video(settings)
        case .data(var settings):
            settings.trim = split.secondTrim
            second.kind = .data(settings)
        default:
            return
        }

        let newObjects = twinnedObjects(of: source, boundTo: second.id)

        edit(source.kind.isVideo ? "Split Video" : "Split Data") { project in
            guard let index = project.inputs.firstIndex(where: { $0.id == source.id }) else { return }
            switch project.inputs[index].kind {
            case .video(var first):
                first.trim.end = split.firstEnd
                project.inputs[index].kind = .video(first)
            case .data(var first):
                first.trim.end = split.firstEnd
                project.inputs[index].kind = .data(first)
            default: break
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
        statusMessage = "Split \(source.label) at the playhead."
    }

    /// A twin of every object reading `source`, bound to the other half.
    ///
    /// Data gauges as much as cameras: a `Segment`'s override can switch an object off, not
    /// switch its source. Each twin starts hidden — the segment turns it on at the cut, and
    /// without that it would draw over the first half from the very beginning.
    private func twinnedObjects(of source: Input, boundTo second: InputID) -> [DisplayObject: DisplayObject] {
        var twins: [DisplayObject: DisplayObject] = [:]
        for object in project.displayObjects where object.inputID == source.id {
            var copy = object
            copy.id = DisplayObjectID()
            copy.inputID = second
            copy.label = nextSplitLabel(from: object.label)
            copy.isVisible = false
            twins[object] = copy
        }
        return twins
    }

    /// Where the two halves fall, whichever kind of input is being cut. Video length comes from
    /// the file; a data session's from its own recorded time range.
    private func splitTiming(of input: Input, atProjectTime time: Double) -> VideoTrimming.Split? {
        switch input.kind {
        case .video(let settings):
            return VideoTrimming.split(
                input.sync, trim: settings.trim, atProjectTime: time,
                fullDuration: loaded?.mediaInfo[input.id]?.duration)
        case .data(let settings):
            guard let range = sessions[input.id]?.timeRange else { return nil }
            return VideoTrimming.split(
                input.sync, trim: settings.trim, atProjectTime: time, fullStart: range.lowerBound,
                fullDuration: range.upperBound)
        default:
            return nil
        }
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
