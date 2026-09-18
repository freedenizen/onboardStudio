import Foundation
import Testing

@testable import TelemetryKit

@Suite("Expression fuzzing")
struct ExpressionFuzzTests {
    @Test func randomTokenSoupNeverCrashes() {
        let atoms = [
            "speed", "rpm", "(", ")", "+", "-", "*", "/", "^", "1", "2.5", "1e400", "abs(", "sqrt(", "min(", "max(",
            ",", "if(", ">", "<", "==", "&&", "||", "!", "pi", "x", "aux:oil", "\"", "1/0", "-(", "%", "1e-400",
            "999999999999999999999999",
        ]
        var state: UInt64 = 99
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33)
        }
        for _ in 0..<3000 {
            let length = 1 + next() % 12
            let source = (0..<length).map { _ in atoms[next() % atoms.count] }.joined(
                separator: next() % 3 == 0 ? "" : " ")
            guard let expression = try? Expression(source) else { continue }
            _ = expression.evaluate { _ in Double(next() % 100) - 50 }
        }
    }
}
