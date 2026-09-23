import Foundation
import Testing

@testable import ProjectModel

@Suite("Turning a bar (#113)")
struct BarOrientationTests {
    let settings = ProjectSettings(outputWidth: 1920, outputHeight: 1080)

    func bar(_ frame: UnitRect) -> DisplayObject {
        DisplayObject(label: "Bar", inputID: nil, frame: frame, kind: .bar(BarParams(channel: "throttle")))
    }

    func pixels(_ rect: UnitRect) -> (width: Double, height: Double) {
        (rect.width * 1920, rect.height * 1080)
    }

    @Test func aNewBarTurnedVerticalGetsATallFrameAboutTheSameCentre() throws {
        var object = bar(UnitRect(x: 0.3, y: 0.5, width: 0.4, height: 0.05))
        let before = pixels(object.frame)
        object.setBarOrientation(.vertical, in: settings)
        guard case .bar(let params) = object.kind else { throw CancellationError() }
        #expect(params.orientation == .vertical)
        let after = pixels(object.frame)
        #expect(abs(after.width - before.height) < 0.001)
        #expect(abs(after.height - before.width) < 0.001)
        #expect(abs(object.frame.x + object.frame.width / 2 - 0.5) < 0.001)
        #expect(abs(object.frame.y + object.frame.height / 2 - 0.525) < 0.001)
        // And back: the original frame again.
        object.setBarOrientation(.horizontal, in: settings)
        #expect(abs(object.frame.width - 0.4) < 0.001 && abs(object.frame.height - 0.05) < 0.001)
    }

    @Test func aFrameAlreadyTheRightWayRoundIsLeftAlone() {
        // Tall on the picture already: someone sized it for a vertical bar.
        let tall = UnitRect(x: 0.1, y: 0.1, width: 0.05, height: 0.4)
        var object = bar(tall)
        object.setBarOrientation(.vertical, in: settings)
        #expect(object.frame == tall)
        // Choosing the orientation it already has changes nothing.
        object.setBarOrientation(.vertical, in: settings)
        #expect(object.frame == tall)
    }

    @Test func squareInUnitsIsWideOnA16By9Picture() {
        #expect(!ObjectGeometry.isPortrait(UnitRect(x: 0, y: 0, width: 0.2, height: 0.2), in: settings))
        #expect(ObjectGeometry.isPortrait(UnitRect(x: 0, y: 0, width: 0.1, height: 0.2), in: settings))
    }

    @Test func onlyABarTurns() {
        let frame = UnitRect(x: 0.3, y: 0.5, width: 0.4, height: 0.05)
        var text = DisplayObject(label: "T", inputID: nil, frame: frame, kind: .text(TextParams()))
        text.setBarOrientation(.vertical, in: settings)
        #expect(text.frame == frame)
    }
}
