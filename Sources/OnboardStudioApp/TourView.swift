import ProjectModel
import SwiftUI

/// One callout of a tour: what it says, and the parts of the window it is about. The first of
/// `subjects` is the one it points at.
struct TourStep {
    let title: String
    let text: String
    let subjects: [TourRegion]

    /// Where the callout sits: off everything it talks about (#672).
    var region: TourRegion { TourPlacement.card(avoiding: Set(subjects)) }

    var alignment: Alignment {
        switch region {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// The arrow beside the title that says where to look; `nil` with nothing to point at.
    var arrow: String? {
        guard let subject = subjects.first else { return nil }
        switch TourPlacement.direction(from: region, to: subject) {
        case -1: return "arrow.left"
        case 1: return "arrow.right"
        default: return nil
        }
    }
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Which way to look: the callout is beside what it describes, not on it.
                        if let arrow = current.arrow, arrow == "arrow.left" {
                            Image(systemName: arrow).accessibilityHidden(true)
                        }
                        Text(current.title)
                        if let arrow = current.arrow, arrow == "arrow.right" {
                            Image(systemName: arrow).accessibilityHidden(true)
                        }
                    }
                    .font(.title3.bold())
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
                .padding(40)
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
            subjects: [.leading]),
        TourStep(
            title: "Preview and timeline",
            text: "The preview is the exact exported frame; drag objects to move them. Below it, the timeline shows "
                + "each video as a bar you can drag, trim at its edges and zoom (⌘= / ⌘−); segments switch "
                + "layouts over time.",
            subjects: [.center]),
        TourStep(
            title: "Inspector",
            text: "Everything about the selected input or object lives here: sync, picture, clips, gauge design. "
                + "With nothing selected it shows the project settings, Getting Started first.",
            subjects: [.trailing]),
    ]

    var body: some View {
        TourCallouts(steps: Self.steps, step: $editor.tourStep)
            // A sheet is not part of the tour: files dropped on the window mid-tour brought the
            // import sheet up with a callout left under it (#672).
            .onChange(of: editor.trackDayRequest?.id) { _, request in if request != nil { editor.tourStep = nil } }
    }
}

/// The Logbook's three steps (#452): the app opens there, and its tour used to be the editor's only.
struct LogbookTourOverlay: View {
    @Bindable var model: LogbookModel

    /// The steps for a logbook with sessions in it, or for an empty one, whose middle has no table
    /// yet: the second callout described one that was not there (#672).
    static func steps(isEmpty: Bool) -> [TourStep] {
        [
            TourStep(
                title: "Days, circuits and cars",
                text: "The sidebar narrows the sessions to a track day, a circuit, a car or a year. Begin a day "
                    + "with New Track Day…, or drop a day's files and videos on the window.",
                // The sidebar, and the middle too: its buttons are what this says to press.
                subjects: [.leading, .center]),
            TourStep(
                title: "Sessions",
                text: isEmpty
                    ? "Your sessions are listed here once a day's files are in: one row each, sortable by any "
                        + "column. Trends and Season, above, then show how you are getting on."
                    : "Every session in the logbook, sortable by any column. Select several to correct them at "
                        + "once, and right-click for more. Trends and Season, above, show how you are getting on.",
                subjects: [.center]),
            TourStep(
                title: "The session",
                text: "The chosen session's laps and conditions, and what to do with it: New Project makes an "
                    + "overlay video, Coach… walks you through the lap. With nothing chosen, Getting Started is "
                    + "here.",
                subjects: [.trailing]),
        ]
    }

    var body: some View {
        TourCallouts(steps: Self.steps(isEmpty: model.entries.isEmpty), step: $model.tourStep)
            // A sheet is not part of the tour (#672).
            .onChange(of: model.trackDayRequest?.id) { _, request in if request != nil { model.tourStep = nil } }
            .onChange(of: model.newDayRequested) { _, asked in if asked { model.tourStep = nil } }
    }
}
