import Foundation
import Testing

@testable import TelemetryKit

/// Turn names pinned to where the turns are (#548). Coordinates are invented: a straight run of
/// corners a known number of metres apart, north of an arbitrary origin.
@Suite("Corner naming")
struct CornerNamingTests {
    static let origin = (latitude: 47.0, longitude: 11.0)
    /// Degrees of latitude per metre, near enough for tests that work in tens of metres.
    static let degreesPerMetre = 1 / 111_195.0

    /// A corner whose apex is `north` metres north of the origin, `along` metres into the lap.
    static func corner(north: Double, along: Double? = nil) -> Corner {
        Corner(
            startDistance: (along ?? north) - 20, endDistance: (along ?? north) + 20, apexDistance: along ?? north,
            headingChangeDegrees: 90, lapLengthMeters: 2_000,
            apexLatitude: origin.latitude + north * degreesPerMetre, apexLongitude: origin.longitude)
    }

    static func pin(_ label: String, north: Double) -> TurnName {
        TurnName(label: label, latitude: origin.latitude + north * degreesPerMetre, longitude: origin.longitude)
    }

    /// Five turns as a circuit numbers them, 3a included, 300 m apart.
    static let pinned = [
        pin("1", north: 0), pin("2", north: 300), pin("3", north: 600), pin("3a", north: 900), pin("4", north: 1_200),
    ]

    @Test func withNothingPinnedTheListNamesCornersInOrderAndCountsTheRest() {
        let corners = (0..<4).map { Self.corner(north: Double($0) * 300) }
        let names = CornerNaming.names(for: corners, pinned: [], legacy: ["1", "", "3a"])
        #expect(names.map(\.label) == ["1", "2", "3a", "4"])
        #expect(names.map(\.source) == [.named, .counted, .named, .counted])
    }

    @Test func pinnedNamesFindTheirTurns() {
        let corners = (0..<5).map { Self.corner(north: Double($0) * 300) }
        let names = CornerNaming.names(for: corners, pinned: Self.pinned)
        #expect(names.map(\.label) == ["1", "2", "3", "3a", "4"])
        #expect(names.allSatisfy { $0.source == .named })
    }

    @Test func aLapThatFindsAnExtraKinkKeepsEveryNameOnItsTurn() {
        // The case #548 was filed for: a kink 100 m after the line is a corner on this lap. By
        // position in a list every name after it would move one turn along.
        let corners =
            [Self.corner(north: 0), Self.corner(north: 100)] + (1..<5).map { Self.corner(north: Double($0) * 300) }
        let names = CornerNaming.names(for: corners, pinned: Self.pinned)
        #expect(names.map(\.label) == ["1", "1–2", "2", "3", "3a", "4"])
        #expect(names[1].source == .between)
    }

    @Test func aLapThatMissesATurnLeavesTheOthersNamed() {
        let corners = [0, 300, 900, 1_200].map { Self.corner(north: Double($0)) }
        #expect(CornerNaming.names(for: corners, pinned: Self.pinned).map(\.label) == ["1", "2", "3a", "4"])
    }

    @Test func theApexMayWanderAndStillTakeItsName() {
        // The line and the GPS move an apex from lap to lap; inside the radius it is the same turn.
        let wander = CornerNaming.matchRadiusMeters - 5
        let corners = (0..<5).map { Self.corner(north: Double($0) * 300 + wander) }
        #expect(CornerNaming.names(for: corners, pinned: Self.pinned).map(\.label) == ["1", "2", "3", "3a", "4"])
    }

    /// A named bend from `from` to `to` metres north, its apex at `apex`, a trace point every 10 m.
    static func bend(_ label: String, from: Double, to: Double, apex: Double) -> TurnName {
        let trace = stride(from: from, through: to, by: 10).map {
            GeoPoint(latitude: origin.latitude + $0 * degreesPerMetre, longitude: origin.longitude)
        }
        var pin = Self.pin(label, north: apex)
        pin.trace = trace
        return pin
    }

