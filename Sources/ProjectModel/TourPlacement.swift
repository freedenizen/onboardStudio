import Foundation

/// A third of a window, as a tour's callout thinks of it: the sidebar's side, the middle, the
/// inspector's side.
public enum TourRegion: Sendable, CaseIterable {
    case leading, center, trailing
}

/// Where a tour's callout goes.
public enum TourPlacement {
    /// The region a callout sits in so that it is on none of `subjects`, the parts of the window
    /// it is talking about: the middle when that is free, else the trailing side, else the
    /// leading. The cards used to sit on what they described — the first over the sidebar it
    /// introduced and the button it said to press (#672).
    public static func card(avoiding subjects: Set<TourRegion>) -> TourRegion {
        [TourRegion.center, .trailing, .leading].first { !subjects.contains($0) } ?? .center
    }

    /// Which way a callout in `card` points to show `subject`: -1 towards the leading side, 1
    /// towards the trailing, 0 when it is on it (which `card(avoiding:)` never chooses).
    public static func direction(from card: TourRegion, to subject: TourRegion) -> Int {
        let order: [TourRegion] = [.leading, .center, .trailing]
        guard let here = order.firstIndex(of: card), let there = order.firstIndex(of: subject) else { return 0 }
        return (there - here).signum()
    }
}
