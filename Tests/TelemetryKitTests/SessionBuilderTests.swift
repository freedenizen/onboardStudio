import Testing

@testable import TelemetryKit

@Suite("Attribute-first mapping")
struct AttributeMappingBuildTests {
    /// A file where the importer's guess and the user's mapping disagree, and the guess comes
    /// first in the file — the case the column-order rule used to get wrong.
    func table() -> RawTable {
        RawTable(
            info: SessionInfo(sourceFormat: "test"),
            times: [0, 1],
            columns: [
                RawColumn(name: "Brake", unit: .percent, suggestedRole: .brake, values: [10, 20]),
                RawColumn(name: "canbus:front_brake_pressure", unit: .none, values: [100, 200]),
            ])
    }

    @Test func anAttributeTakesTheColumnItIsPointedAt() throws {
        let session = SessionBuilder.build(
            table(), options: .init(sourceColumns: [.brake: "canbus:front_brake_pressure"]))
        let brake = try #require(session[.brake])
        #expect(brake.name == "canbus:front_brake_pressure")
        #expect(brake.values == [100, 200])
    }

    /// The column that lost the role is kept as an aux channel rather than dropped: it is still
    /// data the user can bind an object to.
    @Test func theGuessThatLosesTheRoleBecomesAux() {
        let session = SessionBuilder.build(
            table(), options: .init(sourceColumns: [.brake: "canbus:front_brake_pressure"]))
        #expect(session[.aux("Brake")] != nil)
    }

    @Test func theColumnIsMatchedWithoutRegardToCase() throws {
        let session = SessionBuilder.build(
            table(), options: .init(sourceColumns: [.brake: "CANBUS:FRONT_BRAKE_PRESSURE"]))
        #expect(try #require(session[.brake]).values == [100, 200])
    }

    /// The milestone's example: the file says nothing about the unit, the user says kPa. Reading
    /// changes; the stored numbers do not, because brake's canonical unit does not accept kPa.
    @Test func anAttributeIsReadInTheUnitTheUserGives() throws {
        let session = SessionBuilder.build(
            table(),
            options: .init(
                sourceColumns: [.brake: "canbus:front_brake_pressure"], sourceUnits: [.brake: .kilopascal]))
        let brake = try #require(session[.brake])
        #expect(brake.unit == .kilopascal)
        #expect(brake.values == [100, 200])
    }

    /// A source unit needs no source column: the usual case is a column matched correctly whose
    /// unit is missing or wrong.
    @Test func aSourceUnitAloneCorrectsTheColumnThatWasMatched() throws {
        let raw = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1],
            columns: [RawColumn(name: "Speed", unit: .none, suggestedRole: .speed, values: [36, 72])])
        let session = SessionBuilder.build(raw, options: .init(sourceUnits: [.speed: .kilometersPerHour]))
        let speed = try #require(session[.speed])
        #expect(speed.unit == .metersPerSecond)
        #expect(abs(speed.values[0] - 10) < 1e-9)
        #expect(session.recordedUnit(of: .speed) == .kilometersPerHour)
    }

    /// The column-keyed overrides name a column in this very file, so they stay the most specific
    /// thing there is — a project saved before the table existed keeps the mapping it had.
    @Test func theColumnKeyedOverridesStillWin() throws {
        let session = SessionBuilder.build(
            table(),
            options: .init(
                roleOverrides: ["Brake": .brake], unitOverrides: ["Brake": .percent],
                sourceColumns: [.brake: "canbus:front_brake_pressure"], sourceUnits: [.brake: .kilopascal]))
        let brake = try #require(session[.brake])
        #expect(brake.name == "Brake")
        #expect(brake.unit == .percent)
    }

    /// Without this the table can only offer columns the importer already understood — and the
    /// column a user most needs to point an attribute at is the one it ignored.
    @Test func everyColumnTheFileOfferedIsRemembered() {
        let session = SessionBuilder.build(table())
        #expect(session.sourceColumns == ["Brake", "canbus:front_brake_pressure"])
        #expect(session.channels.count == 1)
    }

    @Test func attributeNamesAreReadable() {
        #expect(ChannelRole.lateralG.displayName == "Lateral G")
        #expect(ChannelRole.canbus("front_brake_pressure").displayName == "canbus:front_brake_pressure")
        #expect(ChannelRole.mappableAttributes.contains(.brake))
        // Structure and computed channels have no source column to choose.
        #expect(!ChannelRole.mappableAttributes.contains(.time))
        #expect(!ChannelRole.mappableAttributes.contains(.lapDelta))
        #expect(Set(ChannelRole.mappableAttributes).isSubset(of: Set(ChannelRole.standardRoles)))
    }

    /// Nothing mapped must build exactly the session it always built.
    @Test func noMappingChangesNothing() throws {
        let plain = SessionBuilder.build(table())
        let empty = SessionBuilder.build(table(), options: .init(sourceColumns: [:], sourceUnits: [:]))
        #expect(try #require(plain[.brake]).name == "Brake")
        #expect(try #require(empty[.brake]).name == "Brake")
        #expect(plain.channels.mapValues(\.name) == empty.channels.mapValues(\.name))
    }
}

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

    /// Canonicalisation rewrites the channel's unit, so the session must remember the file's own —
    /// and still remember it after resampling and smoothing have rebuilt the channel.
    @Test func rememberTheUnitAChannelWasRecordedIn() {
        let plain = SessionBuilder.build(table())
        #expect(plain[.speed]?.unit == .metersPerSecond)
        #expect(plain.recordedUnit(of: .speed) == .kilometersPerHour)
        #expect(plain.recordedUnits[.aux("Ignored")] == nil)

        let processed = SessionBuilder.build(table(), options: .init(resampleHertz: 10, smoothingSeconds: 0.5))
        #expect(processed.recordedUnit(of: .speed) == .kilometersPerHour)

        var raw = table()
        raw.columns[0].unit = .metersPerSecond
        let native = SessionBuilder.build(raw)
        #expect(native.recordedUnits[.speed] == nil, "Nothing was converted, so there is nothing to remember")
        #expect(native.recordedUnit(of: .speed) == .metersPerSecond)
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
