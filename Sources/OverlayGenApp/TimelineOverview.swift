import ProjectModel
import SwiftUI

/// A thin strip showing the whole project with every video as a small bar and a rectangle for
/// the part the zoomed timeline currently shows; drag the rectangle (or click) to scroll there.
struct TimelineOverview: View {
    @Bindable var editor: EditorModel
    /// Fraction of the whole timeline that is visible (1 when zoomed to fit).
    let visibleFraction: Double
    /// Called with the fraction (0…1) of the timeline the visible window should start at.
    let scrollTo: (Double) -> Void

    private let height: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let duration = max(editor.timelineDuration, 0.001)
            let windowWidth = max(width * visibleFraction, 8)
            let windowX = width * editor.timelineScrollFraction
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(nsColor: .underPageBackgroundColor))
                ForEach(editor.project.videoInputs) { video in
                    let start = video.sync.offsetInProject
                    let end = editor.end(of: video) ?? start
                    RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.6))
                        .frame(width: max(width * (end - start) / duration, 2), height: 6)
                        .offset(x: width * start / duration)
                }
                Rectangle().fill(Color.red).frame(width: 1, height: height)
                    .offset(x: width * min(editor.currentTime, duration) / duration)
                if visibleFraction < 0.999 {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.12)))
                        .frame(width: windowWidth, height: height - 2)
                        .offset(x: min(max(windowX, 0), width - windowWidth), y: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    guard visibleFraction < 0.999 else { return }
                    let fraction = (value.location.x - windowWidth / 2) / width
                    scrollTo(min(max(fraction, 0), 1 - visibleFraction))
                }
            )
        }
        .frame(height: height)
        .help("The whole project; drag the window to scroll the zoomed timeline")
    }
}
