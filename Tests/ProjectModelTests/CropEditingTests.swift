import Foundation
import Testing

@testable import ProjectModel

/// Cropping a video on the preview (#276).
@Suite struct CropEditingTests {
    let crop = CropInsets(top: 0.1, left: 0.2, bottom: 0.05, right: 0)

    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func turnedAndFlippedCropsComeBackAsTheyWere() {
        for rotation in [0.0, 90, 180, 270] {
            for mirror in [
                Mirror(), Mirror(horizontal: true), Mirror(vertical: true), Mirror(horizontal: true, vertical: true),
            ] {
                let shown = CropEditing.displayed(crop, rotation: rotation, mirror: mirror)
                #expect(CropEditing.source(shown, rotation: rotation, mirror: mirror) == crop)
            }
        }
    }

    @Test func aQuarterTurnPutsTheLeftOnTop() {
        let shown = CropEditing.displayed(crop, rotation: 90, mirror: Mirror())
        #expect(shown.top == 0.2 && shown.right == 0.1 && shown.bottom == 0 && shown.left == 0.05)
        #expect(CropEditing.displayed(crop, rotation: 0, mirror: Mirror(horizontal: true)).right == 0.2)
    }

    @Test func edgesAndCornersAreFoundAlongTheirLength() {
        let rect = UnitRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let t = CGSize(width: 0.02, height: 0.02)
        #expect(CropEditing.handle(at: CGPoint(x: 0.2, y: 0.7), in: rect, tolerance: t) == .left)
        #expect(CropEditing.handle(at: CGPoint(x: 0.79, y: 0.21), in: rect, tolerance: t) == .topRight)
        #expect(CropEditing.handle(at: CGPoint(x: 0.5, y: 0.5), in: rect, tolerance: t) == .body)
        #expect(CropEditing.handle(at: CGPoint(x: 0.1, y: 0.5), in: rect, tolerance: t) == nil)
    }

    @Test func anEdgeStopsAtItsLimits() {
        let pulled = CropEditing.dragged(.none, handle: .left, dx: 0.9, dy: 0)
        #expect(pulled.left == CropEditing.maximumInset)
        let pushed = CropEditing.dragged(CropInsets(right: 0.45), handle: .left, dx: 0.5, dy: 0)
        #expect(close(pushed.left, 1 - 0.45 - CropEditing.minimumSize))
        #expect(CropEditing.dragged(.none, handle: .top, dx: 0, dy: -0.1).top == 0)
    }

    @Test func theWindowMovesWholeAndStaysInside() {
        let window = CropInsets(top: 0.2, left: 0.2, bottom: 0.2, right: 0.2)
        let moved = CropEditing.dragged(window, handle: .body, dx: 0.1, dy: -0.5)
        #expect(close(moved.left, 0.3) && close(moved.right, 0.1))
        #expect(close(moved.top, 0) && close(moved.bottom, 0.4))
    }

    @Test func aCornerHeldToAShapeKeepsIt() {
        // A 16:9 picture held square: the crop's pixels are as wide as they are tall.
        let dragged = CropEditing.dragged(
            .none, handle: .bottomRight, dx: -0.3, dy: 0, ratio: 1, pictureAspect: 16.0 / 9)
        let width = 1 - dragged.left - dragged.right
        let height = 1 - dragged.top - dragged.bottom
        #expect(close(width * 16 / 9, height))
    }

    @Test func aShapeIsFittedInTheMiddle() {
        let square = CropEditing.fitted(ratio: 1, pictureAspect: 16.0 / 9)
        #expect(close(square.left, square.right) && close(1 - square.left - square.right, 9.0 / 16))
        #expect(square.top == 0)
        let tall = CropEditing.fitted(ratio: 9.0 / 16, pictureAspect: 16.0 / 9)
        #expect(close(1 - tall.left - tall.right, 81.0 / 256) && tall.top == 0)
        #expect(CropEditing.fitted(ratio: 16.0 / 9, pictureAspect: 16.0 / 9) == .none)
    }
}
