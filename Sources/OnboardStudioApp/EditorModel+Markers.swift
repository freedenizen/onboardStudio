import Foundation
import ProjectModel

// MARK: - Markers (#54)

extension EditorModel {
    /// Adds a marker at the playhead and selects it.
    ///
    /// Which kind it is follows Resolve: with an input selected the marker belongs to that input
    /// and is stored in the input's own time, so re-syncing carries it along; with nothing
    /// selected it belongs to the timeline and stays at its timecode.
    @discardableResult
    func addMarkerAtPlayhead() -> MarkerID? {
        let time = currentTime
        let input = selectedObjectID == nil ? selectedInput : nil
        let marker = Marker(
            inputID: input?.id,
            time: input.map { $0.sync.inputTime(forProjectTime: time) } ?? time,
            name: defaultMarkerName())
        edit("Add Marker") { $0.markers.append(marker) }
        selectedMarkerID = marker.id
        selectedObjectID = nil
        selectedSegmentID = nil
        statusMessage =
            input.map { "Marker \(marker.name) added to \($0.label)." }
            ?? "Marker \(marker.name) added to the timeline."
        return marker.id
    }

    /// Markers are numbered rather than left blank so the list is usable before anything is named.
    private func defaultMarkerName() -> String {
        let used = project.markers.compactMap { marker -> Int? in
            guard marker.name.hasPrefix("Marker ") else { return nil }
            return Int(marker.name.dropFirst("Marker ".count))
        }
        return "Marker \((used.max() ?? 0) + 1)"
    }

    func deleteMarker(_ id: MarkerID) {
        guard project.markers.contains(where: { $0.id == id }) else { return }
        edit("Delete Marker") { $0.markers.removeAll { $0.id == id } }
        if selectedMarkerID == id { selectedMarkerID = nil }
    }

    func deleteSelectedMarker() {
        if let id = selectedMarkerID { deleteMarker(id) }
    }

    func updateMarker(_ id: MarkerID, name: String = "Edit Marker", _ change: (inout Marker) -> Void) {
        guard let index = project.markers.firstIndex(where: { $0.id == id }) else { return }
        edit(name) { change(&$0.markers[index]) }
    }

    func renameMarker(_ id: MarkerID, to name: String) {
        updateMarker(id, name: "Rename Marker") { $0.name = name }
    }

    /// Moves the playhead to the next marker after it, selecting that marker.
    @discardableResult
    func goToNextMarker() -> Bool { goTo(project.marker(after: currentTime)) }

    @discardableResult
    func goToPreviousMarker() -> Bool { goTo(project.marker(before: currentTime)) }

    private func goTo(_ target: PlacedMarker?) -> Bool {
        guard let target else {
            statusMessage = project.markers.isEmpty ? "No markers yet — press M to add one." : "No marker that way."
            return false
        }
        select(marker: target.marker.id, seekTo: target.start)
        statusMessage = target.marker.name
        return true
    }

    /// Where each marker sits on the project ruler, for the timeline and the marker list.
    var markersInProjectTime: [PlacedMarker] {
        project.markersInProjectTime()
    }
}

extension EditorModel {
    /// Adds a marker and asks for its name straight away, pausing playback so it can be typed.
    func addAndNameMarker() {
        if isPlaying { togglePlayback() }
        guard let id = addMarkerAtPlayhead() else { return }
        renameMarker(id)
    }

    func renameSelectedMarker() {
        if let id = selectedMarkerID { renameMarker(id) }
    }

    private func renameMarker(_ id: MarkerID) {
        guard let marker = project.markers.first(where: { $0.id == id }) else { return }
        guard let name = OpenPanels.askMarkerName(default: marker.name) else { return }
        renameMarker(id, to: name.trimmingCharacters(in: .whitespaces))
    }
}

extension EditorModel {
    var selectedMarker: Marker? {
        selectedMarkerID.flatMap { id in project.markers.first { $0.id == id } }
    }
}

extension EditorModel {
    /// Selects a marker and goes to it. Clears the other selections so the inspector shows the
    /// marker rather than whatever was selected before.
    func select(marker id: MarkerID, seekTo start: Double) {
        selectedMarkerID = id
        selectedObjectID = nil
        selectedSegmentID = nil
        seek(to: max(0, start))
    }
}
