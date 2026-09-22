import TelemetryKit
import Testing

@testable import Importers

/// #71: a gate is two points, and everything the lap detector needs comes out of them.
@Suite("Lap gates")
struct LapGeometryTests {
    /// Sonoma's start/finish as a real VBVDHD2 log records it, ~10 m across.
    let start = LapGate(
        kind: .start, label: "Start / Finish",
        startLatitude: 39.538_480, startLongitude: -122.331_177,
        endLatitude: 39.538_571, endLongitude: -122.331_184)

    @Test func theCentreIsBetweenTheEnds() {
        #expect(abs(start.centreLatitude - 39.538_525) < 1e-6)
        #expect(abs(start.centreLongitude - -122.331_180) < 1e-6)
    }

    /// Half the gate's own length, which beats the 25 m the detector otherwise assumes: a logger
    /// draws the line as wide as the track is.
    @Test func theHalfWidthIsHalfTheGate() {
        #expect(start.halfWidthMeters > 4 && start.halfWidthMeters < 6, "\(start.halfWidthMeters)")
    }

    /// A degenerate gate must not give the detector a zero-width line it can never cross.
    @Test func aGateWithNoLengthStillHasAWidth() {
        let point = LapGate(
            kind: .start, startLatitude: 39.5, startLongitude: -122.3,
            endLatitude: 39.5, endLongitude: -122.3)
        #expect(point.halfWidthMeters >= 1)
    }

    @Test func kindsAreToldApart() {
        let geometry = LapGeometry(gates: [
            start,
            LapGate(kind: .split, startLatitude: 1, startLongitude: 2, endLatitude: 3, endLongitude: 4),
            LapGate(kind: .finish, startLatitude: 5, startLongitude: 6, endLatitude: 7, endLongitude: 8),
        ])
        #expect(geometry.start?.label == "Start / Finish")
        #expect(geometry.splits.count == 1, "neither the start nor the finish is a sector boundary")
        #expect(!geometry.isEmpty)
        #expect(LapGeometry().isEmpty)
    }

    /// The gates survive into the session, which is where the app reads them.
    @Test func theSessionKeepsWhatTheFileCarried() throws {
        let session = try VBOImporter().importSession(at: try Fixtures.url("vbox-canbus.vbo"))
        #expect(session.lapGeometry.start?.label == "Start / Finish")
        #expect(session.lapGeometry.splits.count == 2)
    }
}
