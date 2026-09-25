import Testing

@testable import ProjectModel

/// Framing the picture on the preview (#275).
@Suite struct FramingEditingTests {
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func theWholeShotIsTheRegionOfNoFraming() {
        #expect(FramingEditing.region(of: .none) == UnitRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func aZoomOfTwoShowsTheMiddleHalf() {
        let region = FramingEditing.region(of: CameraFraming(zoom: 2))
        #expect(close(region.x, 0.25) && close(region.width, 0.5))
        #expect(close(region.y, 0.25) && close(region.height, 0.5))
    }

    @Test func movingFollowsThePointerAndStopsAtTheEdge() {
        let framing = CameraFraming(zoom: 2)
        let moved = FramingEditing.moved(framing, dx: 0.1, dy: -0.05)
        #expect(close(moved.centerX, 0.6) && close(moved.centerY, 0.45))
        #expect(close(FramingEditing.region(of: moved).x, 0.35))
        let far = FramingEditing.moved(framing, dx: 5, dy: -5)
        #expect(close(far.centerX, 0.75) && close(far.centerY, 0.25))
        // Back from the edge at once: no dead stretch of drag.
        let back = FramingEditing.moved(far, dx: -0.1, dy: 0)
        #expect(close(back.centerX, 0.65))
    }

    @Test func aWholeShotCannotMove() {
        let moved = FramingEditing.moved(.none, dx: 0.3, dy: 0.3)
        #expect(close(moved.centerX, 0.5) && close(moved.centerY, 0.5))
    }

    @Test func movingAcrossATrimmedPictureScalesToTheTrim() {
        let framing = CameraFraming(zoom: 2, crop: CropInsets(left: 0.25, right: 0.25))
        let moved = FramingEditing.moved(framing, dx: 0.05, dy: 0)
        #expect(close(moved.centerX, 0.6))
    }

    @Test func zoomingStaysInRangeAndInside() {
        #expect(FramingEditing.zoomed(.none, by: 0.5).zoom == 1)
        #expect(FramingEditing.zoomed(CameraFraming(zoom: 3), by: 2).zoom == 4)
        // Zoomed out from a window at the edge, the wider window is pulled back inside.
        let atEdge = CameraFraming(zoom: 4, centerX: 0.875)
        let wider = FramingEditing.zoomed(atEdge, by: 0.5)
        #expect(wider.zoom == 2 && close(wider.centerX, 0.75))
    }

    @Test func resizingAWindowToAWidthZoomsToMatch() {
        let resized = FramingEditing.resized(.none, toWidth: 0.5)
        #expect(close(resized.zoom, 2))
        #expect(close(FramingEditing.region(of: resized).width, 0.5))
        #expect(FramingEditing.resized(.none, toWidth: 2).zoom == 1)
        #expect(FramingEditing.resized(.none, toWidth: 0).zoom == 4)
    }
}
