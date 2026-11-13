import ProjectModel
import SwiftUI

/// Above the preview while Getting Started has a step left (#451): what comes next, with its
/// button. Once a video and its data were in, the window showed the picture and nothing drawn on
/// it, and the checklist that said gauges came next was the last section of the project's
/// inspector — below the fold, and replaced by the new input's inspector the moment it was added.
/// An empty project has the welcome in the preview instead, which says the first step.
struct NextStepBar: View {
    @Bindable var editor: EditorModel
    @AppStorage(Preferences.showGettingStarted.key) private var show = true

    private var next: GettingStartedStep? { editor.gettingStartedSteps.first { !$0.done } }

    var body: some View {
        if show, !editor.project.inputs.isEmpty, let step = next {
            HStack(spacing: 10) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next step: \(step.title)").font(.callout.weight(.semibold))
                        .accessibilityIdentifier("nextStep.title")
                    Text(step.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .help(step.detail)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Button(GettingStartedSection.label(for: step.action)) {
                    GettingStartedSection.perform(step.action, in: editor)
                }
                .accessibilityIdentifier("nextStep.action")
                Button("Show All Steps") {
                    editor.deselectAll()
                    editor.showInspector = true
                }
                .help("The Getting Started checklist, first in the project's inspector")
                .accessibilityIdentifier("nextStep.showAll")
                Button {
                    show = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Hide Getting Started")
                .help("Hide Getting Started; Help ▸ Show Getting Started brings it back")
                .accessibilityIdentifier("nextStep.hide")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
        }
    }
}
