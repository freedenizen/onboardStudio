import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// Placing a start/finish line by pointing at the drawn map.
///
/// `SectorMapSession` is the ruler throughout: a square 100 m on a side at a known corner, so a
/// drawn length can be checked against a side of the square rather than against the projection's
/// own arithmetic, which would only prove it agrees with itself.
@Suite struct TrackMapEditingTests {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
    let origin = SectorMapSession.origin
    var cosLat: Double { cos(origin.latitude * .pi / 180) }

    /// Metres north of the south-west corner, as a latitude.
    func latitude(north metres: Double) -> Double { origin.latitude + metres / 110_540 }
    /// Metres east of the south-west corner, as a longitude.
    func longitude(east metres: Double) -> Double { origin.longitude + metres / (111_320 * cosLat) }

    func projection(rotation: Double = 0) throws -> TrackProjection {
        try #require(TrackProjection(session: SectorMapSession.session, rotationDegrees: rotation))
    }

    @Test("A point unprojects to the coordinate it was drawn from")
    func roundTripsThroughTheProjection() throws {
        for rotation in [0.0, 37.0, -125.0, 180.0] {
            let projection = try projection(rotation: rotation)
            for north in stride(from: 0.0, through: 100.0, by: 25.0) {
                for east in stride(from: 0.0, through: 100.0, by: 25.0) {
                    let latitude = latitude(north: north)
                    let longitude = longitude(east: east)
                    let drawn = projection.point(latitude: latitude, longitude: longitude, in: bounds)
                    let back = projection.coordinate(at: drawn, in: bounds)
                    // A millionth of a degree is about 10 cm — finer than any GPS this reads.
                    #expect(abs(back.latitude - latitude) < 1e-6)
                    #expect(abs(back.longitude - longitude) < 1e-6)
                }
            }
        }
    }

    @Test("The line is drawn across the direction of travel")
    func drawsSquareToTravel() throws {
        let projection = try projection()
        // Halfway up the west side, where the square is driven due north.
        let spec = LapLineSpec(
            latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0, halfWidthMeters: 20)
        let line = TrackMapEditing.line(spec, projection: projection, in: bounds)
        // North is up and the map is unrotated, so a line across a northward track runs flat, with
        // the right-hand end — 90° clockwise of travel — to the east, which is to the right.
        #expect(abs(line.right.y - line.centre.y) < 0.5)
        #expect(abs(line.left.y - line.centre.y) < 0.5)
        #expect(line.right.x > line.centre.x)
        #expect(line.left.x < line.centre.x)
    }

    @Test("The drawn line is as wide as the half-width says")
    func honoursHalfWidthInMetres() throws {
        let projection = try projection()
        // The south side of the square is 100 m of longitude, which is the axis the line runs on.
        let southWest = projection.point(latitude: origin.latitude, longitude: origin.longitude, in: bounds)
        let southEast = projection.point(
            latitude: origin.latitude, longitude: longitude(east: 100), in: bounds)
        let pixelsPerHundredMetres = hypot(southEast.x - southWest.x, southEast.y - southWest.y)
        let spec = LapLineSpec(
            latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0, halfWidthMeters: 20)
        let line = TrackMapEditing.line(spec, projection: projection, in: bounds)
        let drawn = hypot(line.right.x - line.left.x, line.right.y - line.left.y)
        #expect(abs(drawn - pixelsPerHundredMetres * 0.4) < 0.5)
    }

    @Test("A line with no heading is drawn square to the trace under it")
    func takesItsHeadingFromTheTraceWhenUnset() throws {
        let projection = try projection()
        let spec = LapLineSpec(latitude: latitude(north: 50), longitude: origin.longitude)
        // Halfway up the west side the square runs due north, and that is what a crossing there
        // would be measured against, so it is what must be drawn.
        #expect(abs(TrackMapEditing.line(spec, projection: projection, in: bounds).headingDegrees) < 5)
        let onTheNorthSide = LapLineSpec(latitude: latitude(north: 100), longitude: longitude(east: 50))
        let heading = TrackMapEditing.line(onTheNorthSide, projection: projection, in: bounds).headingDegrees
        #expect(abs(heading - 90) < 5)
    }

    @Test("Dragging the body puts the line where the pointer is")
    func draggingTheBodyMovesIt() throws {
        for rotation in [0.0, 40.0] {
            let projection = try projection(rotation: rotation)
            let spec = LapLineSpec(
                latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0)
            let target = (latitude: latitude(north: 100), longitude: longitude(east: 50))
            let pointer = projection.point(latitude: target.latitude, longitude: target.longitude, in: bounds)
            let moved = TrackMapEditing.dragged(
                spec, handle: .body, to: pointer, projection: projection, in: bounds)
            #expect(abs(moved.latitude - target.latitude) < 1e-6)
            #expect(abs(moved.longitude - target.longitude) < 1e-6)
            // Moving it says nothing about which way it is crossed.
            #expect(moved.headingDegrees == 0)
        }
    }

    @Test("Dragging an end swings the line about its centre")
    func draggingAnEndRotatesIt() throws {
        let projection = try projection()
        let centre = (latitude: latitude(north: 50), longitude: origin.longitude)
        let spec = LapLineSpec(latitude: centre.latitude, longitude: centre.longitude, headingDegrees: 0)
        // Drag the right-hand end due north of the centre. The right-hand end sits 90° clockwise
        // of travel, so travel is now due west.
        let pointer = projection.point(
            latitude: latitude(north: 80), longitude: origin.longitude, in: bounds)
        let turned = TrackMapEditing.dragged(
            spec, handle: .rightEnd, to: pointer, projection: projection, in: bounds)
        #expect(abs((turned.headingDegrees ?? 0) - 270) < 1)
        // The centre does not move: rotating and moving are different gestures.
        #expect(turned.latitude == spec.latitude)
        #expect(turned.longitude == spec.longitude)
        // The other end is the same line crossed the other way.
        let other = TrackMapEditing.dragged(
            spec, handle: .leftEnd, to: pointer, projection: projection, in: bounds)
        #expect(abs((other.headingDegrees ?? 0) - 90) < 1)
    }

