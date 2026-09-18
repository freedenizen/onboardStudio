import Foundation
import Testing

@testable import GPMFKit
@testable import TelemetryKit

/// Builds GPMF payloads and a minimal MP4 around them so the whole path can be tested without a
/// real camera file.
enum GPMFFixture {
    static func item(_ key: String, type: Character, size: Int, repeatCount: Int, payload: Data) -> Data {
        var data = Data(key.utf8)
        data.append(UInt8(type.asciiValue ?? 0))
        data.append(UInt8(size))
        data.append(UInt8(repeatCount >> 8))
        data.append(UInt8(repeatCount & 0xFF))
        data.append(payload)
        while data.count % 4 != 0 { data.append(0) }
        return data
    }

    static func nested(_ key: String, _ children: [Data]) -> Data {
        let body = children.reduce(Data()) { $0 + $1 }
        return item(key, type: "\0", size: 1, repeatCount: body.count, payload: body)
    }

    static func be(_ value: Int32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    static func be(_ value: Int16) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    static func be(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    static func be(_ value: UInt64) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }

    static func string(_ key: String, _ text: String) -> Data {
        item(key, type: "c", size: text.utf8.count, repeatCount: 1, payload: Data(text.utf8))
    }

    struct GPSRow {
        var lat: Double
        var lon: Double
        var speed: Double
        var days: Int
        var secs: Double
        var fix: Int
    }

    struct AccelSample {
        var z: Double
        var x: Double
        var y: Double
    }

    /// A GPS9 stream: rows of (lat, lon, alt, 2D, 3D, days, secs, dop, fix) already scaled up.
    static func gpsStream(rows: [GPSRow], startMicros: UInt64) -> Data {
        var payload = Data()
        for row in rows {
            payload += be(Int32(row.lat * 1e7))
            payload += be(Int32(row.lon * 1e7))
            payload += be(Int32(12_000))  // 12 m altitude
            payload += be(Int32(row.speed * 1000))
            payload += be(Int32(row.speed * 1000 + 100))
            payload += be(Int32(row.days))
            payload += be(Int32(row.secs * 1000))
            payload += be(Int16(150))  // DOP 1.5
            payload += be(Int16(row.fix))
        }
        var scale = Data()
        for value: Int32 in [10_000_000, 10_000_000, 1000, 1000, 1000, 1, 1000, 100, 1] { scale += be(value) }
        return nested(
            "STRM",
            [
                item("STMP", type: "J", size: 8, repeatCount: 1, payload: be(startMicros)),
                string("STNM", "GPS (Lat., Long., Alt., 2D, 3D, days, secs, DOP, fix)"),
                string("TYPE", "lllllllSS"),
                item("SCAL", type: "l", size: 4, repeatCount: 9, payload: scale),
                item("GPS9", type: "?", size: 32, repeatCount: rows.count, payload: payload),
            ])
    }

    /// An accelerometer stream with ORIN "ZXY" and one scale, values in m/s² × 418.
    static func accelStream(samples: [AccelSample], startMicros: UInt64) -> Data {
        var payload = Data()
        for s in samples {
            payload += be(Int16(s.z * 418))
            payload += be(Int16(s.x * 418))
            payload += be(Int16(s.y * 418))
        }
        return nested(
            "STRM",
            [
                item("STMP", type: "J", size: 8, repeatCount: 1, payload: be(startMicros)),
                string("STNM", "Accelerometer"), string("ORIN", "ZXY"), string("SIUN", "m/s²"),
                item("SCAL", type: "s", size: 2, repeatCount: 1, payload: be(Int16(418))),
                item("ACCL", type: "s", size: 6, repeatCount: samples.count, payload: payload),
            ])
    }

    static func payload(streams: [Data]) -> Data {
        nested(
            "DEVC",
            [item("DVID", type: "L", size: 4, repeatCount: 1, payload: be(UInt32(1))), string("DVNM", "HERO13 Black")]
                + streams)
    }

    // MARK: - MP4 container

    static func box(_ type: String, _ body: Data) -> Data {
        var data = be(UInt32(body.count + 8))
        data += Data(type.utf8)
        data += body
        return data
    }

    static func fullBox(_ type: String, _ body: Data) -> Data { box(type, Data([0, 0, 0, 0]) + body) }

    /// An MP4 with only a `gpmd` track whose samples are `payloads`, each `durationMs` long.
    static func mp4(payloads: [Data], durationMs: UInt32 = 1001) -> Data {
        let ftyp = box("ftyp", Data("mp42".utf8) + be(UInt32(0)) + Data("mp42isom".utf8))
        let mdatBody = payloads.reduce(Data()) { $0 + $1 }
        let mdatOffset = ftyp.count + 8
        let mdat = box("mdat", mdatBody)
        // Sample tables.
        let entry = box("gpmd", Data(repeating: 0, count: 8))
        let stsd = fullBox("stsd", be(UInt32(1)) + entry)
        let stts = fullBox("stts", be(UInt32(1)) + be(UInt32(payloads.count)) + be(durationMs))
        let stsc = fullBox("stsc", be(UInt32(1)) + be(UInt32(1)) + be(UInt32(1)) + be(UInt32(1)))
        var sizes = be(UInt32(0)) + be(UInt32(payloads.count))
        for p in payloads { sizes += be(UInt32(p.count)) }
        let stsz = fullBox("stsz", sizes)
        var offsets = be(UInt32(payloads.count))
        var cursor = mdatOffset
        for p in payloads {
            offsets += be(UInt32(cursor))
            cursor += p.count
        }
        let stco = fullBox("stco", offsets)
        let stbl = box("stbl", stsd + stts + stsc + stsz + stco)
        let minf = box("minf", stbl)
        let hdlr = fullBox(
            "hdlr", be(UInt32(0)) + Data("meta".utf8) + Data(repeating: 0, count: 12) + Data("GoPro MET\0".utf8))
        let mdhd = fullBox(
            "mdhd",
            be(UInt32(0)) + be(UInt32(0)) + be(UInt32(1000)) + be(UInt32(durationMs * UInt32(payloads.count)))
                + Data([0, 0, 0, 0]))
        let mdia = box("mdia", mdhd + hdlr + minf)
        let tkhd = fullBox("tkhd", Data(repeating: 0, count: 80))
        let trak = box("trak", tkhd + mdia)
        let mvhd = fullBox("mvhd", Data(repeating: 0, count: 96))
        let moov = box("moov", mvhd + trak)
        return ftyp + mdat + moov
    }

    static func write(_ data: Data, name: String = "gpmf") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "overlaygen-\(name)-\(UUID().uuidString).mp4")
        try data.write(to: url)
        return url
    }
}

