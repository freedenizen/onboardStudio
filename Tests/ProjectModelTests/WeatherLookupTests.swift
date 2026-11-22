import Foundation
import Testing

@testable import ProjectModel
@testable import TelemetryKit

/// #560: a session's weather from the hourly record for its place and time.
@Suite("Weather from the hourly record (#560)")
struct WeatherLookupTests {
    /// 14 June 2026, 00:00 GMT: where the fixture starts.
    static let midnight = Date(timeIntervalSince1970: 1_781_395_200)

    static func hourly() throws -> WeatherLookup.Hourly {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Tests/Fixtures/weather.d/open-meteo-hourly.json")
        return try WeatherLookup.parse(Data(contentsOf: url))
    }

    static func session(at hour: Double, for minutes: Double) -> WeatherLookup.Request {
        WeatherLookup.Request(
            latitude: 38.161, longitude: -122.454, start: midnight.addingTimeInterval(hour * 3600),
            duration: minutes * 60)
    }

    @Test func theRecordIsReadInFull() throws {
        let hourly = try Self.hourly()
        #expect(hourly.time.count == 18)
        #expect(hourly.time.first == Self.midnight)
        #expect(hourly.temperature[13] == 23 && hourly.precipitation[15] == 1.2 && hourly.cloudCover[0] == 95)
    }

    @Test func aDrySunnyMiddayIsReadAsThat() throws {
        let reading = WeatherLookup.reading(of: try Self.hourly(), for: Self.session(at: 12, for: 20))
        #expect(reading.weather == .sunny)
        #expect(reading.track == .dry)
        // Ten minutes in: a sixth of the way from 22 °C at noon to 23 °C at one.
        #expect(reading.airCelsius == 22.2)
    }

    @Test func rainInTheHoursBeforeLeavesTheSurfaceDamp() throws {
        let reading = WeatherLookup.reading(of: try Self.hourly(), for: Self.session(at: 5, for: 20))
        #expect(reading.weather == .cloudy)
        #expect(reading.track == .damp)
        #expect(reading.airCelsius == 10.6)
    }

    @Test func rainInEveryHourIsRainAndAWetSurface() throws {
        let reading = WeatherLookup.reading(of: try Self.hourly(), for: Self.session(at: 14.5, for: 120))
        #expect(reading.weather == .rain)
        #expect(reading.track == .wet)
    }

    @Test func rainInSomeHoursIsMixed() throws {
        let reading = WeatherLookup.reading(of: try Self.hourly(), for: Self.session(at: 13.5, for: 120))
        #expect(reading.weather == .mixed)
        #expect(reading.track == .wet)
    }

    @Test func aSessionTheRecordDoesNotReachReadsNothing() throws {
        let reading = WeatherLookup.reading(of: try Self.hourly(), for: Self.session(at: 48, for: 20))
        #expect(reading == WeatherLookup.Reading())
    }

    @Test func somethingElseIsNotARecord() {
        #expect(throws: WeatherLookup.Failure.unreadable) {
            try WeatherLookup.parse(Data(#"{"error":true,"reason":"Parameter 'start_date' is out of range"}"#.utf8))
        }
    }

    @Test func onlyATenthOfADegreeAndTheDatesAreSent() throws {
        let request = Self.session(at: 12, for: 20)
        let now = Self.midnight.addingTimeInterval(30 * 86_400)
        let url = request.url(now: now)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "archive-api.open-meteo.com")
        #expect(query["latitude"] == "38.2" && query["longitude"] == "-122.5")
        // From six hours before, for the rain that left the surface damp.
        #expect(query["start_date"] == "2026-06-14" && query["end_date"] == "2026-06-14")
        #expect(query["timeformat"] == "unixtime" && query["timezone"] == "GMT")
        #expect(
            Set(query.keys) == ["latitude", "longitude", "start_date", "end_date", "hourly", "timezone", "timeformat"])
    }

    @Test func aRecentSessionIsReadFromTheForecastRecord() {
        let request = Self.session(at: 12, for: 20)
        #expect(request.url(now: Self.midnight.addingTimeInterval(2 * 86_400)).host() == "api.open-meteo.com")
    }

    @Test func onlyEmptyFieldsAreFilledAndNoted() {
        var conditions = SessionConditions(weather: .overcast, tyres: "RE-71RS")
        let filled = conditions.fill(from: .init(airCelsius: 18.4, weather: .sunny, track: .dry))
        #expect(filled)
        #expect(conditions.weather == .overcast, "The driver's weather was replaced")
        #expect(conditions.track == .dry && conditions.ambientCelsius == 18.4)
        #expect(conditions.lookedUp == [.track, .air])
        let again = conditions.fill(from: .init(airCelsius: 30, weather: .rain, track: .wet))
        #expect(!again, "Filled twice")
    }

    @Test func aLookedUpFieldTheDriverChangesIsTheirs() {
        var old = SessionConditions()
        old.fill(from: .init(airCelsius: 18, weather: .sunny, track: .dry))
        var changed = old
        changed.track = .damp
        #expect(changed.keepingLookups(from: old).lookedUp == [.weather, .air])
    }

    @Test func whatWasLookedUpIsKeptOnDiskAndAbsentWhenNothingWas() throws {
        var conditions = SessionConditions()
        conditions.fill(from: .init(airCelsius: 18, weather: .sunny, track: nil))
        let data = try JSONEncoder().encode(conditions)
        #expect(try JSONDecoder().decode(SessionConditions.self, from: data).lookedUp == [.weather, .air])
        let plain = try JSONEncoder().encode(SessionConditions(weather: .sunny))
        #expect(String(bytes: plain, encoding: .utf8)?.contains("lookedUp") == false)
    }

    @Test func anEntryRemembersItsLookup() throws {
        var entry = GarageTests.entry("a", car: "Miata")
        entry.weatherLookedUp = Self.midnight
        let again = try JSONDecoder().decode(LogbookEntry.self, from: JSONEncoder().encode(entry))
        #expect(again.weatherLookedUp == Self.midnight)
    }

    @Test func aSessionAtAKnownCircuitIsPlacedThere() throws {
        let circuit = try #require(CircuitCatalog.all.first)
        var entry = GarageTests.entry("a", car: "Miata")
        #expect(WeatherLookup.place(of: entry) == nil)
        entry.circuitID = circuit.id
        let place = try #require(WeatherLookup.place(of: entry))
        #expect(place.latitude == circuit.latitude && place.longitude == circuit.longitude)
    }
}
