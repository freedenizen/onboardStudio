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

    @Test func aPictureAspectAllowsForCropAndRotation() {
        #expect(FramingEditing.pictureAspect(width: 1920, height: 1080) == 1920.0 / 1080)
        #expect(FramingEditing.pictureAspect(width: 1920, height: 1080, rotation: 90) == 1080.0 / 1920)
        let cropped = FramingEditing.pictureAspect(width: 1000, height: 1000, crop: CropInsets(left: 0.25, right: 0.25))
        #expect(cropped == 0.5)
        #expect(FramingEditing.pictureAspect(width: 0, height: 1080) == nil)
    }

    @Test func aNarrowerPictureIsPillarboxedInItsBox() {
        // A 4:3 camera in a full 16:9 frame: bars either side.
        let box = UnitRect(x: 0, y: 0, width: 1, height: 1)
        let placed = FramingEditing.fitted(aspect: 4.0 / 3, in: box, boxAspect: 16.0 / 9)
        #expect(close(placed.width, 0.75) && close(placed.x, 0.125) && placed.height == 1)
        let wide = FramingEditing.fitted(aspect: 21.0 / 9, in: box, boxAspect: 16.0 / 9)
        #expect(close(wide.height, 16.0 / 21) && wide.width == 1)
    }

    @Test func aCornerReachingDownIsMeasuredAgainstTheVerticalTrim() {
        // Top and bottom trimmed a quarter each, the sides not: the picture shown is half as tall.
        let trimmed = CameraFraming(crop: CropInsets(top: 0.25, bottom: 0.25))
        // A window a quarter of the shown picture tall is half of what is left: zoom 2, not 4.
        let resized = FramingEditing.resized(trimmed, toWidth: 0, height: 0.25)
        #expect(close(resized.zoom, 2))
        // Across and down both given, the larger window wins.
        let both = FramingEditing.resized(.none, toWidth: 0.5, height: 0.8)
        #expect(close(both.zoom, 1.25))
    }
}