@Suite("GPMF parser")
struct GPMFParserTests {
    @Test func parsesNestedItemsAndTypes() {
        let payload = GPMFFixture.payload(streams: [
            GPMFFixture.gpsStream(
                rows: [
                    GPMFFixture.GPSRow(lat: 38.16155, lon: -122.45467, speed: 30, days: 9731, secs: 84946.5, fix: 3)
                ],
                startMicros: 1_000_000),
            GPMFFixture.accelStream(
                samples: [GPMFFixture.AccelSample(z: 9.8, x: 0.1, y: -0.2)], startMicros: 1_000_000),
        ])
        let items = GPMFParser.parse(payload)
        #expect(items.count == 1 && items[0].key == "DEVC" && items[0].isNested)
        let devc = items[0]
        #expect(devc["DVNM"]?.string == "HERO13 Black")
        #expect(devc["DVID"]?.numbers == [1])
        let streams = devc.all("STRM")
        #expect(streams.count == 2)
        let gps = streams[0]
        #expect(gps["TYPE"]?.string == "lllllllSS")
        #expect(gps["SCAL"]?.numbers.count == 9)
        #expect(gps["STMP"]?.numbers == [1_000_000])
        let rows = gps["GPS9"]?.rows(typeString: "lllllllSS") ?? []
        #expect(rows.count == 1 && rows[0].count == 9)
        #expect(abs(rows[0][0] / 1e7 - 38.16155) < 1e-7)
        #expect(rows[0][8] == 3)
        let accl = streams[1]
        #expect(accl["ORIN"]?.string == "ZXY")
        #expect(accl["ACCL"]?.numbers.count == 3)
        #expect(abs((accl["ACCL"]?.numbers[0] ?? 0) / 418 - 9.8) < 0.01)
    }

    @Test func utcDates() {
        // yymmddhhmmss.sss → 2026-08-23 23:35:46.500 UTC
        let epoch = GPMFParser.utcSeconds("260823233546.500")
        #expect(epoch.map { abs($0 - 1_787_528_146.5) < 1e-6 } == true)
        #expect(GPMFParser.utcSeconds("junk") == nil)
    }

    @Test func scalarDecodingCoversAllWidths() {
        let data = Data([0xFF, 0x80, 0x00, 0x00, 0x00, 0x01, 0x3F, 0x80, 0x00, 0x00])
        #expect(GPMFParser.scalar(data, at: 0, type: UInt8(ascii: "b")) == -1)
        #expect(GPMFParser.scalar(data, at: 0, type: UInt8(ascii: "B")) == 255)
        #expect(GPMFParser.scalar(data, at: 1, type: UInt8(ascii: "s")) == -32768)
        #expect(GPMFParser.scalar(data, at: 2, type: UInt8(ascii: "L")) == 1)
        #expect(GPMFParser.scalar(data, at: 6, type: UInt8(ascii: "f")) == 1)
    }
}

