import SwiftUI

/// A three-step first-run tour: one callout each for the sidebar, the preview and the inspector.
/// Shown once (Help ▸ Take the Tour repeats it).
struct TourOverlay: View {
    @Bindable var editor: EditorModel
    private var step: Int? {
        get { editor.tourStep }
        nonmutating set { editor.tourStep = newValue }
    }

    struct Step {
        let title: String
        let text: String
        let alignment: Alignment
    }

    static let steps: [Step] = [
        Step(
            title: "Inputs and objects",
            text: "The sidebar lists your videos, data files and the gauges drawn on top. Add a video with the "
                + "toolbar or drop files anywhere in the window.",
            alignment: .leading),
        Step(
            title: "Preview and timeline",
            text: "The preview is the exact exported frame; drag objects to move them. Below it, the timeline shows "
                + "each video as a bar you can drag, trim at its edges and zoom (⌘= / ⌘−); segments switch "
                + "layouts over time.",
            alignment: .bottom),
        Step(
            title: "Inspector",
            text: "Everything about the selected input or object lives here: sync, picture, clips, gauge design. "
                + "With nothing selected it shows the project settings and the Getting Started checklist.",
            alignment: .trailing),
    ]

    var body: some View {
        if let index = step, Self.steps.indices.contains(index) {
            let current = Self.steps[index]
            ZStack(alignment: current.alignment) {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { advance() }
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(index + 1) of \(Self.steps.count)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tour.step")
                    Text(current.title).font(.title3).bold()
                    Text(current.text).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Skip") { step = nil }.accessibilityIdentifier("tour.skip")
                        Spacer()
                        Button(index + 1 == Self.steps.count ? "Done" : "Next") { advance() }
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
        step = index + 1 < Self.steps.count ? index + 1 : nil
    }
}
