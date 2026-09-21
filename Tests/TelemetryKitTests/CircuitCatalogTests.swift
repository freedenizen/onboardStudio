import Foundation
import Testing

@testable import TelemetryKit

@Suite("Circuit catalogue")
struct CircuitCatalogTests {
    /// Measured from the reference RaceChrono session: 133k position samples at Sonoma.
    static let sonomaCentroid = (latitude: 38.16237, longitude: -122.45739)

    @Test func theBundledListLoads() {
        // The Wikidata query returned 1,290 named circuits. An exact count would break every
        // time the list is refreshed; an empty list means the resource did not ship, which is
        // the failure worth catching.
        #expect(CircuitCatalog.all.count > 1000)
        #expect(CircuitCatalog.all.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        #expect(CircuitCatalog.all.allSatisfy { abs($0.latitude) <= 90 && abs($0.longitude) <= 180 })
    }

    @Test func theReferenceSessionsCentroidFindsSonoma() throws {
        let match = try #require(
            CircuitCatalog.identify(latitude: Self.sonomaCentroid.latitude, longitude: Self.sonomaCentroid.longitude))
        #expect(match.circuit.name == "Sonoma Raceway")
        #expect(match.circuit.country == "US")
        // 0.27 km, with the runner-up 91 km away: a margin no coincidence produces.
        #expect(match.distanceKm < 1)
        #expect(try #require(match.runnerUpKm) > 50)
        #expect(match.isConfident)
    }

    @Test func theFilesOwnTrackNameConfirmsIt() throws {
        // RaceChrono writes `Track name,"Sonoma"` — short for the circuit's full name.
        let match = try #require(
            CircuitCatalog.identify(
                latitude: Self.sonomaCentroid.latitude, longitude: Self.sonomaCentroid.longitude,
                trackName: "Sonoma"))
        #expect(match.nameAgrees)
    }

    @Test func nowhereNearACircuitIsNoMatch() {
        // The middle of the South Atlantic.
        #expect(CircuitCatalog.identify(latitude: -30, longitude: -20) == nil)
        // And a venue just outside the radius is still no match.
        #expect(
            CircuitCatalog.identify(
                latitude: Self.sonomaCentroid.latitude + 0.5, longitude: Self.sonomaCentroid.longitude,
                maxDistanceKm: 10) == nil)
    }

    @Test func aSessionWithoutPositionIsNotIdentified() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [0, 1], values: [10, 10])])
        #expect(CircuitCatalog.centroid(of: session) == nil)
        #expect(CircuitCatalog.identify(session) == nil)
    }

    @Test func aSessionsCentroidIsTheMeanOfItsTrace() throws {
        let times = [0.0, 1, 2, 3]
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: [10, 12, 12, 10]),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: [20, 20, 24, 24]),
            ])
        let centre = try #require(CircuitCatalog.centroid(of: session))
        #expect(abs(centre.latitude - 11) < 1e-9)
        #expect(abs(centre.longitude - 22) < 1e-9)
    }

    @Test func searchingByName() {
        #expect(CircuitCatalog.search("sonoma").contains { $0.name == "Sonoma Raceway" })
        // Accents and punctuation are folded away, so the name can be typed plainly.
        #expect(CircuitCatalog.search("nurburgring").contains { $0.name.contains("rburgring") })
        #expect(CircuitCatalog.search("").isEmpty)
        #expect(CircuitCatalog.search("zzzzzznotacircuit").isEmpty)
        #expect(CircuitCatalog.search("circuit", limit: 5).count == 5)
    }

    @Test func lookingACircuitUpByItsWikidataID() throws {
        let sonoma = try #require(CircuitCatalog.circuit(id: "Q112563"))
        #expect(sonoma.name == "Sonoma Raceway")
        #expect(CircuitCatalog.circuit(id: "Q0") == nil)
    }

    @Test func displayNameIncludesTheCountryWhenThereIsOne() {
        #expect(
            Circuit(id: "Q1", name: "Somewhere", latitude: 0, longitude: 0, country: "GB").displayName
                == "Somewhere (GB)")
        #expect(Circuit(id: "Q1", name: "Somewhere", latitude: 0, longitude: 0).displayName == "Somewhere")
    }
}

