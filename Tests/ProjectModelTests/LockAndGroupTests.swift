import Foundation
import Testing

@testable import ProjectModel

@Suite("Locking and grouping objects (#90)")
struct LockAndGroupTests {
    let speedo = DisplayObject(
        label: "Speedo", inputID: nil, frame: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        kind: .text(TextParams()))
    let label = DisplayObject(
        label: "Label", inputID: nil, frame: UnitRect(x: 0.1, y: 0.3, width: 0.2, height: 0.05),
        kind: .text(TextParams()))
    let other = DisplayObject(
        label: "Other", inputID: nil, frame: UnitRect(x: 0.6, y: 0.6, width: 0.1, height: 0.1),
        kind: .text(TextParams()))

    var project: Project { Project(displayObjects: [speedo, label, other]) }

    @Test func anObjectSavedBeforeLocksIsUnlockedAndOnItsOwn() throws {
        let json = try JSONEncoder().encode(speedo)
        var dictionary = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        dictionary.removeValue(forKey: "isLocked")
        dictionary.removeValue(forKey: "groupID")
        let old = try JSONDecoder().decode(
            DisplayObject.self, from: JSONSerialization.data(withJSONObject: dictionary))
        #expect(!old.isLocked && old.groupID == nil)
        var locked = speedo
        locked.isLocked = true
        locked.groupID = ObjectGroupID()
        #expect(try JSONDecoder().decode(DisplayObject.self, from: JSONEncoder().encode(locked)) == locked)
    }

    @Test func aClickOnOneMemberSelectsTheGroup() throws {
        var project = project
        let grouped = project.group([speedo.id, label.id])
        let group = try #require(grouped)
        #expect(project.displayObjects.filter { $0.groupID == group }.count == 2)
        #expect(project.expandingGroups([label.id]) == [speedo.id, label.id])
        #expect(project.expandingGroups([other.id]) == [other.id])
        // One object is not a group.
        #expect(project.group([other.id]) == nil)
        // Grouping a member with another object takes the whole group along.
        let merged = project.group([label.id, other.id])
        let bigger = try #require(merged)
        #expect(project.displayObjects.allSatisfy { $0.groupID == bigger })
        project.ungroup([other.id])
        #expect(project.displayObjects.allSatisfy { $0.groupID == nil })
    }

    @Test func aGroupIsLockedAsAWhole() {
        var project = project
        project.group([speedo.id, label.id])
        project.setLocked(true, [speedo.id])
        #expect(project.displayObjects.map(\.isLocked) == [true, true, false])
        project.setLocked(false, [label.id])
        #expect(project.displayObjects.allSatisfy { !$0.isLocked })
    }

    @Test func membersFollowTheGroupsBox() throws {
        let box = try #require(ObjectGeometry.bounds([speedo.frame, label.frame]))
        #expect(box.x == 0.1 && box.y == 0.1 && abs(box.width - 0.2) < 1e-9 && abs(box.height - 0.25) < 1e-9)
        // Moved: everything shifts by the same amount.
        var moved = box
        moved.x += 0.1
        #expect(abs(ObjectGeometry.mapped(label.frame, from: box, to: moved).x - 0.2) < 1e-9)
        // Doubled from its top-left: the label doubles and moves down with it.
        let doubled = UnitRect(x: box.x, y: box.y, width: box.width * 2, height: box.height * 2)
        let grown = ObjectGeometry.mapped(label.frame, from: box, to: doubled)
        #expect(abs(grown.y - 0.5) < 1e-9 && abs(grown.width - 0.4) < 1e-9 && abs(grown.height - 0.1) < 1e-9)
        #expect(ObjectGeometry.bounds([]) == nil)
    }
}
