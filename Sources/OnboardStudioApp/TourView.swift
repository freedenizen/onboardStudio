import SwiftUI

/// One callout of a tour.
struct TourStep {
    let title: String
    let text: String
    let alignment: Alignment
}

/// A first-run tour: one callout at a time over a dimmed window, with Next and Skip. Shown once
/// per window kind, and again from Help ▸ Take the Tour — the editor's and the Logbook's (#452).
struct TourCallouts: View {
    let steps: [TourStep]
    @Binding var step: Int?

    var body: some View {
        if let index = step, steps.indices.contains(index) {
            let current = steps[index]
            ZStack(alignment: current.alignment) {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { advance() }
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(index + 1) of \(steps.count)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tour.step")
                    Text(current.title).font(.title3).bold()
                    Text(current.text).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Skip") { step = nil }.accessibilityIdentifier("tour.skip")
                        Spacer()
                        Button(index + 1 == steps.count ? "Done" : "Next") { advance() }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("tour.next")
                    }
                }
                .padding(20)
                .frame(width: 340)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 12)
                .padding(current.alignment == .bottom ? 90 : 40)
            }
        }
    }

    func advance() {
        guard let index = step else { return }
        step = index + 1 < steps.count ? index + 1 : nil
    }
}

/// The editor's three steps: one callout each for the sidebar, the preview and the inspector.
struct TourOverlay: View {
    @Bindable var editor: EditorModel

    static let steps: [TourStep] = [
        TourStep(
            title: "Inputs and objects",
            text: "The sidebar lists your videos, data files and the gauges drawn on top. Add a video with the "
                + "toolbar or drop files anywhere in the window.",
            alignment: .leading),
        TourStep(
            title: "Preview and timeline",
            text: "The preview is the exact exported frame; drag objects to move them. Below it, the timeline shows "
                + "each video as a bar you can drag, trim at its edges and zoom (⌘= / ⌘−); segments switch "
                + "layouts over time.",
            alignment: .bottom),
        TourStep(
            title: "Inspector",
            text: "Everything about the selected input or object lives here: sync, picture, clips, gauge design. "
                + "With nothing selected it shows the project settings, Getting Started first.",
            alignment: .trailing),
    ]

    var body: some View { TourCallouts(steps: Self.steps, step: $editor.tourStep) }
}

/// The Logbook's three steps (#452): the app opens there, and its tour used to be the editor's only.
struct LogbookTourOverlay: View {
    @Bindable var model: LogbookModel

    static let steps: [TourStep] = [
        TourStep(
            title: "Days, circuits and cars",
            text: "The sidebar narrows the sessions to a track day, a circuit, a car or a year. Begin a day with "
                + "New Track Day…, or drop a day's files and videos on the window.",
            alignment: .leading),
        TourStep(
            title: "Sessions",
            text: "Every session in the logbook, sortable by any column. Select several to correct them at once, "
                + "and right-click for more. Trends and Season, above, show how you are getting on.",
            alignment: .center),
        TourStep(
            title: "The session",
            text: "The chosen session's laps and conditions, and what to do with it: New Project makes an overlay "
                + "video, Coach… walks you through the lap. With nothing chosen, Getting Started is here.",
            alignment: .trailing),
    ]

    var body: some View { TourCallouts(steps: Self.steps, step: $model.tourStep) }
}
