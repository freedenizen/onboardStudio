import Testing

@testable import TelemetryKit

@Suite("Lap navigation")
struct LapNavigationTests {
    private let laps = [
        Lap(number: 1, start: 0, end: 90, isComplete: true),
        Lap(number: 2, start: 90, end: 178, isComplete: true),
        Lap(number: 3, start: 178, end: nil, isComplete: false),
    ]

    @Test func findsTheLapAroundATime() {
        #expect(laps.lap(containing: 0)?.number == 1)
        #expect(laps.lap(containing: 89.9)?.number == 1)
        #expect(laps.lap(containing: 90)?.number == 2, "a boundary belongs to the lap it starts")
        #expect(laps.lap(containing: 500)?.number == 3, "an unfinished lap runs to the end of the session")
        #expect(laps.lap(containing: -1) == nil)
    }

    /// Jumping must be strictly past the playhead or holding the shortcut sticks where it is.
    @Test func nextLapWalksForward() {
        #expect(laps.lap(startingAfter: 0)?.number == 2)
        #expect(laps.lap(startingAfter: 90)?.number == 3)
        #expect(laps.lap(startingAfter: 178) == nil, "there is nothing after the last lap's start")
    }

    /// Going back from mid-lap lands on the start of the lap you are in — the first press takes
    /// you to the beginning of the current one, as previous-edit does in an editor.
    @Test func previousLapGoesToTheStartOfTheCurrentLapFirst() {
        #expect(laps.lap(startingBefore: 120)?.number == 2)
        #expect(laps.lap(startingBefore: 90)?.number == 1, "sitting exactly on a start goes back past it")
        #expect(laps.lap(startingBefore: 0) == nil)
    }

    /// Scrubbing to a lap start leaves floating-point crumbs behind.
    @Test func jumpingToleratesScrubbingRoundoff() {
        #expect(laps.lap(startingAfter: 90.0000000001)?.number == 3)
        #expect(laps.lap(startingBefore: 89.9999999999)?.number == 1)
    }

    /// Laps out of order must not break navigation; nothing guarantees an importer's ordering.
    @Test func outOfOrderLapsStillNavigate() {
        let jumbled = [laps[2], laps[0], laps[1]]
        #expect(jumbled.lap(startingAfter: 0)?.number == 2)
        #expect(jumbled.lap(startingBefore: 200)?.number == 3)
    }

    @Test func anEmptySessionHasNowhereToGo() {
        let none: [Lap] = []
        #expect(none.lap(containing: 1) == nil)
        #expect(none.lap(startingAfter: 0) == nil)
        #expect(none.lap(startingBefore: 100) == nil)
    }
}
