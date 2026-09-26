import Foundation

/// A change to where objects sit in the stack (#277), as Keynote's Arrange menu has them.
public enum LayerMove: Sendable, CaseIterable {
    case forward, toFront, backward, toBack

    /// The command's name, which the menu and Undo both use.
    public var title: String {
        switch self {
        case .forward: "Bring Forward"
        case .toFront: "Bring to Front"
        case .backward: "Send Backward"
        case .toBack: "Send to Back"
        }
    }
}

/// The stack of display objects (#277). `displayObjects` is the draw order: the first is drawn
/// first, at the back; the sidebar lists them front first.
extension Project {
    /// Moves `ids`, with every other member of their groups, up or down the stack. Forward and
    /// backward move each of them past one object that is not moving; front and back take them
    /// to the end, keeping their order among themselves.
    public mutating func arrange(_ ids: Set<DisplayObjectID>, _ move: LayerMove) {
        displayObjects = arranged(ids, move)
    }

    /// Whether `arrange` would change anything: Bring Forward is off for what is already in front.
    public func canArrange(_ ids: Set<DisplayObjectID>, _ move: LayerMove) -> Bool {
        !ids.isEmpty && arranged(ids, move).map(\.id) != displayObjects.map(\.id)
    }

    func arranged(_ ids: Set<DisplayObjectID>, _ move: LayerMove) -> [DisplayObject] {
        let moving = expandingGroups(ids)
        var stack = displayObjects
        let isMoving = { (object: DisplayObject) in moving.contains(object.id) }
        switch move {
        case .toFront:
            return stack.filter { !isMoving($0) } + stack.filter(isMoving)
        case .toBack:
            return stack.filter(isMoving) + stack.filter { !isMoving($0) }
        case .forward:
            // From the front down, so a run of moving objects climbs together.
            for index in stride(from: stack.count - 2, through: 0, by: -1)
            where isMoving(stack[index]) && !isMoving(stack[index + 1]) {
                stack.swapAt(index, index + 1)
            }
        case .backward:
            for index in 1..<max(stack.count, 1) where isMoving(stack[index]) && !isMoving(stack[index - 1]) {
                stack.swapAt(index, index - 1)
            }
        }
        return stack
    }

    /// A drag in the sidebar's list, which is front first: the objects at `offsets` go to before
    /// `destination` (both counted in that list, as SwiftUI's `onMove` counts them).
    public mutating func moveObjects(fromListOffsets offsets: IndexSet, toListOffset destination: Int) {
        var list = Array(displayObjects.reversed())
        let moving = offsets.sorted().filter { $0 < list.count }.map { list[$0] }
        let before = offsets.filter { $0 < destination }.count
        for offset in offsets.sorted(by: >) where offset < list.count { list.remove(at: offset) }
        list.insert(contentsOf: moving, at: min(max(destination - before, 0), list.count))
        displayObjects = list.reversed()
    }
}
