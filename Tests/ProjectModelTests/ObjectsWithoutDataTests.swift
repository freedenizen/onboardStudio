import Foundation
import Testing

@testable import ProjectModel

/// The objects with nothing to draw, and what is said of them before exporting (#658).
@Suite("Objects without data (#658)")
struct ObjectsWithoutDataTests {
    private func channels(_ names: [String]) -> [ChannelSummary] {
        names.map { ChannelSummary(identifier: $0, name: $0, unit: "") }
    }

    /// Classic Dash on one data input: speedometer, tachometer, map, G plot, two timers, gear.
    private func project(input: InputID) -> Project {
        var project = Project()
        project.displayObjects = ProjectTemplate.classicDash.displayObjects.map { object in
            var bound = object
            bound.inputID = input
            return bound
        }
        return project
    }

    @Test func aFileWithNoEngineChannelsLeavesTheGaugesThatNeedThem() {
        let input = InputID()
        let project = project(input: input)
        // GPS only: speed and position, as a camera's or a phone's file has.
        let dead = project.objectsWithoutData([input: channels(["speed", "latitude", "longitude", "distance"])])
        #expect(Set(dead.map(\.label)) == ["RPM", "Gear", "G"])
        // The timers and the map read laps and position, not a channel by name.
        #expect(!dead.contains { $0.label == "Lap" || $0.label == "Map" || $0.label == "Speed" })
    }

    @Test func aFileThatHasThemLeavesNone() {
        let input = InputID()
        let all = channels(["speed", "rpm", "gear", "lateralG", "longitudinalG", "latitude", "longitude"])
        #expect(project(input: input).objectsWithoutData([input: all]).isEmpty)
    }

    @Test func nothingIsJudgedBeforeItsFileIsRead() {
        let input = InputID()
        let project = project(input: input)
        #expect(project.objectsWithoutData([:]).isEmpty, "the file is not read yet")
        #expect(project.objectsWithoutData([input: []]).isEmpty, "nor one that offered no channel at all")
    }

    @Test func aHiddenObjectIsNotInTheVideoSoItIsNotCounted() {
        let input = InputID()
        var project = project(input: input)
        for index in project.displayObjects.indices where project.displayObjects[index].label == "RPM" {
            project.displayObjects[index].isVisible = false
        }
        let dead = project.objectsWithoutData([input: channels(["speed"])])
        #expect(!dead.contains { $0.label == "RPM" })
        #expect(dead.contains { $0.label == "Gear" })
    }

    @Test func aGPlotWithOneAxisStillDraws() {
        let input = InputID()
        let dead = project(input: input).objectsWithoutData([input: channels(["speed", "lateralG"])])
        #expect(!dead.contains { $0.label == "G" })
    }

    @Test func theWordsCountAndNameThem() {
        #expect(ObjectsWithoutDataWording.title(1) == "Give 1 gauge its data")
        #expect(ObjectsWithoutDataWording.title(3) == "Give 3 gauges their data")
        #expect(
            ObjectsWithoutDataWording.detail(["RPM"])
                == "RPM has no channel in the data file and draws nothing. Map its columns to it, or remove it "
                + "before you export.")
        let three = ObjectsWithoutDataWording.detail(["RPM", "Gear", "G"])
        #expect(three.contains(" have no channel in the data file and draw nothing. "))
        #expect(three.hasSuffix("Map its columns to them, or remove them before you export."))
        #expect(three.contains("RPM") && three.contains("Gear") && three.contains("G"))
        #expect(ObjectsWithoutDataWording.detail(["A", "B", "C", "D", "E"]).contains("2 more"))
        #expect(ObjectsWithoutDataWording.removeTitle(1) == "Remove It")
        #expect(ObjectsWithoutDataWording.removeTitle(2) == "Remove Them")
    }
}
