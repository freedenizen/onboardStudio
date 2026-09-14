import Testing

@testable import TelemetryKit

@Suite("SessionBuilder")
struct SessionBuilderTests {
    func table(lapValues: [Double?]? = nil, markers: [RawLapMarker] = []) -> RawTable {
        var columns = [
            RawColumn(name: "KPH", unit: .kilometersPerHour, suggestedRole: .speed, values: [36, 72, nil, 144]),
            RawColumn(name: "Ignored", values: [1, 2, 3, 4]),
        ]
        if let lapValues {
            columns.append(RawColumn(name: "Lap", unit: .count, suggestedRole: .lap, values: lapValues))
        }
        return RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2, 3], columns: columns, lapMarkers: markers)
    }

    @Test func dropsUnmappedColumnsAndNilSamplesAndConvertsUnits() throws {
        let session = SessionBuilder.build(table())
        let speed = try #require(session[.speed])
        #expect(speed.unit == .metersPerSecond)
        #expect(speed.times == [0, 1, 3])
        #expect(abs(speed.values[2] - 40) < 1e-9)
        #expect(session[.aux("Ignored")] == nil)
    }

    @Test func roleOverridesWinOverSuggestions() {
        let options = SessionBuilder.Options(roleOverrides: ["ignored": .rpm])
        let session = SessionBuilder.build(table(), options: options)
        #expect(session[.rpm]?.values == [1, 2, 3, 4])
    }

    @Test func duplicateRolesBecomeAuxChannels() {
        var raw = table()
        raw.columns.append(
            RawColumn(
                name: "Speed", unit: .metersPerSecond, source: "obd", suggestedRole: .speed, values: [1, 2, 3, 4]))
        let session = SessionBuilder.build(raw)
        #expect(session[.speed]?.name == "KPH")
        #expect(session[.aux("Speed (obd)")]?.values == [1, 2, 3, 4])
    }

    @Test func lapsFromMarkersFollowRaceRenderSemantics() {
        let session = SessionBuilder.build(
            table(markers: [RawLapMarker(number: 0, time: 1), RawLapMarker(number: 1, time: 2.5)]))
        #expect(session.laps.count == 3)
        #expect(session.laps[0] == Lap(number: 0, start: 0, end: 1, isComplete: true))
        #expect(session.laps[1] == Lap(number: 1, start: 1, end: 2.5, isComplete: true))
        #expect(session.laps[2] == Lap(number: 2, start: 2.5, end: 3, isComplete: false))
    }

    @Test func lapsFromLapNumberTransitions() {
        let session = SessionBuilder.build(table(lapValues: [3, 3, 4, 4]))
        #expect(session.laps.count == 2)
        #expect(session.laps[0] == Lap(number: 3, start: 0, end: 2, isComplete: false))
        #expect(session.laps[1] == Lap(number: 4, start: 2, end: 3, isComplete: false))
        let fromZero = SessionBuilder.build(table(lapValues: [0, 0, 1, 1]))
        #expect(fromZero.laps[0].isComplete == true)
    }

    @Test func markersTakePrecedenceOverLapColumn() {
        let session = SessionBuilder.build(table(lapValues: [0, 0, 1, 1], markers: [RawLapMarker(number: 0, time: 2)]))
        #expect(session.laps.first?.end == 2)
    }

    @Test func sessionOrderingAndRange() {
        let session = SessionBuilder.build(table(lapValues: [0, 0, 1, 1]))
        #expect(session.orderedChannels.map(\.role) == [.speed, .lap])
        #expect(session.timeRange == 0...3)
        #expect(session.duration == 3)
    }
}

@Suite("Derived channels")
struct DerivedChannelsTests {
    // ~10 m north per sample at 1 Hz.
    let lat = Channel(
        role: .latitude, name: "Lat", unit: .degrees, times: [0, 1, 2], values: [45.0, 45.00009, 45.00018])
    let lon = Channel(role: .longitude, name: "Lon", unit: .degrees, times: [0, 1, 2], values: [-122, -122, -122])

    @Test func haversineDistance() {
        let d = DerivedChannels.distance(lat1: 45, lon1: -122, lat2: 45.00009, lon2: -122)
        #expect(abs(d - 10.0) < 0.1)
    }

    @Test func bearingNorthAndEast() {
        #expect(abs(DerivedChannels.bearing(lat1: 45, lon1: -122, lat2: 45.001, lon2: -122) - 0) < 0.01)
        #expect(abs(DerivedChannels.bearing(lat1: 45, lon1: -122, lat2: 45, lon2: -121.999) - 90) < 0.01)
    }

    @Test func speedHeadingAndDistanceFromPosition() throws {
        let speed = try #require(DerivedChannels.speed(latitude: lat, longitude: lon))
        #expect(speed.unit == .metersPerSecond)
        #expect(abs(speed.values[0] - 10) < 0.1)
        #expect(speed.values[2] == speed.values[1])
        let heading = try #require(DerivedChannels.heading(latitude: lat, longitude: lon))
        #expect(abs(heading.values[0]) < 0.01)
        let distance = try #require(DerivedChannels.distance(latitude: lat, longitude: lon))
        #expect(abs(distance.values[2] - 20) < 0.2)
    }

    @Test func builderDerivesOnlyWhenMissing() {
        let raw = RawTable(
            info: SessionInfo(sourceFormat: "t"), times: [0, 1, 2],
            columns: [
                RawColumn(name: "Lat", unit: .degrees, suggestedRole: .latitude, values: lat.values as [Double?]),
                RawColumn(name: "Lon", unit: .degrees, suggestedRole: .longitude, values: lon.values as [Double?]),
                RawColumn(name: "Speed", unit: .metersPerSecond, suggestedRole: .speed, values: [1, 1, 1]),
            ])
        let session = SessionBuilder.build(raw)
        #expect(session[.speed]?.name == "Speed")
        #expect(session[.heading]?.name == "Heading (from GPS)")
        #expect(session[.distance] != nil)
        let off = SessionBuilder.build(
            raw, options: .init(deriveHeadingFromPosition: false, deriveDistanceFromPosition: false))
        #expect(off[.heading] == nil && off[.distance] == nil)
    }
}
