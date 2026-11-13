import Foundation
import Testing

/// AVFoundation work one test at a time, each with a deadline (#531).
///
/// The Test job on CI's macOS 27 runners was cancelled at its 30-minute limit twice (#514, #529)
/// with the same signature: the other targets passed, then media tests started and never
/// finished and the log fell silent. The suites were `.serialized` only within themselves, so under
/// `--parallel` dozens of compositions, image generators, readers and exports ran at once on a
/// runner whose GPU is paravirtualised. Every suite that decodes, renders or writes media carries
/// `.media`, which lets one of their tests run at a time across all of them.
///
/// And a test that still has not finished `deadline` after it was let in names itself and stops
/// the test process: the job fails in minutes with the test's name, where it hung silently for
/// half an hour. A test cannot be abandoned and the next let in instead — the testing library does
/// not let its body outlive the scope that runs it.
extension Trait where Self == MediaGateTrait {
    static var media: Self { MediaGateTrait() }
}

struct MediaGateTrait: SuiteTrait, TestTrait, TestScoping {
    /// The slowest media test takes under 30 s on a loaded runner; four times that is a hang.
    /// `ONBOARD_MEDIA_TEST_DEADLINE` (seconds) shortens it, to see the watchdog work.
    static var deadline: Duration {
        let seconds = ProcessInfo.processInfo.environment["ONBOARD_MEDIA_TEST_DEADLINE"].flatMap(Double.init)
        return .seconds(seconds ?? 120)
    }

    var isRecursive: Bool { true }

    /// Each test function, not the suites around them.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> MediaGateTrait? {
        test.isSuite || testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        await MediaGate.shared.enter()
        let name = "\(test.id)"
        let deadline = Self.deadline
        let watchdog = Task.detached {
            try await Task.sleep(for: deadline)
            let line = "MediaGate: \(name) did not finish in \(deadline); stopping the test process (#531).\n"
            FileHandle.standardError.write(Data(line.utf8))
            exit(EXIT_FAILURE)
        }
        do {
            try await function()
        } catch {
            watchdog.cancel()
            await MediaGate.shared.leave()
            throw error
        }
        watchdog.cancel()
        await MediaGate.shared.leave()
    }
}

/// One holder at a time, the rest waiting in the order they came.
actor MediaGate {
    static let shared = MediaGate()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the gate to the next in line, which keeps it held.
    func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}
