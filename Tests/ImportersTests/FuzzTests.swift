import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

/// Deterministic mutations of every fixture and synthetic file, fed to every importer. The only
/// failure is a crash or a hang; throwing is the expected way to reject garbage.
enum Fuzz {
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

    /// One mutated copy of `data`: flips, truncation, duplicated or inserted chunks, digit storms.
    static func mutate(_ data: Data, seed: UInt64) -> Data {
        var random = Random(state: seed)
        var bytes = [UInt8](data)
        guard !bytes.isEmpty else { return Data([UInt8(random.below(256))]) }
        switch random.below(7) {
        case 0:
            for _ in 0..<(1 + random.below(20)) { bytes[random.below(bytes.count)] = UInt8(random.below(256)) }
        case 1:
            bytes = Array(bytes.prefix(random.below(bytes.count)))
        case 2:
            let start = random.below(bytes.count)
            let length = min(bytes.count - start, 1 + random.below(512))
            let chunk = Array(bytes[start..<start + length])
            bytes.insert(contentsOf: chunk, at: random.below(bytes.count))
        case 3:
            let garbage = (0..<(1 + random.below(64))).map { _ in UInt8(random.below(256)) }
            bytes.insert(contentsOf: garbage, at: random.below(bytes.count))
        case 4:
            // Numbers become enormous, negative or empty.
            let text = String(bytes: bytes, encoding: .utf8) ?? ""
            let replacements = ["999999999999999999999", "-1e308", "", "NaN", "0x10", "1,5"]
            let out = text.replacingOccurrences(
                of: #"\d+(\.\d+)?"#, with: replacements[random.below(replacements.count)], options: .regularExpression,
                range: text.startIndex..<text.index(text.startIndex, offsetBy: min(text.count, 2000)))
            bytes = Array(out.utf8)
        case 5:
            bytes.removeAll { $0 == 10 || $0 == 13 }
        default:
            let start = random.below(bytes.count)
            bytes.removeSubrange(start..<min(bytes.count, start + 1 + random.below(256)))
        }
        return Data(bytes)
    }

    /// FNV-1a so a failing case reproduces across runs (`String.hashValue` is per-process).
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Writes the mutation `iteration` of `seed` for `label` to `directory` (for reproducing).
    static func dump(_ seed: Data, label: String, iteration: Int, to directory: URL, ext: String) throws -> URL {
        let url = directory.appending(path: "fuzz-\(label)-\(iteration).\(ext)")
        try mutate(seed, seed: UInt64(iteration) &* 7_919 &+ stableHash(label)).write(to: url)
        return url
    }

    static let fixtures = [
        "racerender-basic.csv", "racechrono-v3.csv", "racechrono-v2.csv", "generic.csv", "harrys.csv", "track.gpx",
        "activity.tcx", "track.nmea", "session.vbo", "vbox-canbus.vbo", "dji-mavic.srt", "dji-osmo.srt",
        // A zip read by hand is the likeliest thing here to walk off the end of a buffer.
        "session.rcz",
    ]

    static func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(path: name)
    }

    /// Runs `body` on `iterations` mutations of `seed` data written to `ext` files; reports cases
    /// that take longer than `budget` seconds (a hang in disguise).
    static func run(
        _ seed: Data, ext: String, iterations: Int, budget: Double = 5, label: String,
        body: (URL) throws -> Void
    ) throws {
        for iteration in 0..<iterations {
            let mutated = mutate(seed, seed: UInt64(iteration) &* 7_919 &+ stableHash(label))
            let url = FileManager.default.temporaryDirectory.appending(
                path: "fuzz-\(label)-\(iteration)-\(UUID().uuidString).\(ext)")
            try mutated.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let started = Date()
            if ProcessInfo.processInfo.environment["FUZZ_TRACE"] != nil {
                FileHandle.standardError.write(Data("FUZZ \(label) \(iteration)\n".utf8))
            }
            _ = try? body(url)
            let elapsed = Date().timeIntervalSince(started)
            #expect(elapsed < budget, "\(label) iteration \(iteration) took \(elapsed) s")
        }
    }
}

@Suite("Importer fuzzing")
struct ImporterFuzzTests {
    @Test(arguments: Fuzz.fixtures) func mutatedFixturesNeverCrashTheDetectorOrImporters(fixture: String) throws {
        let seed = try Data(contentsOf: try Fuzz.fixtureURL(fixture))
        let ext = (fixture as NSString).pathExtension
        try Fuzz.run(seed, ext: ext, iterations: 150, label: fixture) { url in
            for candidate in try FormatDetector.candidates(for: url) {
                _ = try? candidate.importer.importSession(at: url)
            }
            // Every importer must also survive files it did not claim.
            for importer in FormatDetector.importers { _ = try? importer.importSession(at: url) }
        }
    }

    @Test func mutatedFITFilesNeverCrash() throws {
        let seed = FITFixture.make(seconds: 20, developerFields: true)
        try Fuzz.run(seed, ext: "fit", iterations: 500, label: "fit") { url in
            _ = try FITImporter().importSession(at: url)
        }
    }

    @Test func randomBytesAreRejectedNotCrashedOn() throws {
        var random = Fuzz.Random(state: 42)
        for iteration in 0..<30 {
            let bytes = (0..<(1 + random.below(4096))).map { _ in UInt8(random.below(256)) }
            let url = FileManager.default.temporaryDirectory.appending(path: "fuzz-random-\(iteration).bin")
            try Data(bytes).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            for importer in FormatDetector.importers { _ = try? importer.importSession(at: url) }
        }
    }
}
