import AppKit
import SwiftUI

/// Calls `onRow` when a click in the table behind it lands on a row, and `onEmpty` when it lands
/// on no row. A local event monitor, so the click itself still goes where it was going.
///
/// - The editor's sidebar clears its selection on a click in empty space, as AppKit's lists do
///   and SwiftUI's does not (#280).
/// - The Logbook's sessions take the keyboard on a click on a row. On macOS 27 a click on a
///   SwiftUI `Table` row selects it but leaves the keyboard where it was — in the search field,
///   or nowhere — so ⌘⌫ and the arrow keys did nothing to the sessions (#509). Watching the
///   selection is not enough: a click on the row already selected changes nothing.
struct TableClick: NSViewRepresentable {
    var onRow: (() -> Void)?
    var onEmpty: (() -> Void)?

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        update(view)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { update(view) }

    private func update(_ view: MonitorView) {
        view.onRow = onRow
        view.onEmpty = onEmpty
    }

    final class MonitorView: NSView {
        var onRow: (() -> Void)?
        var onEmpty: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        /// Only clicks inside this view, which lies behind the table and has its frame.
        private func handle(_ event: NSEvent) {
            guard let window, event.window === window,
                convert(bounds, to: nil).contains(event.locationInWindow),
                let hit = window.contentView?.hitTest(event.locationInWindow),
                let table = Self.table(containing: hit)
            else { return }
            if table.row(at: table.convert(event.locationInWindow, from: nil)) == -1 {
                onEmpty?()
            } else {
                onRow?()
            }
        }

        /// The table the click is in: an ancestor, or the document of an enclosing scroll view
        /// (the empty space below the last row belongs to the scroll view, not the table).
        private static func table(containing view: NSView) -> NSTableView? {
            var current: NSView? = view
            while let candidate = current {
                if let table = candidate as? NSTableView { return table }
                if let scroll = candidate as? NSScrollView { return scroll.documentView as? NSTableView }
                current = candidate.superview
            }
            return nil
        }
    }
}
