import Foundation
import Testing

/// Core Image drawing one test at a time, each with a deadline (#447).
///
/// Two goldens drawn through the compositor came back about 1.5 % different on CI now and then —
/// `steering-wheel-straight`, `speedometer-mph-5s` — always in the first second of the RenderKit
/// test process, while dozens of suites started at once, and a second render of the same frame in
/// the same run matched. Every golden test builds its own `FrameCompositor`, with its own Metal
/// `CIContext`, on a runner whose GPU is paravirtualised. Every suite that draws through Core
/// Image carries `.gpu`, which lets one of their tests run at a time across all of them, as
/// `.media` does for MediaKit's AVFoundation tests (#531, `MediaKitTests/MediaGate.swift`, whose
/// twin this is: test targets cannot share a source file).
///
/// A test still running `deadline` after it was let in names itself and stops the test process.
extension Trait where Self == GPUGateTrait {
    static var gpu: Self { GPUGateTrait() }
}

struct GPUGateTrait: SuiteTrait, TestTrait, TestScoping {
    /// The slowest drawing test takes seconds on a loaded runner; two minutes is a hang.
    /// `ONBOARD_GPU_TEST_DEADLINE` (seconds) shortens it, to see the watchdog work.
    static var deadline: Duration {
        let seconds = ProcessInfo.processInfo.environment["ONBOARD_GPU_TEST_DEADLINE"].flatMap(Double.init)
        return .seconds(seconds ?? 120)
    }

    var isRecursive: Bool { true }

    /// Each test function, not the suites around them.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> GPUGateTrait? {
        test.isSuite || testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        await GPUGate.shared.enter()
        let name = "\(test.id)"
        let deadline = Self.deadline
        let watchdog = Task.detached {
            try await Task.sleep(for: deadline)
            let line = "GPUGate: \(name) did not finish in \(deadline); stopping the test process (#447).\n"
            FileHandle.standardError.write(Data(line.utf8))
            exit(EXIT_FAILURE)
        }
        do {
            try await function()
        } catch {
            watchdog.cancel()
            await GPUGate.shared.leave()
            throw error
        }
        watchdog.cancel()
        await GPUGate.shared.leave()
    }
}

/// One holder at a time, the rest waiting in the order they came.
actor GPUGate {
    static let shared = GPUGate()
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
