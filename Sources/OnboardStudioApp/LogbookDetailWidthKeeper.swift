import AppKit
import ProjectModel
import SwiftUI

/// Makes the Logbook's split view keep the width a session's detail was dragged to (#483).
///
/// SwiftUI's `HSplitView` has no autosave name and puts a pane back at its minimum width every
/// time the pane returns, and the system inspector column does the same after its first showing
/// (both measured). A divider of the app's own keeps the width but loses what the split view
/// gives for nothing. So the split view stays — since #503 the three-column `NavigationSplitView`
/// whose last column is the session — and this sits in that column, finds the `NSSplitView`
/// SwiftUI made, moves its last divider to the kept width when the column appears, and writes the
/// width down when the divider is dragged.
struct LogbookDetailWidthKeeper: View {
    @AppStorage(LogbookDetailWidth.defaultsKey, store: UITestSupport.paneDefaults)
    private var kept = LogbookDetailWidth.range.lowerBound

    var body: some View {
        Finder(kept: $kept).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private struct Finder: NSViewRepresentable {
        @Binding var kept: Double

        func makeNSView(context: Context) -> KeeperView {
            let view = KeeperView()
            view.kept = kept
            view.record = { kept = $0 }
            return view
        }

        func updateNSView(_ view: KeeperView, context: Context) { view.kept = kept }
    }

    final class KeeperView: NSView {
        var kept = LogbookDetailWidth.range.lowerBound
        var record: (Double) -> Void = { _ in }
        private weak var split: NSSplitView?
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard window != nil else { return }
            // The pane joins the split view after this view joins the window.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            var ancestor = superview
            while let view = ancestor, !(view is NSSplitView) { ancestor = view.superview }
            guard let split = ancestor as? NSSplitView, split.arrangedSubviews.count >= 2 else { return }
            self.split = split
            restore()
            observer = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main
            ) { [weak self] note in
                // A drag of the divider says what the driver wants; a resize of the window does not.
                let dragged = note.userInfo?["NSSplitViewDividerIndex"] != nil
                MainActor.assumeIsolated { self?.resized(byDivider: dragged) }
            }
        }

        /// The divider to where the kept width puts it, in a split view this wide.
        private func restore() {
            guard let split, let pane = split.arrangedSubviews.last else { return }
            let target = LogbookDetailWidth.fitted(kept, available: split.bounds.width)
            guard abs(pane.frame.width - target) > 0.5 else { return }
            split.setPosition(
                split.bounds.width - target - split.dividerThickness, ofDividerAt: split.arrangedSubviews.count - 2)
        }

        private func resized(byDivider: Bool) {
            guard byDivider, let pane = split?.arrangedSubviews.last else { return }
            let width = min(
                max(pane.frame.width, LogbookDetailWidth.range.lowerBound), LogbookDetailWidth.range.upperBound)
            if abs(width - kept) > 0.5 {
                kept = width
                record(width)
            }
        }
    }
}
