import Testing

@Suite("The drawing gate (#447)")
struct GPUGateTests {
    actor Log {
        var events: [String] = []
        func add(_ event: String) { events.append(event) }
    }

    @Test func aSecondTestWaitsUntilTheFirstLeaves() async {
        let gate = GPUGate()
        let log = Log()
        await gate.enter()
        let second = Task {
            await gate.enter()
            await log.add("second in")
            await gate.leave()
        }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await log.events.isEmpty, "the second came in while the gate was held")
        await log.add("first out")
        await gate.leave()
        await second.value
        #expect(await log.events == ["first out", "second in"])
        // Free again: the next comes straight in.
        await gate.enter()
        await gate.leave()
    }
}
