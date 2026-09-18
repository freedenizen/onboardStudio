import Foundation
import Testing

@testable import Importers

/// Writes a specific fuzz case to FUZZ_REPRO_DIR for reproducing with the CLI. Skipped otherwise.
@Suite("Fuzz reproduction helper")
struct FuzzReproTests {
    @Test func dumpCase() throws {
        guard let dir = ProcessInfo.processInfo.environment["FUZZ_REPRO_DIR"],
            let spec = ProcessInfo.processInfo.environment["FUZZ_REPRO_CASE"]
        else { return }
        let parts = spec.split(separator: ":")
        let fixture = String(parts[0])
        let iteration = Int(parts[1]) ?? 0
        let seed = try Data(contentsOf: try Fuzz.fixtureURL(fixture))
        let url = try Fuzz.dump(
            seed, label: fixture, iteration: iteration, to: URL(fileURLWithPath: dir),
            ext: (fixture as NSString).pathExtension)
        print("wrote \(url.path)")
    }
}
