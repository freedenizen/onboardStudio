import Foundation
import ProjectModel

/// Segment editing: overridable object properties, segment lifecycle and camera layouts.
extension EditorModel {
    // MARK: - Timeline

    /// Sets an overridable property: into the segment at the playhead when there is one,
    /// otherwise on the object itself.
    func setOverridable(_ id: DisplayObjectID, name: String, _ change: (inout ObjectOverride) -> Void) {
        if let segment = editingSegment {
            edit(name) { project in
                var override = project.timeline.segment(segment.id)?.overrides[id] ?? ObjectOverride()
                change(&override)
                project.timeline.setOverride(override, for: id, in: segment.id)
            }
        } else {
            edit(name) { project in
                guard let index = project.displayObjects.firstIndex(where: { $0.id == id }) else { return }
                var override = ObjectOverride()
                change(&override)
                override.apply(to: &project.displayObjects[index])
            }
        }
    }

    /// Whether the segment at the playhead sets `property` for `id`.
    func isOverriddenHere(_ property: OverridableProperty, _ id: DisplayObjectID) -> Bool {
        guard let segment = editingSegment else { return false }
        return project.timeline.overrides(property, of: id, in: segment.id)
    }

    /// Removes the segment-level override so the property is inherited again.
    func resetOverride(_ property: OverridableProperty, _ id: DisplayObjectID) {
        guard let segment = editingSegment else { return }
        edit("Inherit \(property.rawValue)") { project in
            project.timeline.update(property, for: id, in: segment.id) { override in
                switch property {
                case .isVisible: override.isVisible = nil
                case .frame: override.frame = nil
                case .opacity: override.opacity = nil
                }
            }
        }
    }

    @discardableResult
    func addSegmentAtPlayhead() -> SegmentID? {
        guard duration > 0 else { return nil }
        // Floor to the millisecond so the playhead is never a hair before the new segment.
        let time = (currentTime * 1000).rounded(.down) / 1000
        var id: SegmentID?
        edit("Add Segment") { project in
            id = project.timeline.addSegment(at: time, label: "Segment \(project.timeline.segments.count + 1)")
        }
        selectedSegmentID = id
        selectedObjectID = nil
        selectedInputID = nil
        seek(to: time)
        return id
    }

    func deleteSegment(_ id: SegmentID) {
        edit("Delete Segment") { $0.timeline.removeSegment(id) }
        if selectedSegmentID == id { selectedSegmentID = nil }
    }

    func shiftSegment(_ id: SegmentID, to start: Double) {
        edit("Move Segment") { $0.timeline.shiftSegment(id, to: min(max(start, 0), max(duration, 0))) }
    }

    func renameSegment(_ id: SegmentID, to label: String) {
        edit("Rename Segment") { project in
            guard let index = project.timeline.segments.firstIndex(where: { $0.id == id }) else { return }
            project.timeline.segments[index].label = label
        }
    }

    /// Arranges the video objects (main camera first) with a preset, in the segment at the
    /// playhead or on the objects themselves.
    func applyLayout(_ preset: LayoutPreset) {
        // Draw order: the bottom-most camera is the main one; insets draw above it.
        let overrides = preset.overrides(for: project.videoObjects.map(\.id))
        if let segment = editingSegment {
            edit("Layout: \(preset.displayName)") { project in
                for (id, override) in overrides {
                    var merged = project.timeline.segment(segment.id)?.overrides[id] ?? ObjectOverride()
                    merged.isVisible = override.isVisible
                    merged.frame = override.frame
                    project.timeline.setOverride(merged, for: id, in: segment.id)
                }
            }
        } else {
            edit("Layout: \(preset.displayName)") { project in
                for index in project.displayObjects.indices {
                    overrides[project.displayObjects[index].id]?.apply(to: &project.displayObjects[index])
                }
            }
        }
    }

    func updateObject(_ id: DisplayObjectID, name: String = "Edit Object", _ change: (inout DisplayObject) -> Void) {
        edit(name) { project in
            guard let index = project.displayObjects.firstIndex(where: { $0.id == id }) else { return }
            change(&project.displayObjects[index])
        }
    }

    func updateInput(_ id: InputID, name: String = "Edit Input", _ change: (inout Input) -> Void) {
        edit(name) { project in
            guard let index = project.inputs.firstIndex(where: { $0.id == id }) else { return }
            change(&project.inputs[index])
        }
    }
}