    @Test("A rotated map does not change where a drag lands on the Earth")
    func rotationDoesNotMoveTheGeography() throws {
        let plain = try projection()
        let tilted = try projection(rotation: 65)
        let spec = LapLineSpec(
            latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0)
        let target = (latitude: latitude(north: 25), longitude: longitude(east: 75))
        let fromPlain = TrackMapEditing.dragged(
            spec, handle: .body,
            to: plain.point(latitude: target.latitude, longitude: target.longitude, in: bounds),
            projection: plain, in: bounds)
        let fromTilted = TrackMapEditing.dragged(
            spec, handle: .body,
            to: tilted.point(latitude: target.latitude, longitude: target.longitude, in: bounds),
            projection: tilted, in: bounds)
        #expect(abs(fromPlain.latitude - fromTilted.latitude) < 1e-6)
        #expect(abs(fromPlain.longitude - fromTilted.longitude) < 1e-6)
        // And a heading is a compass heading, not a screen angle: the same drag on a map turned
        // 65° must still say the car is going the same way.
        let pointer = { (p: TrackProjection) in
            p.point(latitude: latitude(north: 80), longitude: origin.longitude, in: bounds)
        }
        let plainHeading = TrackMapEditing.dragged(
            spec, handle: .rightEnd, to: pointer(plain), projection: plain, in: bounds
        ).headingDegrees
        let tiltedHeading = TrackMapEditing.dragged(
            spec, handle: .rightEnd, to: pointer(tilted), projection: tilted, in: bounds
        ).headingDegrees
        #expect(abs((plainHeading ?? 0) - (tiltedHeading ?? 0)) < 1)
    }

    @Test("A click finds the part of the line it landed on")
    func hitTestsTheHandles() throws {
        let projection = try projection()
        let spec = LapLineSpec(
            latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0, halfWidthMeters: 25)
        let line = TrackMapEditing.line(spec, projection: projection, in: bounds)
        #expect(TrackMapEditing.handle(at: line.centre, of: line, tolerance: 6) == .body)
        #expect(TrackMapEditing.handle(at: line.right, of: line, tolerance: 6) == .rightEnd)
        #expect(TrackMapEditing.handle(at: line.left, of: line, tolerance: 6) == .leftEnd)
        let away = CGPoint(x: line.centre.x, y: line.centre.y + 40)
        #expect(TrackMapEditing.handle(at: away, of: line, tolerance: 6) == nil)
    }

    @Test("Handles stay far enough apart to be grabbed, however narrow the line is")
    func keepsTheHandlesReachable() throws {
        let projection = try projection()
        // Two metres across a 400 m lap is a couple of points on a 300-point map: both ends land
        // inside one click of the centre and of each other, which is the state the reach fixes.
        let narrow = LapLineSpec(
            latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0, halfWidthMeters: 2)
        let cramped = TrackMapEditing.line(narrow, projection: projection, in: bounds)
        #expect(hypot(cramped.right.x - cramped.left.x, cramped.right.y - cramped.left.y) < 12)
        let line = TrackMapEditing.line(narrow, projection: projection, in: bounds, minimumHandleDistance: 18)
        #expect(abs(hypot(line.rightHandle.x - line.centre.x, line.rightHandle.y - line.centre.y) - 18) < 0.01)
        #expect(abs(hypot(line.leftHandle.x - line.centre.x, line.leftHandle.y - line.centre.y) - 18) < 0.01)
        // Pushed out along the line, not somewhere new: the handle still says which way it turns.
        #expect(line.rightHandle.x > line.centre.x)
        #expect(line.leftHandle.x < line.centre.x)
        #expect(abs(line.rightHandle.y - line.centre.y) < 0.5)
        // The line itself keeps its true width; only the reach moved.
        #expect(line.right == cramped.right)
        #expect(line.left == cramped.left)
        #expect(TrackMapEditing.handle(at: line.rightHandle, of: line, tolerance: 7) == .rightEnd)
        #expect(TrackMapEditing.handle(at: line.leftHandle, of: line, tolerance: 7) == .leftEnd)
    }

    @Test("A wide line keeps its own ends as its handles")
    func leavesAWideLineAlone() throws {
        let projection = try projection()
        // 40 m across a 100 m side is a good fraction of the map: no reach needed.
        let wide = LapLineSpec(
            latitude: latitude(north: 50), longitude: origin.longitude, headingDegrees: 0, halfWidthMeters: 40)
        let line = TrackMapEditing.line(wide, projection: projection, in: bounds, minimumHandleDistance: 18)
        #expect(line.rightHandle == line.right)
        #expect(line.leftHandle == line.left)
    }

    @Test("A heading is reported as a compass bearing, never a negative one")
    func normalizesHeadings() {
        #expect(TrackMapEditing.normalized(-90) == 270)
        #expect(TrackMapEditing.normalized(450) == 90)
        #expect(TrackMapEditing.normalized(0) == 0)
        #expect(TrackMapEditing.normalized(-370) == 350)
    }
}
