import Foundation
import Testing

@testable import GPMFKit

@Suite("GPMF and MP4 fuzzing")
struct GPMFFuzzTests {
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    }

    static func mutate(_ data: Data, random: inout Random) -> Data {
        var bytes = [UInt8](data)
        switch random.below(4) {
        case 0: for _ in 0..<(1 + random.below(24)) { bytes[random.below(bytes.count)] = UInt8(random.below(256)) }
        case 1: bytes = Array(bytes.prefix(random.below(bytes.count)))
        case 2:
            let at = random.below(bytes.count)
            bytes.insert(contentsOf: (0..<(1 + random.below(32))).map { _ in UInt8(random.below(256)) }, at: at)
        default:
            let start = random.below(bytes.count)
            bytes.removeSubrange(start..<min(bytes.count, start + 1 + random.below(64)))
        }
        return Data(bytes)
    }

    /// One second of GPS and accelerometer data, as the fixture tests build it.
    static func seedPayload(second: Int) -> Data {
        let rows = (0..<10).map { index in
            GPMFFixture.GPSRow(
                lat: 45 + Double(index) * 1e-5, lon: -122, speed: 10, days: 20_000,
                secs: Double(second) + Double(index) / 10,
                fix: 3)
        }
        let samples = (0..<20).map { index in GPMFFixture.AccelSample(z: 9.8, x: Double(index), y: 0) }
        let micros = UInt64(second) * 1_000_000
        return GPMFFixture.payload(streams: [
            GPMFFixture.gpsStream(rows: rows, startMicros: micros),
            GPMFFixture.accelStream(samples: samples, startMicros: micros),
        ])
    }

    @Test func mutatedGPMFPayloadsParse() {
        var random = Random(state: 7)
        let seed = Self.seedPayload(second: 0)
        for _ in 0..<1500 {
            let items = GPMFParser.parse(Self.mutate(seed, random: &random))
            for item in items where !item.isNested {
                _ = item.numbers
                _ = item.string
                _ = item.rows(typeString: "Llf")
            }
        }
    }

    @Test func mutatedMP4ContainersNeverCrashTheBoxReader() throws {
        var random = Random(state: 11)
        let seed = GPMFFixture.mp4(payloads: [Self.seedPayload(second: 0), Self.seedPayload(second: 1)])
        for iteration in 0..<800 {
            let url = FileManager.default.temporaryDirectory.appending(path: "fuzz-mp4-\(iteration).mp4")
            try Self.mutate(seed, random: &random).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let started = Date()
            _ = MP4Boxes.hasTrack("gpmd", in: url)
            _ = try? GoProTelemetry.importFile(at: url)
            _ = GoProTelemetry.recordingStartEpoch(of: url)
            #expect(Date().timeIntervalSince(started) < 5, "iteration \(iteration) hung")
        }
    }
}
