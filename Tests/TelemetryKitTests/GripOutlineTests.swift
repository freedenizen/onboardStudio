import Foundation
import Testing

@testable import TelemetryKit

/// #631: the car's grip as a shape the friction circle can draw.
@Suite("The grip envelope's outline (#631)")
struct GripOutlineTests {
    @Test func aCirclesOutlineIsACircle() {
        let outline = GripEnvelope(circle: 1.2).outline(points: 64)
        #expect(outline.count == 64)
        for point in outline { #expect(abs(hypot(point.lateral, point.longitudinal) - 1.2) < 1e-9) }
    }

    @Test func itStartsAtStraightBrakingAndGoesRoundThroughCorneringRight() throws {
        var reach = Array(repeating: 1.0, count: GripEnvelope.directions)
        reach[0] = 1.3  // braking
        reach[4] = 1.1  // cornering right
        reach[8] = 0.5  // accelerating
        let outline = GripEnvelope(reach: reach).outline(points: 16)
        #expect(abs(outline[0].lateral) < 1e-9 && abs(outline[0].longitudinal + 1.3) < 1e-9)
        #expect(abs(outline[4].lateral - 1.1) < 1e-9 && abs(outline[4].longitudinal) < 1e-9)
        #expect(abs(outline[8].lateral) < 1e-9 && abs(outline[8].longitudinal - 0.5) < 1e-9)
    }

    @Test func everyPointOfTheOutlineIsAtTheLimit() {
        var reach = (0..<GripEnvelope.directions).map { 0.8 + Double($0 % 5) * 0.1 }
        reach[3] = 1.4
        let envelope = GripEnvelope(reach: reach)
        for point in envelope.outline(points: 90) {
            #expect(abs(envelope.used(lateral: point.lateral, longitudinal: point.longitudinal) - 1) < 1e-9)
        }
    }

    @Test func tooFewPointsStillGoRoundEverySector() {
        #expect(GripEnvelope(circle: 1).outline(points: 3).count == GripEnvelope.directions)
    }
}
