import Testing

@testable import MediaKit

/// An import whose sheet has been sent away, as the Logbook window shows it (#664).
@Suite("Add Files in the background (#664)")
struct TrackDayImportActivityTests {
    private typealias Activity = TrackDayImport.Activity
    private let step = TrackDayImport.Step(index: 2, count: 8, name: "session_3.csv")

    @Test("The sheet's button says the files go on being read, until there is a report to close")
    func closeTitle() {
        for phase in [TrackDayImport.Phase.waiting, .reading, .placing] {
            #expect(Activity(phase: phase).closeTitle == "Continue in Background")
            #expect(Activity(phase: phase).isWorking)
        }
        #expect(Activity(phase: .done).closeTitle == "Done")
        #expect(!Activity(phase: .done).isWorking)
        #expect(!Activity(phase: .asking).isWorking)
    }

    @Test("The sheet comes back for the question and for the report, and only when it was sent away")
    func sheetReturns() {
        #expect(Activity(phase: .done, isInBackground: true).wantsItsSheet)
        #expect(Activity(phase: .asking, isInBackground: true).wantsItsSheet)
        #expect(!Activity(phase: .reading, step: step, isInBackground: true).wantsItsSheet)
        #expect(!Activity(phase: .waiting, isInBackground: true).wantsItsSheet)
        #expect(!Activity(phase: .placing, isInBackground: true).wantsItsSheet)
        // On screen already: nothing to bring back.
        #expect(!Activity(phase: .done).wantsItsSheet)
        #expect(!Activity(phase: .asking).wantsItsSheet)
    }

    @Test("The Logbook's line names the file being read and how many there are")
    func line() {
        #expect(Activity(phase: .reading).line == "Looking for files…")
        #expect(Activity(phase: .reading, step: step).line == "Reading 3 of 8: session_3.csv…")
        #expect(Activity(phase: .waiting).line == "Waiting for the files before these…")
        #expect(Activity(phase: .asking).line == "Some files are from another day.")
        #expect(Activity(phase: .done).line == "The files are in the logbook.")
    }

    @Test("The bar is as far along as the files read, and only busy where no count is known")
    func fraction() {
        #expect(Activity(phase: .reading).fraction == nil)
        #expect(Activity(phase: .reading, step: step).fraction == 0.25)
        #expect(Activity(phase: .reading, step: .init(index: 0, count: 0, name: "")).fraction == 0)
        #expect(Activity(phase: .waiting).fraction == nil)
        #expect(Activity(phase: .placing).fraction == nil)
        #expect(Activity(phase: .done).fraction == 1)
    }

    @Test("The button that brings the sheet back says what it will show")
    func showTitle() {
        #expect(Activity(phase: .reading, step: step).showTitle == "Show Progress")
        #expect(Activity(phase: .asking).showTitle == "Answer…")
        #expect(Activity(phase: .done).showTitle == "Show Report")
    }
}