    @Test func theApexOfALongBendMayMoveFurtherThanTheRadiusAndKeepItsName() {
        // A long constant-radius bend: the apex lands anywhere along it from one lap to the next.
        let carousel = Self.bend("Carousel", from: 500, to: 700, apex: 520)
        let far = CornerNaming.matchRadiusMeters * 4
        #expect(CornerNaming.names(for: [Self.corner(north: 520 + far)], pinned: [carousel])[0].label == "Carousel")
        // Without the bend, the apex alone is too far away to be the same turn.
        var apexOnly = carousel
        apexOnly.trace = []
        #expect(CornerNaming.names(for: [Self.corner(north: 520 + far)], pinned: [apexOnly])[0].source == .counted)
    }

    @Test func ofTwoCornersOnOneNamedBendTheNearerApexTakesTheName() {
        // A kink at the entry of a long turn lies on the named bend as much as the turn does.
        let pinned = [Self.pin("1", north: 0), Self.bend("2", from: 200, to: 400, apex: 350)]
        let corners = [0, 210, 340].map { Self.corner(north: Double($0)) }
        #expect(CornerNaming.names(for: corners, pinned: pinned).map(\.label) == ["1", "1–2", "2"])
    }

    @Test func aDetectedCornerCarriesItsBendAndAPinKeepsIt() throws {
        let session = SyntheticTrack.session()
        let lap = try #require(session.laps.first)
        let corner = try #require(CornerDetector.corners(of: lap, in: session).first)
        #expect(corner.trace.count >= 2)
        let pin = try #require(TurnName(label: "1", corner: corner))
        #expect(pin.trace == corner.trace)
        let decoded = try JSONDecoder().decode(TurnName.self, from: try JSONEncoder().encode(pin))
        #expect(decoded == pin)
        // A name written with only its apex still reads.
        let apexOnly = try JSONDecoder().decode(
            TurnName.self, from: Data(#"{"label":"3a","latitude":47,"longitude":11}"#.utf8))
        #expect(apexOnly.trace.isEmpty)
    }

    @Test func aCornerTooFarFromEveryNameIsCalledByItsNeighbours() {
        let corners = [0, 300, 450, 600].map { Self.corner(north: Double($0)) }
        let names = CornerNaming.names(for: corners, pinned: Self.pinned)
        #expect(names.map(\.label) == ["1", "2", "2–3", "3"])
    }

    @Test func aCornerBeforeTheFirstNameIsBetweenTheLastAndTheFirst() {
        // A lap goes round: the kink before turn 1 comes after the last turn.
        let corners = [Self.corner(north: -150)] + (0..<5).map { Self.corner(north: Double($0) * 300) }
        #expect(CornerNaming.names(for: corners, pinned: Self.pinned)[0].label == "4–1")
    }

    @Test func eachNameGoesToTheNearestCornerOnce() {
        // Two corners inside the radius of one name: the nearer takes it, the other does not
        // take it as well.
        let corners = [Self.corner(north: 0), Self.corner(north: 30), Self.corner(north: 300)]
        let names = CornerNaming.names(for: corners, pinned: [Self.pin("1", north: 25), Self.pin("2", north: 300)])
        #expect(names.map(\.label) == ["2–1", "1", "2"])
    }

    @Test func pinsNoCornerMatchesFallBackToTheCount() {
        // Names from somewhere else entirely — another circuit's file — name nothing here.
        let corners = (0..<3).map { Self.corner(north: 10_000 + Double($0) * 300) }
        let names = CornerNaming.names(for: corners, pinned: Self.pinned)
        #expect(names.map(\.label) == ["1", "2", "3"])
        #expect(names.allSatisfy { $0.source == .counted })
    }

    @Test func aCornerPlacedByDistanceAloneIsNotMatched() {
        var corner = Self.corner(north: 0)
        corner.apexLatitude = nil
        #expect(CornerNaming.match([corner], to: Self.pinned) == [nil])
    }

    @Test func theFirstNameGivenPinsEveryCornerAsItIsShown() {
        let corners = (0..<4).map { Self.corner(north: Double($0) * 300) }
        let pinned = CornerNaming.renaming(3, to: "3a", corners: corners, pinned: [], legacy: ["1", "", "3"])
        #expect(pinned.map(\.label) == ["1", "2", "3", "3a"])
        // And they stay put on a lap with an extra corner.
        let extra = corners + [Self.corner(north: 750)]
        let sorted = extra.sorted { $0.apexDistance < $1.apexDistance }
        #expect(CornerNaming.names(for: sorted, pinned: pinned).map(\.label) == ["1", "2", "3", "3–3a", "3a"])
    }

    @Test func renamingChangesOnlyThatTurn() {
        let corners = (0..<5).map { Self.corner(north: Double($0) * 300) }
        let pinned = CornerNaming.renaming(2, to: " Carousel ", corners: corners, pinned: Self.pinned)
        #expect(pinned.map(\.label) == ["1", "2", "Carousel", "3a", "4"])
        #expect(pinned[2].latitude == Self.pinned[2].latitude)
    }

    @Test func aBlankNameUnpinsTheTurn() {
        let corners = (0..<5).map { Self.corner(north: Double($0) * 300) }
        let pinned = CornerNaming.renaming(4, to: "  ", corners: corners, pinned: Self.pinned)
        #expect(pinned.map(\.label) == ["1", "2", "3", "3a"])
        #expect(CornerNaming.names(for: corners, pinned: pinned)[4].label == "3a–1")
    }

    @Test func namingACornerNoNameReachesAddsOne() {
        let corners = [0, 300, 450].map { Self.corner(north: Double($0)) }
        let pinned = CornerNaming.renaming(2, to: "2a", corners: corners, pinned: Self.pinned)
        #expect(pinned.count == Self.pinned.count + 1)
        #expect(CornerNaming.names(for: corners, pinned: pinned).map(\.label) == ["1", "2", "2a"])
    }

    @Test func namesSetOnAnotherLapAreKept() {
        // This lap does not find 3a; renaming turn 1 must not lose it.
        let corners = [0, 300, 600, 1_200].map { Self.corner(north: Double($0)) }
        let pinned = CornerNaming.renaming(0, to: "Turn One", corners: corners, pinned: Self.pinned)
        #expect(pinned.map(\.label) == ["Turn One", "2", "3", "3a", "4"])
    }

    @Test func detectedCornersCarryTheirApexPosition() throws {
        let session = SyntheticTrack.session()
        let lap = try #require(session.laps.first)
        let corners = CornerDetector.corners(of: lap, in: session)
        let latitudes = try #require(session[.latitude]).values
        let longitudes = try #require(session[.longitude]).values
        #expect(!corners.isEmpty)
        for corner in corners {
            let latitude = try #require(corner.apexLatitude)
            let longitude = try #require(corner.apexLongitude)
            // The apex is a point of the lap's own trace.
            let nearest = zip(latitudes, longitudes).map {
                DerivedChannels.distance(lat1: latitude, lon1: longitude, lat2: $0, lon2: $1)
            }
            .min()
            #expect((nearest ?? .infinity) < CornerDetector.Options().stepMeters * 2)
        }
    }

    @Test func aSessionPrefersPinnedNamesToItsList() throws {
        var session = SyntheticTrack.session()
        let lap = try #require(session.laps.first)
        let corners = CornerDetector.corners(of: lap, in: session)
        session.cornerLabels = ["A", "B"]
        #expect(session.cornerNames(for: corners).map(\.label) == ["A", "B"])
        session.turnNames = try corners.reversed().enumerated().map { offset, corner in
            TurnName(
                label: "pinned \(offset)", latitude: try #require(corner.apexLatitude),
                longitude: try #require(corner.apexLongitude))
        }
        #expect(session.cornerNames(for: corners).map(\.label) == ["pinned 1", "pinned 0"])
    }

    @Test func aCornerWrittenBeforeItHadAPlaceStillReads() throws {
        let json =
            #"{"startDistance":10,"endDistance":50,"apexDistance":30,"headingChangeDegrees":90,"lapLengthMeters":400}"#
        let corner = try JSONDecoder().decode(Corner.self, from: Data(json.utf8))
        #expect(corner.apexDistance == 30)
        #expect(corner.apexLatitude == nil)
        #expect(corner.trace.isEmpty)
    }

    @Test func aTurnNameSurvivesEncoding() throws {
        let data = try JSONEncoder().encode(Self.pinned)
        #expect(try JSONDecoder().decode([TurnName].self, from: data) == Self.pinned)
    }
}
