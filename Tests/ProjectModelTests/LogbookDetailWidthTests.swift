import Testing

@testable import ProjectModel

/// #483: the width a session's detail was dragged to is the width it comes back at.
@Suite("The Logbook detail's width (#483)")
struct LogbookDetailWidthTests {
    @Test func whatWasKeptIsShownWhereThereIsRoom() {
        #expect(LogbookDetailWidth.fitted(380, available: 1400) == 380)
        #expect(LogbookDetailWidth.fitted(320, available: 1400) == 320)
        #expect(LogbookDetailWidth.fitted(420, available: 1400) == 420)
    }

    @Test func aKeptWidthOutOfRangeIsHeldToIt() {
        // A preference from another build, or one edited by hand.
        #expect(LogbookDetailWidth.fitted(90, available: 1400) == 320)
        #expect(LogbookDetailWidth.fitted(900, available: 1400) == 420)
        #expect(LogbookDetailWidth.fitted(.nan, available: 1400) == 320)
        #expect(LogbookDetailWidth.fitted(.infinity, available: 1400) == 320)
    }

    @Test func aNarrowWindowGivesTheSessionsTheirMinimumFirst() {
        // 1,024 wide: the sessions keep 640, so a detail kept at 420 is shown at 384 — and is
        // 420 again when the window is wider, because what is kept is not what is shown.
        #expect(LogbookDetailWidth.fitted(420, available: 1024) == 384)
        #expect(LogbookDetailWidth.fitted(350, available: 1024) == 350)
        // Narrower than both minimums together it is the detail's minimum, never less.
        #expect(LogbookDetailWidth.fitted(420, available: 900) == 320)
    }
}
