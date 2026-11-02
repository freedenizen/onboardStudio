import ProjectModel
import SwiftUI
import TelemetryKit

extension EditorModel {
    /// Project ▸ Coaching… ▸ Make a Plan: the top opportunities as experiments (#330).
    func makePlan(from analysis: CoachingAnalysis, lapNumber: Int, for input: Input) {
        let plan = NextSessionPlan.suggested(from: analysis, lapNumber: lapNumber)
        edit("Make Plan") { $0.plan = plan }
        rememberPlan(for: input)
    }

    func setExperimentText(_ text: String, id: UUID, for input: Input) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = project.plan?.experiments.firstIndex(where: { $0.id == id }),
            project.plan?.experiments[index].text != trimmed
        else { return }
        edit("Edit Plan") { $0.plan?.experiments[index].text = trimmed }
        rememberPlan(for: input)
    }

    func addExperiment(for input: Input) {
        edit("Add Experiment") { $0.plan?.experiments.append(PlannedExperiment(cornerLabel: "", text: "")) }
    }

    func removeExperiment(id: UUID, for input: Input) {
        edit("Remove Experiment") { $0.plan?.experiments.removeAll { $0.id == id } }
        rememberPlan(for: input)
    }

    func usePreviousPlan(_ plan: NextSessionPlan) {
        edit("Use Previous Plan") { $0.plan = plan }
    }

    /// The plan the circuit remembers from last time, when it is not the one in this project.
    func previousPlan(for input: Input) -> NextSessionPlan? {
        guard let match = circuit(for: input.id), let plan = trackLibrary.definition(id: match.circuit.id)?.plan,
            !plan.experiments.isEmpty, plan != project.plan
        else { return nil }
        return plan
    }

    /// Where the plan is kept besides the project: the circuit's name, or `nil` when none is
    /// recognised.
    func planCircuitName(for input: Input) -> String? {
        circuit(for: input.id).map { trackLibrary.definition(id: $0.circuit.id)?.name ?? $0.circuit.name }
    }

    /// Writes the project's plan onto the circuit's track definition, so the next project here
    /// opens knowing it. A circuit with no definition yet gets one from this input's settings, as
    /// Save Track Definition would make it.
    func rememberPlan(for input: Input) {
        guard let plan = project.plan, let match = circuit(for: input.id) else { return }
        var definition: TrackDefinition
        if let saved = trackLibrary.definition(id: match.circuit.id) {
            definition = saved
        } else {
            guard case .data(let settings) = input.kind else { return }
            definition = TrackDefinition(
                circuitID: match.circuit.id, name: match.circuit.name, latitude: match.circuit.latitude,
                longitude: match.circuit.longitude, startFinish: settings.lapLine, sectors: settings.sectors,
                cornerLabels: settings.cornerLabels)
        }
        guard definition.plan != plan else { return }
        definition.plan = plan
        definition.modified = Date()
        try? trackLibrary.save(definition)
    }
}

/// The Next Session section of the Coaching window (#330): the plan's experiments, editable, and
/// what was planned last time at this circuit.
struct NextSessionPlanView: View {
    let editor: EditorModel
    let input: Input
    let analysis: CoachingAnalysis?
    let lapNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next Session").font(.subheadline.weight(.semibold))
            if let plan = editor.project.plan {
                experiments(plan)
            } else {
                Text(
                    "Three things to try next time, written from the opportunities, kept with the project and "
                        + "remembered for the circuit."
                )
                .foregroundStyle(.secondary)
                HStack {
                    Button("Make a Plan") {
                        if let analysis { editor.makePlan(from: analysis, lapNumber: lapNumber, for: input) }
                    }
                    .disabled(analysis?.opportunities.isEmpty != false)
                    .accessibilityIdentifier("coaching.makePlan")
                }
            }
            if let previous = editor.previousPlan(for: input) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(previous.experiments) { experiment in
                            Text("\(experiment.title): \(experiment.text)").font(.callout)
                        }
                        Button("Use It Again") { editor.usePreviousPlan(previous) }
                            .accessibilityIdentifier("coaching.plan.previous.use")
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Last time at \(editor.planCircuitName(for: input) ?? "this circuit") you planned to try…")
                        .font(.callout)
                }
                .accessibilityIdentifier("coaching.plan.previous")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching.plan")
    }

    private func experiments(_ plan: NextSessionPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(plan.experiments.enumerated()), id: \.element.id) { index, experiment in
                ExperimentRow(experiment: experiment, number: index + 1) { text in
                    editor.setExperimentText(text, id: experiment.id, for: input)
                } remove: {
                    editor.removeExperiment(id: experiment.id, for: input)
                }
            }
            HStack {
                Button("Add Experiment") { editor.addExperiment(for: input) }
                    .accessibilityIdentifier("coaching.plan.add")
                if let analysis, !analysis.opportunities.isEmpty {
                    Button("Start Over") { editor.makePlan(from: analysis, lapNumber: lapNumber, for: input) }
                        .accessibilityIdentifier("coaching.plan.startOver")
                }
                Spacer()
                Text(provenance(plan)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func provenance(_ plan: NextSessionPlan) -> String {
        var parts: [String] = []
        if let lap = plan.fromLap, let phrase = plan.referencePhrase {
            parts.append("From lap \(lap) against \(phrase)")
        }
        if let name = editor.planCircuitName(for: input) {
            parts.append("remembered for \(name)")
        } else {
            parts.append("kept with the project; no circuit recognised to remember it for")
        }
        return parts.joined(separator: " · ")
    }
}

/// One experiment: its corner and an editable line, committed on Return or when focus leaves.
struct ExperimentRow: View {
    let experiment: PlannedExperiment
    let number: Int
    let commit: (String) -> Void
    let remove: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(experiment.title).font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
            TextField("What to try", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { commit(text) }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit(text) } }
                .accessibilityLabel("Experiment \(number)")
                .accessibilityIdentifier("coaching.plan.experiment.\(number)")
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove Experiment \(number)")
                .accessibilityIdentifier("coaching.plan.remove.\(number)")
                .help("Remove this experiment from the plan")
        }
        .onAppear { text = experiment.text }
        // The model is the truth: an undo while the field is focused must show too.
        .onChange(of: experiment.text) { _, new in text = new }
    }
}
