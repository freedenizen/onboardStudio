import Foundation
import Testing

@testable import ProjectModel

@Suite("Markers")
struct MarkerTests {
    private func project(sync: SyncSettings = .identity) -> (Project, InputID) {
        let input = Input(
            label: "Data", source: MediaReference(path: "session.csv"), kind: .data(DataInputSettings()),
            sync: sync)
        return (Project(inputs: [input]), input.id)
    }

    @Test func aTimelineMarkerStaysAtItsTimecode() {
        var (project, _) = self.project()
        project.markers = [Marker(time: 12.5, name: "Braking")]

        let placed = project.markersInProjectTime()
        #expect(placed.count == 1)
        #expect(placed[0].start == 12.5 && placed[0].end == 12.5)
        #expect(!placed[0].marker.isRange, "no duration draws a flag, not a bar")
    }

    /// The reason an input's marker is stored in the input's own time: marking a braking point in
    /// the data and then fixing the sync must move the mark with the data, not leave it behind.
    @Test func anInputsMarkerTravelsWhenTheInputIsResynced() {
        var (project, id) = self.project()
        project.markers = [Marker(inputID: id, time: 100, name: "Braking")]
        #expect(project.markersInProjectTime()[0].start == 100)

        // Slide the data two seconds later on the timeline; the marker follows it.
        project.inputs[0].sync.offsetInProject = 2
        #expect(project.markersInProjectTime()[0].start == 102)

        // And at double speed the input's 100 s falls at half the distance from its offset.
        project.inputs[0].sync = SyncSettings(startPositionInInput: 0, offsetInProject: 0, playSpeed: 2)
        #expect(project.markersInProjectTime()[0].start == 50)
    }

    @Test func aRangeMarkerKeepsItsLengthThroughTheMapping() {
        var (project, id) = self.project(sync: SyncSettings(startPositionInInput: 0, offsetInProject: 0, playSpeed: 2))
        project.markers = [Marker(inputID: id, time: 100, duration: 20, name: "Sector 2")]

        let placed = project.markersInProjectTime()[0]
        #expect(placed.marker.isRange)
        #expect(placed.start == 50 && placed.end == 60, "20 s of a 2× input is 10 s on the timeline")
    }

    /// A marker whose input has been removed would otherwise be drawn at the wrong place.
    @Test func markersOfARemovedInputAreDropped() {
        var (project, id) = self.project()
        project.markers = [Marker(inputID: id, time: 10), Marker(time: 20)]
        project.inputs = []

        let placed = project.markersInProjectTime()
        #expect(placed.count == 1)
        #expect(placed[0].start == 20, "only the timeline marker survives")
    }

    @Test func markersAreReturnedInTimeOrderAcrossInputs() {
        var (project, id) = self.project(sync: SyncSettings(startPositionInInput: 0, offsetInProject: 30, playSpeed: 1))
        project.markers = [
            Marker(time: 50, name: "third"), Marker(inputID: id, time: 5, name: "second"),
            Marker(time: 1, name: "first"),
        ]
        #expect(project.markersInProjectTime().map(\.marker.name) == ["first", "second", "third"])
    }

    /// Jumping must be strictly past the playhead, or holding the shortcut sticks on the marker
    /// already under it.
    @Test func jumpingWalksTheListInsteadOfSticking() {
        var (project, _) = self.project()
        project.markers = [Marker(time: 10), Marker(time: 20), Marker(time: 30)]

        #expect(project.marker(after: 0)?.start == 10)
        #expect(project.marker(after: 10)?.start == 20, "sitting on one moves to the next")
        #expect(project.marker(after: 30) == nil)

        #expect(project.marker(before: 40)?.start == 30)
        #expect(project.marker(before: 20)?.start == 10)
        #expect(project.marker(before: 10) == nil)
    }

    /// Scrubbing to a marker leaves floating-point crumbs; without the tolerance the next jump
    /// would land back on the same marker.
    @Test func jumpingToleratesScrubbingRoundoff() {
        var (project, _) = self.project()
        project.markers = [Marker(time: 10), Marker(time: 20)]
        #expect(project.marker(after: 10.000000001)?.start == 20)
        #expect(project.marker(before: 19.999999999)?.start == 10)
    }

    /// Projects written before markers existed must still open, and must not gain a phantom one.
    @Test func projectsSavedBeforeMarkersStillOpen() throws {
        let json = """
            {"schemaVersion": 1, "inputs": [], "displayObjects": []}
            """
        let decoded = try Project.decode(Data(json.utf8))
        #expect(decoded.markers.isEmpty)
    }

    @Test func markersRoundTripThroughJSON() throws {
        var (project, id) = self.project()
        project.markers = [
            Marker(
                inputID: id, time: 3, duration: 1.5, name: "Turn 4",
                colour: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), note: "wide"),
            Marker(time: 9, name: "Flag"),
        ]
        let decoded = try Project.decode(try project.encoded())
        #expect(decoded.markers == project.markers)
        #expect(decoded.markers[0].note == "wide")
    }
}
