import Foundation

/// How wide a session's detail is in the Logbook, as the driver left it (#483).
///
/// Neither of SwiftUI's own containers keeps it. A pane of an `HSplitView` is put back at its
/// minimum width every time it returns, and the split view has no autosave name; the system
/// inspector column opens at its ideal width once and at its minimum after that. Both were
/// measured. So the Logbook keeps the width in the preferences, and the app puts the split view's
/// divider back there whenever the detail returns (`LogbookDetailWidthKeeper`).
public enum LogbookDetailWidth {
    /// What the detail may be: wide enough for its buttons, never so wide it crowds the table.
    public static let range: ClosedRange<Double> = 320...420
    /// What the sessions beside it keep, whatever was dragged.
    public static let sessionsMinimum = 640.0
    public static let defaultsKey = "logbook.detailWidth"

    /// The width to show the detail at in a split view `available` points wide: what was kept,
    /// held to the range, and narrower than that only when the sessions would lose their minimum.
    /// What is kept is not changed by a narrow window: the detail is as wide as it was left again
    /// when there is room.
    public static func fitted(_ kept: Double, available: Double) -> Double {
        let widest = min(range.upperBound, max(range.lowerBound, available - sessionsMinimum))
        guard kept.isFinite else { return range.lowerBound }
        return min(max(kept, range.lowerBound), widest)
    }
}
