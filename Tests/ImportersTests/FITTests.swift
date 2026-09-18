import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

/// A tiny FIT encoder so the decoder can be tested without a committed binary fixture.
enum FITFixture {
    static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }
    static func be32(_ v: UInt32) -> [UInt8] { le32(v).reversed() }

    /// Records every second for `seconds` seconds at 10 m/s heading east, one lap at 3 s.
    static func make(seconds: Int = 6, bigEndian: Bool = false, developerFields: Bool = false) -> Data {
        var body: [UInt8] = []
        let arch: UInt8 = bigEndian ? 1 : 0
        func u16(_ v: UInt16) -> [UInt8] { bigEndian ? le16(v).reversed() : le16(v) }
        func u32(_ v: UInt32) -> [UInt8] { bigEndian ? be32(v) : le32(v) }
        func s32(_ v: Int32) -> [UInt8] { u32(UInt32(bitPattern: v)) }

        // Definition for record (global 20), local 0: timestamp, lat, lon, altitude, speed, distance, heart rate.
        var recordDefinition: [UInt8] = [0x40 | (developerFields ? 0x20 : 0), 0, arch] + u16(20) + [7]
        recordDefinition += [253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85, 2, 2, 0x84, 6, 2, 0x84, 5, 4, 0x86, 3, 1, 0x02]
        if developerFields { recordDefinition += [1, 0, 2, 0] }  // one developer field, 2 bytes
        body += recordDefinition
        // Definition for lap (global 19), local 1: timestamp, start_time.
        body += [0x41, 0, arch] + u16(19) + [2, 253, 4, 0x86, 2, 4, 0x86]
        // Definition for record without a timestamp field, local 2, for compressed-timestamp headers.
        body += [0x42, 0, arch] + u16(20) + [5, 0, 4, 0x85, 1, 4, 0x85, 2, 2, 0x84, 6, 2, 0x84, 5, 4, 0x86]

        let start: UInt32 = 1_000_000_000  // FIT seconds
        for i in 0..<seconds {
            let lat = Int32(45.0 / 180 * 2_147_483_648)
            let lon = Int32((-122.0 + Double(i) * 0.0001) / 180 * 2_147_483_648)
            body += [0]  // data message, local 0
            body += u32(start + UInt32(i)) + s32(lat) + s32(lon) + u16(UInt16((100 + 500) * 5)) + u16(UInt16(10_000))
            body += u32(UInt32(i * 1000)) + [UInt8(120 + i)]
            if developerFields { body += [0xAB, 0xCD] }
        }
        // A compressed-timestamp record 1 s after the last one (header 0x80 | local 2 << 5 | offset).
        let lastSeconds = start + UInt32(seconds - 1)
        let offsetBits = UInt8((lastSeconds + 1) & 0x1F)
        body += [0x80 | (2 << 5) | offsetBits]
        body +=
            s32(Int32(45.0 / 180 * 2_147_483_648)) + s32(Int32(-121.0 / 180 * 2_147_483_648)) + u16(0xFFFF)
            + u16(20_000)
        body += u32(UInt32(seconds * 1000))
        // Lap message: start at 3 s.
        body += [1] + u32(start + 5) + u32(start + 3)

        var header: [UInt8] = [14, 0x20] + le16(2_000) + le32(UInt32(body.count)) + Array(".FIT".utf8) + [0, 0]
        header[12] = 0
        header[13] = 0
        return Data(header + body + [0, 0])
    }

    static func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "overlaygen-\(UUID().uuidString).fit")
        try data.write(to: url)
        return url
    }
}

@Suite("FIT importer")
struct FITImporterTests {
    @Test func decodesRecordsLapsAndBothByteOrders() throws {
        for bigEndian in [false, true] {
            let url = try FITFixture.write(FITFixture.make(bigEndian: bigEndian))
            defer { try? FileManager.default.removeItem(at: url) }
            let table = try FITImporter().importFile(at: url)
            #expect(table.times == [0, 1, 2, 3, 4, 5, 6], "endian \(bigEndian)")
            let session = SessionBuilder.build(table)
            #expect(session.info.sourceFormat == "Garmin FIT")
            #expect(abs((session[.latitude]?.value(at: 0) ?? 0) - 45) < 1e-6)
            #expect(abs((session[.longitude]?.value(at: 2) ?? 0) - (-121.9998)) < 1e-6)
            #expect(abs((session[.altitude]?.value(at: 0) ?? 0) - 100) < 1e-9)
            #expect(session[.speed]?.value(at: 1) == 10)
            #expect(session[.distance]?.value(at: 4) == 40)  // 4000 cm
            #expect(session[.aux("heart_rate")]?.value(at: 2) == 122)
            // The compressed-timestamp record: 1 s later, 20 m/s, invalid altitude and heart rate skipped.
            #expect(session[.speed]?.value(at: 6) == 20)
            #expect(session[.altitude]?.lastTime == 5)
            #expect(session[.aux("heart_rate")]?.lastTime == 5)
            // FIT epoch: 1e9 s after 1989-12-31.
            #expect(session.info.createdAt?.timeIntervalSince1970 == 1_631_065_600.0)
            #expect(table.lapMarkers.map(\.time) == [3])
            #expect(session.laps.count >= 2)
        }
    }

    @Test func skipsDeveloperFields() throws {
        let url = try FITFixture.write(FITFixture.make(developerFields: true))
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try FITImporter().importFile(at: url)
        #expect(table.times.count == 7)
        #expect(table.columns.first { $0.name == "Heart rate" }?.values[1] == 121)
    }

    @Test func detectedBySignatureAndExtension() throws {
        let url = try FITFixture.write(FITFixture.make())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try FormatDetector.detect(url)?.id == "fit")
        let session = try FormatDetector.importSession(at: url)
        #expect(session.info.sourceFileName == url.lastPathComponent)
        #expect(throws: ImportError.self) {
            _ = try FITDecoder.decode(Data("not fit".utf8))
        }
    }
}
