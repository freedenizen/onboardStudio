import Testing

@testable import ProjectModel

/// A click on the preview picks what the user meant, not the video under everything (#278).
@Suite struct PreviewPickingTests {
    let video = DisplayObject(label: "Video", inputID: nil, frame: .full, kind: .video(VideoObjectParams()))
    let gauge = DisplayObject(
        label: "Gauge", inputID: nil, frame: UnitRect(x: 0.7, y: 0.6, width: 0.2, height: 0.3),
        kind: .speedometer(.speedometer()))

    @Test func aVideoIsPickedOnlyOnceSelectedOrWhileFraming() {
        #expect(!ObjectGeometry.isPickable(video, selected: false))
        #expect(ObjectGeometry.isPickable(video, selected: true))
        #expect(ObjectGeometry.isPickable(video, selected: false, editingFraming: true))
    }

    @Test func otherObjectsArePickedAsBefore() {
        #expect(ObjectGeometry.isPickable(gauge, selected: false))
        var hidden = gauge
        hidden.isVisible = false
        #expect(!ObjectGeometry.isPickable(hidden, selected: true))
    }

    @Test func aLockStillWinsOverSelection() {
        var locked = video
        locked.isLocked = true
        #expect(!ObjectGeometry.isPickable(locked, selected: true, editingFraming: true))
        var lockedGauge = gauge
        lockedGauge.isLocked = true
        #expect(!ObjectGeometry.isPickable(lockedGauge, selected: false))
    }
}