@Suite("GoPro telemetry")
struct GoProTelemetryTests {
    func fixtureURL() throws -> URL {
        // Two payloads a second apart: GPS at 10 Hz (no fix for the first two samples), accel at 4 Hz.
        var rows: [GPMFFixture.GPSRow] = []
        for i in 0..<10 {
            rows.append(
                GPMFFixture.GPSRow(
                    lat: 38.1 + Double(i) * 0.0001, lon: -122.4, speed: 10 + Double(i), days: 9731,
                    secs: 84946.0 + Double(i) * 0.1, fix: i < 2 ? 0 : 3))
        }
        let rows2 = rows.map {
            GPMFFixture.GPSRow(
                lat: $0.lat + 0.001, lon: $0.lon, speed: $0.speed + 10, days: $0.days, secs: $0.secs + 1, fix: 3)
        }
        func accel(_ xs: [Double]) -> [GPMFFixture.AccelSample] {
            xs.map { GPMFFixture.AccelSample(z: 9.8, x: $0, y: 0) }
        }
        let p1 = GPMFFixture.payload(streams: [
            GPMFFixture.gpsStream(rows: rows, startMicros: 0),
            GPMFFixture.accelStream(samples: accel([0, 1, 2, 3]), startMicros: 0),
        ])
        let p2 = GPMFFixture.payload(streams: [
            GPMFFixture.gpsStream(rows: rows2, startMicros: 1_000_000),
            GPMFFixture.accelStream(samples: accel([4, 5, 6, 7]), startMicros: 1_000_000),
        ])
        return try GPMFFixture.write(GPMFFixture.mp4(payloads: [p1, p2], durationMs: 1000))
    }

    @Test func readsTheMetadataTrackFromAnMP4() throws {
        let url = try fixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let track = try MP4Boxes.trackSamples("gpmd", in: url)
        #expect(track.count == 2 && track.timescale == 1000)
        #expect(track.times == [0, 1] && track.durations == [1, 1])
        #expect(MP4Boxes.hasTrack("gpmd", in: url))
        #expect(!MP4Boxes.hasTrack("avc1", in: url))
        let handle = try FileHandle(forReadingFrom: url)
        let data = try MP4Boxes.sampleData(track, index: 1, in: handle)
        #expect(data.count == track.sizes[1] && GPMFParser.parse(data).first?.key == "DEVC")
    }

    @Test func buildsChannelsWithVideoTimeAndRecordingStart() throws {
        let url = try fixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try GoProTelemetry.importFile(at: url)
        let session = SessionBuilder.build(table)
        #expect(session.info.sourceFormat == "GoPro GPMF" && session.info.title == "HERO13 Black")
        let speed = try #require(session[.speed])
        // 20 GPS rows minus the two without a fix.
        #expect(speed.count == 18)
        #expect(speed.firstTime.map { abs($0 - 0.2) < 1e-9 } == true)  // third sample of payload 1
        #expect(abs((speed.value(at: 1.0) ?? 0) - 20) < 1e-6)  // first sample of payload 2
        let lat = try #require(session[.latitude])
        #expect(abs((lat.value(at: 0.5) ?? 0) - 38.1005) < 1e-9)
        // Accelerometer: ORIN "ZXY" puts the second value on X, converted to G.
        let ax = try #require(session[.aux("accel_x")])
        #expect(ax.count == 8 && abs((ax.value(at: 1.25) ?? 0) - 5 / 9.80665) < 1e-3)
        let az = try #require(session[.aux("accel_z")])
        #expect(abs((az.value(at: 0) ?? 0) - 9.8 / 9.80665) < 1e-3)  // int16 quantisation
        // Recording start: the first fixed sample (t = 0.2 s) was at 2026-08-23 23:35:46.2 UTC.
        let epoch = 946_684_800.0 + 9731 * 86400 + 84946.2
        #expect(session.info.createdAt.map { abs($0.timeIntervalSince1970 - (epoch - 0.2)) < 1e-3 } == true)
        #expect(GoProTelemetry.recordingStartEpoch(of: url).map { abs($0 - (epoch - 0.2)) < 1e-3 } == true)
        #expect(session[.aux("gps_fix")]?.interpolation == .step)
    }

    @Test func rejectsFilesWithoutTheTrack() throws {
        let url = try GPMFFixture.write(Data("not an mp4 at all, just text".utf8), name: "text")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: MP4Boxes.ReadError.self) { try MP4Boxes.trackSamples("gpmd", in: url) }
        #expect(GoProTelemetry.recordingStartEpoch(of: url) == nil)
    }

    /// Runs only when a real GoPro clip is available locally (never committed).
    @Test func realClipWhenAvailable() throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERLAYGEN_SAMPLES_DIR"] else { return }
        let url = URL(fileURLWithPath: dir).appending(path: "GX010037.MP4")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let start = Date()
        let table = try GoProTelemetry.importFile(at: url)
        let session = SessionBuilder.build(table)
        let elapsed = Date().timeIntervalSince(start)
        print("real clip: \(session.channels.count) channels, \(session[.speed]?.count ?? 0) GPS rows in \(elapsed) s")
        #expect((session[.speed]?.count ?? 0) > 5000)
        #expect(session.duration > 700)
        #expect(session.info.createdAt != nil)
    }
}