@Suite("Circuit name matching")
struct CircuitNameTests {
    @Test func eitherNameMayContainTheOther() {
        #expect(CircuitCatalog.names("Sonoma", match: "Sonoma Raceway"))
        #expect(CircuitCatalog.names("Sonoma Raceway", match: "Sonoma"))
        #expect(CircuitCatalog.names("Spa", match: "Circuit de Spa-Francorchamps"))
        #expect(!CircuitCatalog.names("Laguna Seca", match: "Sonoma Raceway"))
        #expect(!CircuitCatalog.names(nil, match: "Sonoma Raceway"))
    }

    @Test func punctuationAccentsAndCaseAreIgnored() {
        #expect(CircuitCatalog.names("spa francorchamps", match: "Circuit de Spa-Francorchamps"))
        #expect(CircuitCatalog.names("NURBURGRING", match: "Nürburgring"))
        #expect(CircuitCatalog.names("Mazda Raceway (Laguna Seca)", match: "Laguna Seca"))
    }

    @Test func aTooShortNameNeverMatches() {
        // "Q1" or a stray initial would otherwise be inside half the list.
        #expect(!CircuitCatalog.names("A", match: "Anglesey Circuit"))
        #expect(!CircuitCatalog.names("Anglesey", match: "An"))
    }
}

@Suite("Choosing between nearby circuits")
struct CircuitTieBreakTests {
    /// Three venues sharing one coordinate, which the real list has: the Isle of Man's Clypse,
    /// Four Inch and Highroads courses all sit on the same point.
    static let coLocated = [
        Circuit(id: "Q1", name: "Alpha Course", latitude: 54.17167, longitude: -4.49194),
        Circuit(id: "Q2", name: "Beta Course", latitude: 54.17167, longitude: -4.49194),
        Circuit(id: "Q3", name: "Gamma Course", latitude: 54.17170, longitude: -4.49194),
    ]

    func identify(_ trackName: String?) -> CircuitCatalog.Match? {
        CircuitCatalog.identify(
            in: Self.coLocated, latitude: 54.17168, longitude: -4.49194, trackName: trackName, maxDistanceKm: 10)
    }

    @Test func withoutANameTheMatchIsNotConfident() throws {
        let match = try #require(identify(nil))
        #expect(!match.isConfident)
        #expect(try #require(match.runnerUpKm) < 0.1)
    }

    @Test func theFilesNamePicksTheRightOneEvenIfItIsNotTheNearest() throws {
        // Gamma is three metres further away than Alpha and Beta, and is still the answer
        // because the file says so.
        let match = try #require(identify("Gamma Course"))
        #expect(match.circuit.id == "Q3")
        #expect(match.nameAgrees)
        #expect(match.isConfident)
    }

    @Test func aNameNoneOfThemHasFallsBackToTheNearest() throws {
        let match = try #require(identify("Somewhere Else"))
        #expect(!match.nameAgrees)
        #expect(!match.isConfident)
    }

    @Test func aLoneCandidateHasNoRunnerUpAndIsTakenAtItsWord() throws {
        let match = try #require(
            CircuitCatalog.identify(
                in: [Self.coLocated[0]], latitude: 54.17168, longitude: -4.49194, trackName: nil, maxDistanceKm: 10))
        #expect(match.runnerUpKm == nil)
        #expect(match.isConfident)
    }
}

@Suite("Circuit list parsing")
struct CircuitParsingTests {
    @Test func aQuotedFieldMayContainCommas() {
        let rows = CircuitCatalog.parse(
            """
            id,name,latitude,longitude,country
            Q1,"Sears Point, Sonoma",38.16083,-122.45500,US
            Q2,Plain Name,1.5,2.5,GB
            """)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Sears Point, Sonoma")
        #expect(rows[1].latitude == 1.5)
    }

    @Test func aDamagedRowIsSkippedRatherThanFailingTheWholeList() {
        let rows = CircuitCatalog.parse(
            """
            id,name,latitude,longitude,country
            Q1,Good,1,2,GB
            Q2,Missing coordinates,,,
            ,No id,3,4,FR
            Q4,Not a number,abc,def,IT
            Q5,Also good,5,6,ES
            """)
        #expect(rows.map(\.id) == ["Q1", "Q5"])
    }

    @Test func doubledQuotesBecomeOne() {
        let rows = CircuitCatalog.parse("h\nQ1,\"The \"\"Ring\"\"\",1,2,DE")
        #expect(rows.first?.name == "The \"Ring\"")
    }
}
