import SwiftUI

/// Lays views out in a row and starts a new row when the next one does not fit, as text wraps.
///
/// For a group of buttons in a column the user can resize. An `HStack` given too little width
/// shares it out by truncating every title — "C…", "Re…", "Ex…" (#448); this keeps each view at
/// the size it asks for and uses another row instead.
struct FlowLayout: Layout {
    /// Where each view goes, and the size of the whole.
    struct Arrangement: Equatable {
        var origins: [CGPoint] = []
        var size: CGSize = .zero
    }

    /// `sizes` in rows no wider than `width`, each row centred on its tallest view. `gaps[i]` is
    /// the space between view `i` and the next when they share a row. A view wider than `width`
    /// gets a row to itself.
    static func arrange(_ sizes: [CGSize], gaps: [CGFloat], rowSpacing: CGFloat, width: CGFloat) -> Arrangement {
        var rows: [[Int]] = []
        var rowWidth: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if let previous = rows.last?.last, rowWidth + gaps[previous] + size.width <= width {
                rows[rows.count - 1].append(index)
                rowWidth += gaps[previous] + size.width
            } else {
                rows.append([index])
                rowWidth = size.width
            }
        }
        var arrangement = Arrangement(origins: Array(repeating: .zero, count: sizes.count))
        var y: CGFloat = 0
        for (number, row) in rows.enumerated() {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x: CGFloat = 0
            for (position, index) in row.enumerated() {
                if position > 0 { x += gaps[row[position - 1]] }
                arrangement.origins[index] = CGPoint(x: x, y: y + (height - sizes[index].height) / 2)
                x += sizes[index].width
            }
            arrangement.size.width = max(arrangement.size.width, x)
            y += height + (number < rows.count - 1 ? rowSpacing : 0)
        }
        arrangement.size.height = y
        return arrangement
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(of: subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangement(of: subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            // Its own size, or the row's width when even a row to itself is too narrow for it.
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
        }
    }

    /// The views at the sizes they ask for, with the system's own spacing between them.
    private func arrangement(of subviews: Subviews, width: CGFloat) -> Arrangement {
        let gaps = zip(subviews, subviews.dropFirst()).map { $0.spacing.distance(to: $1.spacing, along: .horizontal) }
        let rowSpacing = subviews.first.map { $0.spacing.distance(to: $0.spacing, along: .vertical) } ?? 0
        return Self.arrange(
            subviews.map { $0.sizeThatFits(.unspecified) }, gaps: gaps, rowSpacing: rowSpacing, width: width)
    }
}
