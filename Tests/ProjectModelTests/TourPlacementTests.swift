import Testing

@testable import ProjectModel

/// A tour's callout is never on what it describes (#672).
@Suite("Tour callouts (#672)")
struct TourPlacementTests {
    @Test func aCalloutIsOffEverythingItTalksAbout() {
        for first in TourRegion.allCases {
            #expect(TourPlacement.card(avoiding: [first]) != first)
            for second in TourRegion.allCases where second != first {
                let card = TourPlacement.card(avoiding: [first, second])
                #expect(card != first && card != second)
            }
        }
    }

    @Test func theMiddleIsTakenWhenItIsFree() {
        #expect(TourPlacement.card(avoiding: [.leading]) == .center)
        #expect(TourPlacement.card(avoiding: [.trailing]) == .center)
        // The Logbook's first step: the sidebar, and the button in the middle it says to press.
        #expect(TourPlacement.card(avoiding: [.leading, .center]) == .trailing)
        #expect(TourPlacement.card(avoiding: [.center]) == .trailing)
    }

    @Test func aCalloutPointsTowardsItsSubject() {
        #expect(TourPlacement.direction(from: .center, to: .leading) == -1)
        #expect(TourPlacement.direction(from: .trailing, to: .leading) == -1)
        #expect(TourPlacement.direction(from: .center, to: .trailing) == 1)
        #expect(TourPlacement.direction(from: .leading, to: .center) == 1)
        #expect(TourPlacement.direction(from: .center, to: .center) == 0)
    }
}
