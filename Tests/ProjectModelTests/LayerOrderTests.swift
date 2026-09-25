import Foundation
import Testing

@testable import ProjectModel

/// Putting display objects in the order they are drawn (#277).
@Suite struct LayerOrderTests {
    func object(_ label: String) -> DisplayObject {
        DisplayObject(label: label, inputID: nil, frame: .full, kind: .text(TextParams()))
    }

    /// Back to front: A B C D.
    var project: Project { Project(displayObjects: ["A", "B", "C", "D"].map(object)) }

    func order(_ project: Project) -> String { project.displayObjects.map(\.label).joined() }
    func id(_ label: String, in project: Project) -> DisplayObjectID {
        guard let object = project.displayObjects.first(where: { $0.label == label }) else {
            Issue.record("No object \(label)")
            return DisplayObjectID()
        }
        return object.id
    }

    @Test func forwardAndBackwardMoveOnePlace() {
        var p = project
        p.arrange([id("B", in: p)], .forward)
        #expect(order(p) == "ACBD")
        p.arrange([id("B", in: p)], .backward)
        p.arrange([id("B", in: p)], .backward)
        #expect(order(p) == "BACD")
    }

    @Test func frontAndBackGoAllTheWayKeepingTheirOrder() {
        var p = project
        p.arrange([id("A", in: p), id("C", in: p)], .toFront)
        #expect(order(p) == "BDAC")
        p.arrange([id("D", in: p), id("C", in: p)], .toBack)
        #expect(order(p) == "DCBA")
    }

    @Test func aRunOfObjectsClimbsTogether() {
        var p = project
        p.arrange([id("A", in: p), id("B", in: p)], .forward)
        #expect(order(p) == "CABD")
    }

    @Test func nothingMovesPastTheEnds() {
        let p = project
        #expect(!p.canArrange([id("D", in: p)], .forward))
        #expect(!p.canArrange([id("D", in: p)], .toFront))
        #expect(p.canArrange([id("D", in: p)], .backward))
        #expect(!p.canArrange([id("A", in: p)], .toBack))
        #expect(!p.canArrange([], .forward))
    }

    @Test func aGroupMovesAsOne() {
        var p = project
        p.group([id("A", in: p), id("C", in: p)])
        p.arrange([id("A", in: p)], .toFront)
        #expect(order(p) == "BDAC")
    }

    @Test func aDragInTheFrontFirstListReordersTheStack() {
        // The sidebar lists D C B A; dragging A (row 3) to the top puts it in front.
        var p = project
        p.moveObjects(fromListOffsets: [3], toListOffset: 0)
        #expect(order(p) == "BCDA")
        // Dragging D (now row 1) to the bottom, below A's old place, sends it to the back.
        p.moveObjects(fromListOffsets: [1], toListOffset: 4)
        #expect(order(p) == "DBCA")
    }
}
